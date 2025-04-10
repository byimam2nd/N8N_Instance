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


nginx_setup() {
  log "$YELLOW" "Install NGINX"
  $SUDO apt install nginx
  log "$YELLOW" "Setup GNINX /etc/nginx/sites-available/n8n.conf"
  $SUDO tee > "/etc/nginx/sites-available/n8n" <<EOF
      server {
          listen 80;
          server_name $DOMAIN;
      
          location / {
              proxy_pass http://localhost:5678;
              proxy_http_version 1.1;
              chunked_transfer_encoding off;
              proxy_buffering off;
              proxy_cache off;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
          }
      }
EOF
log "$YELLOW" "Cek file n8n"
ls /etc/nginx/sites-available/

NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

if [ ! -d "$NGINX_SITES_ENABLED" ]; then
    log "$YELLOW" "Direktori $NGINX_SITES_ENABLED belum ada. Membuat sekarang..."
    $SUDO mkdir /etc/nginx/sites-enabled/
    log "$GREEN" "Direktori berhasil dibuat."
else
    log "$YELLOW" "Direktori $NGINX_SITES_ENABLED sudah ada."
    $SUDO ln -s /etc/nginx/sites-available/n8n.conf /etc/nginx/sites-enabled/
    log "$GREEN" "Membuat symlink direktori."
fi

$SUDO nginx -t
$SUDO systemctl restart nginx
$SUDO apt install certbot python3-certbot-nginx
sudo certbot --nginx -d $DOMAIN
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
  echo "2. Uninstall semua data"
  echo "0. Keluar"
  echo "=============================="
  read -p "Pilih opsi: " OPT
  case $OPT in
    1)
      intro
      install_dep
      nginx_setup
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
