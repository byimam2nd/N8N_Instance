#!/bin/bash

# Mengambil data variable dengan raw
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")
FUNC_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/universal_lib_func.sh"
source <(curl -s "$FUNC_FILE")

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
  

  log "=== Setup PostgreSQL ==="

  if ! command -v psql > /dev/null; then
    log "PostgreSQL belum terpasang. Menginstal..."
    $SUDO apt update && $SUDO apt install -y postgresql postgresql-contrib || {
      log "Gagal menginstal PostgreSQL. Periksa koneksi atau hak akses."
      return
    }
  else
    log "PostgreSQL sudah terpasang."
  fi

  $SUDO systemctl enable postgresql
  $SUDO systemctl start postgresql

  log "Cek apakah user '$DB_USER' sudah ada..."
  USER_EXIST=$($SUDO -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")
  if [[ "$USER_EXIST" != "1" ]]; then
    log "Membuat user '$DB_USER'..."
    $SUDO -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
  else
    log "User '$DB_USER' sudah ada."
  fi

  log "Cek apakah database '$DB_NAME' sudah ada..."
  DB_EXIST=$($SUDO -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
  if [[ "$DB_EXIST" != "1" ]]; then
    log "Membuat database '$DB_NAME' dengan owner '$DB_USER'..."
    $SUDO -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  else
    log "Database '$DB_NAME' sudah ada."
  fi

  log "Setup PostgreSQL selesai."
}

# Fungsi cek IP
function cek_ip() {
  log "IP Internal:"
  $SUDO hostname -I
  log "IP Eksternal:"
  $SUDO curl -s ifconfig.me || curl -s ipinfo.io/ip
}

# Fungsi jalankan ulang n8n container
function run_n8n() {
  
  log "Menjalankan ulang container n8n..."
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
  log "n8n sudah berjalan."
  else
    $SUDO docker start n8n && log "n8n berhasil dijalankan."
  fi
}

# Fungsi start container
function start_n8n() {
  log "Menjalankan container n8n..."
  if $SUDO docker ps | grep -q "n8n"; then
  $SUDO docker ps
  log "n8n sudah berjalan."
  else
  $SUDO docker start n8n && log "n8n berhasil dijalankan."
  fi
}

# Fungsi cek koneksi ke DB
function cek_koneksi_db() {
  
  log "Cek koneksi ke PostgreSQL..."
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME" -c "\dt"
  if [[ $? -ne 0 ]]; then
    log "Gagal terkoneksi ke database."
  else
    log "Koneksi database berhasil."
  fi
}

# Fungsi backup ke GCS
function backup_to_bucket() {
  
  BACKUP_FILE="n8n_backup_$(date +%Y%m%d_%H%M%S).sql.gz"

  if [[ -z "$GCS_BUCKET_NAME" ]]; then
    log "GCS_BUCKET_NAME belum diset. Setup konfigurasi dulu."
    return
  fi

  if ! command -v gsutil > /dev/null; then
    log "gsutil belum tersedia. Silakan instal terlebih dahulu (Google Cloud SDK)."
    return
  fi

  log "=== Backup PostgreSQL ke GCS Bucket ==="
  log "Membackup database..."

  PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME" | gzip > "/tmp/$BACKUP_FILE"

  if [[ $? -ne 0 ]]; then
    log "Gagal membackup database. Periksa koneksi dan konfigurasi."
    return
  fi

  log "Upload ke bucket ..."
  gsutil cp "/tmp/$BACKUP_FILE" "gs://$GCS_BUCKET_NAME/" || {
    log "Gagal upload ke bucket. Periksa GCS_BUCKET_NAME dan akses gsutil."
    return
  }

  log "Backup selesai: $BACKUP_FILE"
}

# Fungsi restore dari GCS
function restore_from_bucket() {
  

  if [[ -z "$GCS_BUCKET_NAME" ]]; then
    log "GCS_BUCKET_NAME belum diset. Setup konfigurasi dulu."
    return
  fi

  if ! command -v gsutil > /dev/null; then
    log "gsutil belum tersedia. Silakan instal terlebih dahulu (Google Cloud SDK)."
    return
  fi

  log "=== Restore PostgreSQL dari GCS Bucket ==="
  log "File yang tersedia:"
  gsutil ls "gs://$GCS_BUCKET_NAME/" || return

  read -p "Masukkan nama file untuk restore (contoh: n8n_backup_YYYYMMDD_HHMMSS.sql.gz): " BACKUP_FILE
  LOCAL_FILE="/tmp/$BACKUP_FILE"

  log "Mengunduh file dari bucket..."
  gsutil cp "gs://$GCS_BUCKET_NAME/$BACKUP_FILE" "$LOCAL_FILE" || {
    log "Gagal mengunduh file dari bucket."
    return
  }

  log "Melakukan restore ke database..."
  gunzip -c "$LOCAL_FILE" | PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -d "$DB_NAME"
}

hapus_backup_lama() {
  source "$CONFIG_FILE"
  log "Cek dan hapus backup lama di bucket GCS ($GCS_BUCKET_NAME)..."

  BACKUP_LIST=$(gsutil ls -l "gs://$GCS_BUCKET_NAME/" | grep -E 'n8n_backup_.*\.sql\.gz' | sort -k2 | awk '{print $NF}')
  BACKUP_COUNT=$(log "$BACKUP_LIST" | wc -l)

  if [[ "$BACKUP_COUNT" -le 10 ]]; then
    log "Backup hanya ada $BACKUP_COUNT. Tidak ada yang dihapus."
    return
  fi

  FILES_TO_DELETE=$(log "$BACKUP_LIST" | head -n $(($BACKUP_COUNT - 10)))
  log "Menghapus $((BACKUP_COUNT - 10)) file backup lama..."
  for FILE in $FILES_TO_DELETE; do
    log "-> Menghapus: $FILE"
    gsutil rm "$FILE"
  done

  log "Selesai menghapus backup lama. Backup tersisa: 10."
}

# Fungsi untuk mengelola webhook Telegram
webhook_menu() {
    
    #clear
    log "======================================="
    log " 📡 Kelola Webhook Telegram"
    log "======================================="
    log "1) Cek Webhook"
    log "2) Hapus Webhook"
    log "3) Atur Webhook"
    log "4) Kembali"
    log "======================================="
    read -p "Masukkan pilihan [1-4]: " WEBHOOK_OPTION
    
    if ! command -v jq > /dev/null; then
      log "jq belum terpasang. Menginstal..."
      $SUDO apt install -y jq || {
      log "Gagal menginstal jq!"
      return
      }
    fi
    
    case $WEBHOOK_OPTION in
        1)
            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/getWebhookInfo"
            log "🔍 Mengambil informasi webhook..."
            curl -s "$API_URL" | jq .
            sleep 2
            webhook_menu
        ;;
        2)
            log "⚠️ Anda akan menghapus webhook. Lanjutkan?"
            read -p "(y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                log "❌ Operasi dibatalkan."
                sleep 1
                webhook_menu
            fi

            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/deleteWebhook"
            log "❌ Menghapus webhook..."
            curl -s "$API_URL" | jq .
            sleep 2
            webhook_menu
        ;;
        3)
            PROTOCOL="https"
            WEBHOOK_URL="$PROTOCOL://$DOMAIN$WEBHOOK_PATH"
            log "======================================="
            log "🔗 URL Webhook Target: $WEBHOOK_URL"
            log "======================================="
            API_URL="https://api.telegram.org/bot$TOKEN_TELEGRAM/setWebhook?url=$WEBHOOK_URL"
            log "🔍 Permintaan ke Telegram API:"
            log "$API_URL"
            log "======================================="
            
            read -p "Lanjutkan mengatur webhook ini? (y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                log "❌ Operasi dibatalkan."
                sleep 1
                webhook_menu
            fi

            RESPONSE=$(curl -s "$API_URL")

            log "📨 Respons dari Telegram:"
            log "$RESPONSE" | jq .

            if log "$RESPONSE" | grep -q '"ok":true'; then
                log "✅ Webhook berhasil diatur!"
            else
                log "❌ Gagal mengatur webhook!"
            fi
            sleep 2
            webhook_menu
        ;;
        4) main_menu ;;
        *) log "❌ Pilihan tidak valid!"; sleep 1; webhook_menu ;;
    esac
}
# Fungsi untuk mengelola DuckDNS
duckdns_menu() {
    
    log "======================================="
    log " 🦆 Update IP DuckDNS"
    log "======================================="
            # Ambil IP eksternal otomatis
            external_ip=$(curl -s ifconfig.me)
            if [[ -z "$external_ip" ]]; then
                log "❌ Gagal mendapatkan IP eksternal!"
                sleep 2
                main_menu
            fi

            API_URL="https://www.duckdns.org/update?domains=$DOMAIN&token=$DUCKDNS_TOKEN&ip=$external_ip"
            log "======================================="
            log "🌐 IP Eksternal: $external_ip"
            log "🔄 URL Update DuckDNS: $API_URL"
            log "======================================="

            read -p "Lanjutkan update DuckDNS? (y/n): " CONFIRM
            if [[ "$CONFIRM" != "y" && "$CONFIRM" != "" ]]; then
                log "❌ Operasi dibatalkan."
                sleep 1
                main_menu
            fi

            response=$(curl -s "$API_URL")
            if [[ "$response" == "OK" ]]; then
                log "✅ DuckDNS berhasil diperbarui!"
            else
                log "❌ Gagal update DuckDNS. Respon: $response"
            fi
            sleep 2
            main_menu
}

function main_menu() {
  while true; do
    log "======================================="
    log "         🛠️  MENU UTAMA n8n TOOL"
    log "======================================="
    log "1) Setup PostgreSQL"
    log "2) Jalankan n8n (start container)"
    log "3) Set config ulang n8n & Jalankan"
    log "4) Cek IP Internal & Eksternal"
    log "5) Cek Koneksi DB"
    log "6) Backup ke GCS Bucket"
    log "7) Restore dari GCS Bucket"
    log "8) Hapus Backup lama GCS Bucket lebih dari 10 list"
    log "9) Management Telegram Webhook"
    log "10) Management DuckDNS"
    log "0) Keluar"
    log "---------------------------------------"
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
      0) log "Keluar..."; exit 0 ;;
      *) log "Pilihan tidak valid!" ;;
    esac
  done
}

#executor
main_menu
