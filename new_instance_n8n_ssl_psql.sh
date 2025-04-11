#!/bin/bash

# ===============================
# BAGIAN ATAS: VARIABEL & VALUE
# ===============================
CONFIG_FILE="./data_n8n.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "File konfigurasi tidak ditemukan!"
  exit 1
fi

log() { echo -e "$1$2${RESET}"; }

# ===============================
# BAGIAN TENGAH: FUNGSI & LOGIKA
# ===============================

install_docker() {
  if ! command -v docker &> /dev/null; then
    log "$YELLOW" "Menginstal Docker..."
    $SUDO apt update
    $SUDO apt install -y docker.io
    log "$GREEN" "Docker berhasil diinstal."
  else
    log "$CYAN" "Docker sudah terpasang."
  fi
}

install_docker_compose() {
  if ! command -v docker compose &> /dev/null; then
    log "$YELLOW" "Menginstal Docker Compose Plugin..."
    $SUDO apt install -y docker-compose-plugin
    log "$GREEN" "Docker Compose berhasil diinstal."
  else
    log "$CYAN" "Docker Compose sudah terpasang."
  fi
}

buat_docker_compose() {
  log "$BLUE" "Membuat direktori $BASE_DIR dan file docker-compose.yml..."
  mkdir -p "$BASE_DIR"
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: always
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.duckdns.acme.httpchallenge=true"
      - "--certificatesresolvers.duckdns.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.duckdns.acme.email=${EMAIL}"
      - "--certificatesresolvers.duckdns.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${SSL_DIR}:/letsencrypt

  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: always
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${DB_HOST}
      - DB_POSTGRESDB_PORT=${DB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_NAME}
      - DB_POSTGRESDB_USER=${DB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${BASIC_AUTH_PASSWORD}
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${DOMAIN}
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - GENERIC_TIMEZONE=Asia/Jakarta
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
    ports:
      - "${PORT}:${PORT}"
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=duckdns"
      - "traefik.http.services.n8n.loadbalancer.server.port=${PORT}"
EOF

  log "$GREEN" "File docker-compose.yml berhasil dibuat."
}

jalankan_docker_compose() {
  log "$BLUE" "Menjalankan docker compose up -d..."
  cd "$BASE_DIR"
  $SUDO docker compose up -d
  log "$GREEN" "n8n & Traefik berhasil dijalankan."
}

# ===============================
# BAGIAN AKHIR: UI & EKSEKUSI
# ===============================
log "$CYAN" "=== PROSES INSTALL n8n INSTANCE ==="
install_docker
install_docker_compose
buat_docker_compose
jalankan_docker_compose
log "$MAGENTA" "✅ n8n siap diakses di: https://${DOMAIN}"
