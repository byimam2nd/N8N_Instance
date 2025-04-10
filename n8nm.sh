#!/bin/bash

# Mengambil data variable dengan raw
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")

sudo_controller

# Fungsi untuk menyimpan konfigurasi
function save_config() {
  cat <<EOF > "$CONFIG_FILE"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASSWORD="$DB_PASSWORD"
DB_PORT="$DB_PORT"
DB_HOST="$DB_HOST"
DOMAIN="$DOMAIN"
ENCRYPTION_KEY="$ENCRYPTION_KEY"
GCS_BUCKET_NAME="$GCS_BUCKET_NAME"
TOKEN_TELEGRAM="$TOKEN_TELEGRAM"
PORT="$PORT"
DUCKDNS_TOKEN="$DUCKDNS_TOKEN"
WEBHOOK_PATH="$WEBHOOK_PATH"

EOF
}

# Fungsi setup PostgreSQL
function setup_postgres() {
  

  echo "=== Setup PostgreSQL ==="

  if ! command -v psql > /dev/null; then
    echo "PostgreSQL belum terpasang. Menginstal..."
    $SUDO apt update && $SUDO apt install -y postgresql postgresql-contrib || {
      echo "Gagal menginstal PostgreSQL. Periksa koneksi atau hak akses."
      return
    }
  else
    echo "PostgreSQL sudah terpasang."
  fi

  $SUDO systemctl enable postgresql
  $SUDO systemctl start postgresql

  echo "Cek apakah user '$DB_USER' sudah ada..."
  USER_EXIST=$($SUDO -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")
  if [[ "$USER_EXIST" != "1" ]]; then
    echo "Membuat user '$DB_USER'..."
    $SUDO -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
  else
    echo "User '$DB_USER' sudah ada."
  fi

  echo "Cek apakah database '$DB_NAME' sudah ada..."
  DB_EXIST=$($SUDO -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
  if [[ "$DB_EXIST" != "1" ]]; then
    echo "Membuat database '$DB_NAME' dengan owner '$DB_USER'..."
    $SUDO -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  else
    echo "Database '$DB_NAME' sudah ada."
  fi

  echo "Setup PostgreSQL selesai."
}

# Fungsi cek IP
function cek_ip() {
  echo "IP Internal:"
  $SUDO hostname -I
  echo "IP Eksternal:"
  $SUDO curl -s ifconfig.me || curl -s ipinfo.io/ip
}

# Fungsi jalankan ulang n8n container
function run_n8n() {
  
  echo "Menjalankan ulang container n8n..."
  $SUDO docker stop n8n 2>/dev/null
  $SUDO docker rm n8n 2>/dev/null

  $SUDO docker run -d --restart unless-stopped -it \
    --name n8n \
    -p 5678:5678 \
    --add-host=host.docker.internal:host-gateway \
    -v ~/.n8n:/home/node/.n8n \
    -e N8N_HOST="$DOMAIN" \
    -e WEBHOOK_URL="https://$DOMAIN/" \
    -e WEBHOOK_TUNNEL_URL="https://$DOMAIN/" \
    -e N8N_SECURE_COOKIE=false \
    -e N8N_RUNNERS_ENABLED=true \
    -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    -e N8N_ENCRYPTION_KEY="$ENCRYPTION_KEY" \
    -e DB_TYPE=postgresdb \
    -e DB_POSTGRESDB_DATABASE="$DB_NAME" \
    -e DB_POSTGRESDB_HOST="host.docker.internal" \
    -e DB_POSTGRESDB_PORT="$DB_PORT" \
    -e DB_POSTGRESDB_USER="$DB_USER" \
    -e DB_POSTGRESDB_PASSWORD="$DB_PASSWORD" \
    -e DB_POSTGRESDB_SCHEMA=public \
    n8nio/n8n
  
  if $SUDO docker ps | grep -q "n8n"; then
  $SUDO docker ps
  echo "n8n sudah berjalan."
  else
    $SUDO docker start n8n && echo "n8n berhasil dijalankan."
  fi
}

# Fungsi start container
function start_n8n() {
  echo "Menjalankan container n8n..."
  if $SUDO docker ps | grep -q "n8n"; then
  $SUDO docker ps
  echo "n8n sudah berjalan."
  else
  $SUDO docker start n8n && echo "n8n berhasil dijalankan."
  fi
}

# Fungsi cek koneksi ke DB
function cek_koneksi_db() {
  
  echo "Cek koneksi ke PostgreSQL..."
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME" -c "\dt"
  if [[ $? -ne 0 ]]; then
    echo "Gagal terkoneksi ke database."
  else
    echo "Koneksi database berhasil."
  fi
}

# Fungsi backup ke GCS
function backup_to_bucket() {
  
  BACKUP_FILE="n8n_backup_$(date +%Y%m%d_%H%M%S).sql.gz"

  if [[ -z "$GCS_BUCKET_NAME" ]]; then
    echo "GCS_BUCKET_NAME belum diset. Setup konfigurasi dulu."
    return
  fi

  if ! command -v gsutil > /dev/null; then
    echo "gsutil belum tersedia. Silakan instal terlebih dahulu (Google Cloud SDK)."
    return
  fi

  echo "=== Backup PostgreSQL ke GCS Bucket ==="
  echo "Membackup database..."

  PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME" | gzip > "/tmp/$BACKUP_FILE"

  if [[ $? -ne 0 ]]; then
    echo "Gagal membackup database. Periksa koneksi dan konfigurasi."
    return
  fi

  echo "Upload ke bucket ..."
  gsutil cp "/tmp/$BACKUP_FILE" "gs://$GCS_BUCKET_NAME/" || {
    echo "Gagal upload ke bucket. Periksa GCS_BUCKET_NAME dan akses gsutil."
    return
  }

  echo "Backup selesai: $BACKUP_FILE"
}

# Fungsi restore dari GCS
function restore_from_bucket() {
  

  if [[ -z "$GCS_BUCKET_NAME" ]]; then
    echo "GCS_BUCKET_NAME belum diset. Setup konfigurasi dulu."
    return
  fi

  if ! command -v gsutil > /dev/null; then
    echo "gsutil belum tersedia. Silakan instal terlebih dahulu (Google Cloud SDK)."
    return
  fi

  echo "=== Restore PostgreSQL dari GCS Bucket ==="
  echo "File yang tersedia:"
  gsutil ls "gs://$GCS_BUCKET_NAME/" || return

  read -p "Masukkan nama file untuk restore (contoh: n8n_backup_YYYYMMDD_HHMMSS.sql.gz): " BACKUP_FILE
  LOCAL_FILE="/tmp/$BACKUP_FILE"

  echo "Mengunduh file dari bucket..."
  gsutil cp "gs://$GCS_BUCKET_NAME/$BACKUP_FILE" "$LOCAL_FILE" || {
    echo "Gagal mengunduh file dari bucket."
    return
  }

  echo "Melakukan restore ke database..."
  gunzip -c "$LOCAL_FILE" | PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME"
}

hapus_backup_lama() {
  source "$CONFIG_FILE"
  echo "Cek dan hapus backup lama di bucket GCS ($GCS_BUCKET_NAME)..."

  BACKUP_LIST=$(gsutil ls -l "gs://$GCS_BUCKET_NAME/" | grep -E 'n8n_backup_.*\.sql\.gz' | sort -k2 | awk '{print $NF}')
  BACKUP_COUNT=$(echo "$BACKUP_LIST" | wc -l)

  if [[ "$BACKUP_COUNT" -le 10 ]]; then
    echo "Backup hanya ada $BACKUP_COUNT. Tidak ada yang dihapus."
    return
  fi

  FILES_TO_DELETE=$(echo "$BACKUP_LIST" | head -n $(($BACKUP_COUNT - 10)))
  echo "Menghapus $((BACKUP_COUNT - 10)) file backup lama..."
  for FILE in $FILES_TO_DELETE; do
    echo "-> Menghapus: $FILE"
    gsutil rm "$FILE"
  done

  echo "Selesai menghapus backup lama. Backup tersisa: 10."
}

# Fungsi untuk mengelola webhook Telegram
webhook_menu() {
    
    #clear
    echo "======================================="
    echo " 📡 Kelola Webhook Telegram"
    echo "======================================="
    echo "1) Cek Webhook"
    echo "2) Hapus Webhook"
    echo "3) Atur Webhook"
    echo "4) Kembali"
    echo "======================================="
    read -p "Masukkan pilihan [1-4]: " WEBHOOK_OPTION
    
    if ! command -v jq > /dev/null; then
      echo "jq belum terpasang. Menginstal..."
      $SUDO apt install -y jq || {
      echo "Gagal menginstal jq!"
      return
      }
    fi
    
    case $WEBHOOK_OPTION in
        1)
            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/getWebhookInfo"
            echo "🔍 Mengambil informasi webhook..."
            curl -s "$API_URL" | jq .
            sleep 2
            webhook_menu
        ;;
        2)
            echo "⚠️ Anda akan menghapus webhook. Lanjutkan?"
            read -p "(y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                echo "❌ Operasi dibatalkan."
                sleep 1
                webhook_menu
            fi

            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/deleteWebhook"
            echo "❌ Menghapus webhook..."
            curl -s "$API_URL" | jq .
            sleep 2
            webhook_menu
        ;;
        3)
            PROTOCOL="https"
            WEBHOOK_URL="$PROTOCOL://$DOMAIN$WEBHOOK_PATH"
            echo "======================================="
            echo "🔗 URL Webhook Target: $WEBHOOK_URL"
            echo "======================================="
            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/setWebhook?url=$WEBHOOK_URL"
            echo "🔍 Permintaan ke Telegram API:"
            echo "$API_URL"
            echo "======================================="
            
            read -p "Lanjutkan mengatur webhook ini? (y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                echo "❌ Operasi dibatalkan."
                sleep 1
                webhook_menu
            fi

            RESPONSE=$(curl -s "$API_URL")

            echo "📨 Respons dari Telegram:"
            echo "$RESPONSE" | jq .

            if echo "$RESPONSE" | grep -q '"ok":true'; then
                echo "✅ Webhook berhasil diatur!"
            else
                echo "❌ Gagal mengatur webhook!"
            fi
            sleep 2
            webhook_menu
        ;;
        4) main_menu ;;
        *) echo "❌ Pilihan tidak valid!"; sleep 1; webhook_menu ;;
    esac
}
# Fungsi untuk mengelola DuckDNS
duckdns_menu() {
    
    echo "======================================="
    echo " 🦆 Update IP DuckDNS"
    echo "======================================="
            # Ambil IP eksternal otomatis
            external_ip=$(curl -s ifconfig.me)
            if [[ -z "$external_ip" ]]; then
                echo "❌ Gagal mendapatkan IP eksternal!"
                sleep 2
                main_menu
            fi

            API_URL="https://www.duckdns.org/update?domains=$DOMAIN&token=$DUCKDNS_TOKEN&ip=$external_ip"
            echo "======================================="
            echo "🌐 IP Eksternal: $external_ip"
            echo "🔄 URL Update DuckDNS: $API_URL"
            echo "======================================="

            read -p "Lanjutkan update DuckDNS? (y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                echo "❌ Operasi dibatalkan."
                sleep 1
                main_menu
            fi

            response=$(curl -s "$API_URL")
            if [[ "$response" == "OK" ]]; then
                echo "✅ DuckDNS berhasil diperbarui!"
            else
                echo "❌ Gagal update DuckDNS. Respon: $response"
            fi
            sleep 2
            main_menu
}

