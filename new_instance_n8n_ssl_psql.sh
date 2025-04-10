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
  echo "2. Ambil sertifikat SSL dari Let's Encrypt ($DOMAIN)"
  echo "3. Setup HTTPS reverse proxy NGINX"
  echo "4. Hubungkan ke DB Neon PostgreSQL"
  echo "5. Aktifkan login basic auth ($BASIC_AUTH_USER)"
  echo "6. Simpan data di $DATA_DIR"
  echo "7. Otomatis jalankan dan restart container n8n"
  echo "8. Jalankan ulang dengan: docker start \$(docker ps -aqf name=n8n)"
  echo
}

pkg_manager() {
  command -v apt &> /dev/null && INSTALL="$SUDO apt update && $SUDO apt install -y"
  command -v dnf &> /dev/null && INSTALL="$SUDO dnf install -y"
  command -v yum &> /dev/null && INSTALL="$SUDO yum install -y"
  [[ -z "$INSTALL" ]] && log "$RED[ERROR] " "Package manager tidak ditemukan!" && exit 1
}

# Cek apakah dependency sudah terinstal
install_dep() {
  pkg_manager
  if ! command -v docker &> /dev/null; then
    eval "$INSTALL docker.io docker-compose nginx certbot psmisc" || eval "$INSTALL docker docker-compose nginx certbot psmisc"
  else
    log "$GREEN[✓] " "Docker, Docker Compose, NGINX, dan Certbot sudah terinstal."
  fi
}

# Cek sertifikat SSL, jika sudah ada, lewati
get_ssl() {
  if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "$GREEN[✓] " "Sertifikat SSL sudah ada, melewati pengambilan sertifikat."
  else
    $SUDO fuser -k 80/tcp || true
    $SUDO systemctl stop nginx
    $SUDO certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" || {
      log "$RED[ERROR] " "Gagal ambil sertifikat SSL."; exit 1; }
    $SUDO systemctl start nginx
    log "$GREEN[✓] " "Sertifikat SSL berhasil diambil."
  fi
}

# Fungsi untuk memastikan file sertifikat dan kunci memiliki izin yang benar
fix_ssl_permissions() {
  log "$YELLOW[*] " "Memperbaiki izin file sertifikat SSL..."
  $SUDO chmod 644 /etc/letsencrypt/archive/$DOMAIN/*.pem
  $SUDO chown root:www-data /etc/letsencrypt/archive/$DOMAIN/*.pem
  $SUDO chmod 644 /etc/letsencrypt/live/$DOMAIN/*.pem
  $SUDO chown root:www-data /etc/letsencrypt/live/$DOMAIN/*.pem
  log "$GREEN[✓] " "Izin file sertifikat telah diperbaiki."
}

nginx_conf() {
  if [ -f "/etc/nginx/sites-available/n8n" ]; then
    log "$GREEN[✓] " "Konfigurasi NGINX untuk n8n sudah ada, melewati konfigurasi."
  else
    log "$YELLOW[*] " "Membuat konfigurasi NGINX untuk n8n..."
    $SUDO tee /etc/nginx/sites-available/n8n > /dev/null <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}
server {
  listen 443 ssl;
  server_name $DOMAIN;
  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
  location / {
    proxy_pass http://localhost:5678;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
    $SUDO ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
    $SUDO nginx -t && $SUDO systemctl restart nginx
    log "$GREEN[✓] " "Konfigurasi NGINX berhasil."
  fi
}

docker_compose_setup() {
  if [ -d "$DATA_DIR" ]; then
    log "$GREEN[✓] " "Direktori data n8n sudah ada, melewati setup docker-compose."
  else
    mkdir -p "$DATA_DIR"
    log "$YELLOW[*] " "Membuat file .env untuk n8n..."
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

    log "$YELLOW[*] " "Membuat file docker-compose.yml untuk n8n..."
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
    log "$GREEN[✓] " "Docker Compose untuk n8n berhasil dijalankan."
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
      get_ssl
      fix_ssl_permissions  # Perbaiki izin file sertifikat SSL
      nginx_conf
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
