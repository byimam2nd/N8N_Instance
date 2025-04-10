#!/bin/bash

# ----------------------------
# Bagian atas: Variabel & Konfigurasi
# ----------------------------

CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")

# ----------------------------
# Bagian tengah: Fungsi & Logika
# ----------------------------

log() { echo -e "$1$2${RESET}"; }
typewriter() { while IFS= read -r -n1 c; do printf "%s" "$c"; sleep "${2:-0.02}"; done <<< "$1"; echo; }

intro() {
  echo; echo "Deskripsi Proses:"
  echo "1. Install Docker, Docker Compose, NGINX, Certbot"
  echo "2. Setup HTTPS reverse proxy NGINX"
  echo "3. Install SSL menggunakan Certbot"
  echo "4. Hubungkan ke DB Neon PostgreSQL"
  echo "5. Aktifkan login basic auth ($BASIC_AUTH_USER)"
  echo "6. Simpan data di $DATA_DIR"
  echo "7. Jalankan dan restart container n8n"
  echo "8. Jalankan ulang dengan: docker start \$(docker ps -aqf name=n8n)"
  echo
}

pkg_manager() {
  command -v apt &> /dev/null && INSTALL="$SUDO apt update && $SUDO apt install -y"
  command -v dnf &> /dev/null && INSTALL="$SUDO dnf install -y"
  command -v yum &> /dev/null && INSTALL="$SUDO yum install -y"
  [[ -z "$INSTALL" ]] && log "$RED[ERROR] " "Package manager tidak ditemukan!" && exit 1
}

install_dep() {
  pkg_manager
  # Cek jika Docker, Docker Compose, NGINX, dan Certbot sudah terpasang
  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null || ! command -v nginx &> /dev/null || ! command -v certbot &> /dev/null; then
    eval "$INSTALL docker.io docker-compose nginx certbot psmisc" || eval "$INSTALL docker docker-compose nginx certbot psmisc"
  else
    log "$GREEN[✓] " "Docker, Docker Compose, NGINX, dan Certbot sudah terinstal."
  fi
}

nginx_conf() {
  # Pastikan direktori sites-enabled ada
  $SUDO mkdir -p /etc/nginx/sites-enabled

  # Cek jika konfigurasi NGINX sudah ada
  if [ -f "/etc/nginx/sites-available/n8n" ]; then
    log "$GREEN[✓] " "Konfigurasi NGINX untuk n8n sudah ada, melewati konfigurasi."
  else
    # Buat konfigurasi NGINX untuk n8n
    log "$YELLOW[*] " "Membuat konfigurasi NGINX untuk n8n..."
    $SUDO tee /etc/nginx/sites-available/n8n > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    # Enable konfigurasi NGINX
    $SUDO ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

    # Test dan restart NGINX
    $SUDO nginx -t && $SUDO systemctl restart nginx
  fi
}

get_ssl() {
  # Cek jika sertifikat SSL sudah ada
  if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "$GREEN[✓] " "Sertifikat SSL sudah ada, melewati pengambilan sertifikat."
  else
    log "$YELLOW[*] " "Mengambil sertifikat SSL menggunakan Certbot..."
    $SUDO apt install -y certbot python3-certbot-nginx
    $SUDO certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" || {
      log "$RED[ERROR] " "Gagal ambil sertifikat SSL."; exit 1; }
    log "$GREEN[✓] " "Sertifikat SSL telah diterapkan untuk $DOMAIN."
  fi
}

docker_compose_setup() {
  # Cek jika direktori data sudah ada
  if [ -d "$DATA_DIR" ]; then
    log "$GREEN[✓] " "Direktori data n8n sudah ada, melewati setup docker-compose."
  else
    mkdir -p "$DATA_DIR"

    # Buat file .env
    cat > "$DATA_DIR/.env" <<EOF
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

    # Buat docker-compose.yml
    cat > "$DATA_DIR/docker-compose.yml" <<EOF
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
EOF

    cd "$DATA_DIR" && $SUDO docker-compose up -d
  fi
}

hapus_semua() {
  log "$YELLOW[*] " "Menghapus semua data dan container..."
  $SUDO docker rm -f $($SUDO docker ps -aqf name=n8n) 2>/dev/null || true
  $SUDO rm -rf "$BASE_DIR"
  $SUDO rm -f /etc/nginx/sites-*/n8n
  $SUDO nginx -t && $SUDO systemctl restart nginx
  log "$GREEN[✓] " "Semua data telah dihapus. Sertifikat SSL tetap dipertahankan."
}

# ----------------------------
# Bagian akhir: Menu Interaktif & Eksekusi
# ----------------------------

menu() {
  echo -e "${BLUE}========== MENU N8N ==========${RESET}"
  echo "1. Install n8n + SSL + PostgreSQL"
  echo "2. Uninstall semua data"
  echo "0. Keluar"
  echo "=============================="
  read -p "Pilih opsi: " OPT
  case $OPT in
    1)
      intro
      install_dep
      nginx_conf
      get_ssl
      docker_compose_setup
      log "$GREEN[✓] " "Instalasi selesai!"
      echo "Akses: https://$DOMAIN"
      echo "Login: $BASIC_AUTH_USER | $BASIC_AUTH_PASSWORD"
      ;;
    2) hapus_semua ;;
    0) exit ;;
    *) log "$RED[!] " "Pilihan tidak valid." ;;
  esac
}

menu
