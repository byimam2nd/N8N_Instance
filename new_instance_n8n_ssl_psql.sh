#!/bin/bash

# ----------------------------
# Bagian atas: Variabel & Konfigurasi
# ----------------------------

# Mengambil data variable dengan raw
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

install_dep() {
  pkg_manager
  eval "$INSTALL docker.io docker-compose nginx certbot psmisc" || eval "$INSTALL docker docker-compose nginx certbot psmisc"
}

get_ssl() {
  $SUDO fuser -k 80/tcp || true
  $SUDO systemctl stop nginx
  $SUDO certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" || {
    log "$RED[ERROR] " "Gagal ambil sertifikat SSL."; exit 1; }
  $SUDO systemctl start nginx
}

nginx_conf() {
  $SUDO tee /etc/nginx/sites-available/n8n > /dev/null <<EOF
server { listen 80; server_name $DOMAIN; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl; server_name $DOMAIN;
  ssl_certificate $SSL_DIR/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key $SSL_DIR/live/$DOMAIN/privkey.pem;
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
}

docker_compose_setup() {
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
  echo "2. Set NGINX (SSL & Config)"
  echo "3. Uninstall semua data"
  echo "0. Keluar"
  echo "=============================="
  read -p "Pilih opsi: " OPT
  case $OPT in
    1)
      intro
      install_dep
      docker_compose_setup
      log "$GREEN[✓] " "Instalasi selesai!"
      echo "Akses: https://$DOMAIN"
      echo "Login: $BASIC_AUTH_USER | $BASIC_AUTH_PASSWORD"
      ;;
    2)
      log "$BLUE[*] " "Menjalankan pengaturan NGINX dan SSL..."
      get_ssl
      nginx_conf
      log "$GREEN[✓] " "Pengaturan NGINX selesai!"
      ;;
    3) hapus_semua ;;
    0) exit ;;
    *) log "$RED[!] " "Pilihan tidak valid." ;;
  esac
}

menu