function main_menu() {
  while true; do
    echo "======================================="
    echo "         🛠️  MENU UTAMA n8n TOOL"
    echo "======================================="
    echo "1) Setup PostgreSQL"
    echo "2) Jalankan n8n (start container)"
    echo "3) Set config ulang n8n & Jalankan"
    echo "4) Cek IP Internal & Eksternal"
    echo "5) Cek Koneksi DB"
    echo "6) Backup ke GCS Bucket"
    echo "7) Restore dari GCS Bucket"
    echo "8) Hapus Backup lama GCS Bucket lebih dari 10 list"
    echo "9) Management Telegram Webhook"
    echo "10) Management DuckDNS"
    echo "0) Keluar"
    echo "---------------------------------------"
    read -p "Pilih menu [0-10]: " MENU
    case $MENU in
      1) setup_postgres ;;
      2) start_n8n ;;
      3) run_n8n ;;
      4) cek_ip ;;
      5) cek_koneksi_db ;;
      6) backup_to_bucket ;;
      7) restore_from_bucket ;;
      8) hapus_backup_lama ;;
      9) webhook_menu ;;
      10) duckdns_menu ;;
      0) echo "Keluar..."; exit 0 ;;
      *) echo "Pilihan tidak valid!" ;;
    esac
  done
}

#executor
main_menu
