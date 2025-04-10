#!/bin/bash

# ----------------------------
# Bagian atas: Variabel & Konfigurasi
# ----------------------------

CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")

# -------------------------------
# Fungsi untuk menampilkan pesan informasi
# -------------------------------
function info() {
    echo -e "\033[0;32m$1\033[0m"
}

# -------------------------------
# Fungsi untuk menampilkan pesan error
# -------------------------------
function error() {
    echo -e "\033[0;31m$1\033[0m"
}

# -------------------------------
# Fungsi untuk logging
# -------------------------------
function log() {
    echo -e "$1 $2"
}

# -------------------------------
# Fungsi untuk menghapus semua data dan container
# -------------------------------
hapus_semua() {
  log "$YELLOW[*] " "Menghapus semua data dan container..."
  $SUDO docker rm -f $($SUDO docker ps -aqf name=n8n) 2>/dev/null || true
  $SUDO rm -rf "$BASE_DIR"
  $SUDO rm -f /etc/nginx/sites-*/n8n
  $SUDO nginx -t && $SUDO systemctl restart nginx
  log "$GREEN[✓] " "Semua data telah dihapus. Sertifikat SSL tetap dipertahankan."
}

# -------------------------------
# Fungsi untuk setup Docker Compose untuk n8n dengan PostgreSQL
# -------------------------------
docker_compose_setup() {
  if [ -d "$DATA_DIR" ]; then
    log "$GREEN[✓] " "Direktori data n8n sudah ada, melewati setup docker-compose."
  else
    $SUDO mkdir -p "$DATA_DIR"
    log "$YELLOW[*] " "Membuat file .env untuk n8n..."

    # Membuat file .env
    $SUDO cat > "$DATA_DIR/.env" <<EOF
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=$DB_HOST
DB_POSTGRESDB_PORT=$DB_PORT
DB_POSTGRESDB_DATABASE=$DB_NAME
DB_POSTGRESDB_USER=$DB_USER
DB_POSTGRESDB_PASSWORD=$DB_PASSWORD
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD
WEBHOOK_TUNNEL_URL=https://$DOMAIN
EOF

    log "$YELLOW[*] " "Membuat file docker-compose.yml untuk n8n..."

    # Membuat file docker-compose.yml
    $SUDO cat > "$DATA_DIR/docker-compose.yml" <<EOF
version: "3.8"
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    env_file:
      - .env
    volumes:
      - $DATA_DIR:/home/node/.n8n
    depends_on:
      - postgresdb

  postgresdb:
    image: postgres:13
    restart: always
    environment:
      POSTGRES_DB: $DB_NAME
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASSWORD
    volumes:
      - $DATA_DIR/postgres_data:/var/lib/postgresql/data
    ports:
      - "$DB_PORT:5432"
EOF

    # Menjalankan docker-compose
    $SUDO cd "$DATA_DIR" && $SUDO docker-compose up -d
    log "$GREEN[✓] " "Docker Compose untuk n8n berhasil dijalankan."
  fi
}

# -------------------------------
# Fungsi untuk menampilkan menu utama
# -------------------------------
menu_utama() {
  echo "======================================="
  echo "        Menu Manajemen n8n"
  echo "======================================="
  echo "1. Setup n8n dengan PostgreSQL"
  echo "2. Hapus semua data dan container"
  echo "3. Keluar"
  echo -n "Pilih opsi: "
  read pilihan
  case $pilihan in
    1)
      docker_compose_setup
      ;;
    2)
      hapus_semua
      ;;
    3)
      exit 0
      ;;
    *)
      echo "Pilihan tidak valid!"
      menu_utama
      ;;
  esac
}

# Menjalankan menu utama
menu_utama
