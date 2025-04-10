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
# Fungsi untuk setup Nginx
# -------------------------------
setup_nginx() {
  log "$YELLOW[*] " "Mengonfigurasi Nginx untuk reverse proxy..."

  # Pastikan direktori tersedia
  $SUDO mkdir -p /etc/nginx/sites-available
  $SUDO mkdir -p /etc/nginx/sites-enabled

  # Hapus file konfigurasi lama jika ada
  $SUDO rm -f /etc/nginx/sites-available/n8n
  $SUDO rm -f /etc/nginx/sites-enabled/n8n

  # Buat file konfigurasi baru
  echo "server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}" | $SUDO tee /etc/nginx/sites-available/n8n > /dev/null

  # Buat symlink
  $SUDO ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n

  # Tes dan restart nginx
  if $SUDO nginx -t; then
    $SUDO systemctl restart nginx
    log "$GREEN[✓] " "Konfigurasi Nginx berhasil dan Nginx telah di-restart."
  else
    error "[X] Konfigurasi Nginx gagal! Cek file secara manual."
    exit 1
  fi
}

# -------------------------------
# Fungsi untuk setup SSL menggunakan Certbot
# -------------------------------
setup_ssl() {
  log "$YELLOW[*] " "Menyiapkan SSL dengan Certbot..."

  # Install Certbot dan plugin
  $SUDO apt update
  $SUDO apt install -y certbot python3-certbot-nginx

  # Jalankan Certbot
  if $SUDO certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN; then
    log "$GREEN[✓] " "SSL berhasil dipasang untuk $DOMAIN."
  else
    error "[X] Gagal memasang SSL dengan Certbot!"
    exit 1
  fi
}

# -------------------------------
# Fungsi untuk setup Docker Compose
# -------------------------------
docker_compose_setup() {
  if [ -d "$DATA_DIR" ]; then
    log "$GREEN[✓] " "Direktori data n8n sudah ada, melewati setup docker-compose."
  else
    $SUDO mkdir -p "$DATA_DIR"
    log "$YELLOW[*] " "Membuat file .env untuk n8n..."

    # Membuat file .env
    echo "DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=$DB_HOST
DB_POSTGRESDB_PORT=$DB_PORT
DB_POSTGRESDB_DATABASE=$DB_NAME
DB_POSTGRESDB_USER=$DB_USER
DB_POSTGRESDB_PASSWORD=$DB_PASSWORD
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD
WEBHOOK_TUNNEL_URL=https://$DOMAIN" | $SUDO tee "$DATA_DIR/.env" > /dev/null

    log "$YELLOW[*] " "Membuat file docker-compose.yml..."

    # Membuat docker-compose.yml
    echo "version: '3.8'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - '5678:5678'
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
      - '$DB_PORT:5432'" | $SUDO tee "$DATA_DIR/docker-compose.yml" > /dev/null

    # Jalankan Docker Compose
    $SUDO docker compose -f "$DATA_DIR/docker-compose.yml" up -d
    log "$GREEN[✓] " "Docker Compose untuk n8n berhasil dijalankan."
  fi
}

# -------------------------------
# Program utama
# -------------------------------
log "$YELLOW[*] " "Memulai instalasi otomatis n8n..."
docker_compose_setup
setup_nginx
setup_ssl
log "$GREEN[✓] " "Instalasi selesai! Akses: https://$DOMAIN"
