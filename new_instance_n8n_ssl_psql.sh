#!/bin/bash

# ===============================
# BAGIAN ATAS: VARIABEL & VALUE
# ===============================
# Get Universal Variable
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")
# Get Universal Function
FUNC_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/universal_lib_func.sh"
source <(curl -s "$FUNC_FILE")


# ===============================
# BAGIAN TENGAH: FUNGSI & LOGIKA
# ===============================

install_docker() {
  log "$YELLOW" "Remove incompatible or out of date Docker implementations if they exist"
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
  log "$YELLOW" "Install pre requirment packages"
  sudo apt-get update
  sudo apt-get install ca-certificates curl
  log "$YELLOW" "Download the repo signing key"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  log "$YELLOW" "Configure the repository"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  log "$GREEN" "Update and install Docker and Docker Compose"
  sudo apt-get update
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

setup_docker() {
  log "$BLUE" "chmod 600 for .../data/config"
  $SUDO chmod 600 /home/byimam2nd/n8n_instance/data/config
}

buat_docker_compose() {
  log "$BLUE" "Membuat direktori $BASE_DIR dan file docker-compose.yml..."
  mkdir -p "$BASE_DIR"
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
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
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${BASIC_AUTH_PASSWORD}
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=${PORT}
      - WEBHOOK_URL=https://${DOMAIN}
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - GENERIC_TIMEZONE=Asia/Jakarta
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_AUTH_TOKEN=${ENCRYPTION_KEY}
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
  log "$YELLOW" "Membuat izin chown -R"
  sudo chown -R 1000:1000 /home/byimam2nd/n8n_instance/data
  log "$BLUE" "Menjalankan docker-compose up -d..."
  cd "$BASE_DIR"
  $SUDO docker-compose up -d
  log "$GREEN" "n8n & Traefik berhasil dijalankan."
}

update_docker_compose() {
  log "$BLUE" "Memperbarui docker-compose.yml..."
  $SUDO docker stop n8n traefik
  $SUDO docker rm n8n traefik

  # Backup
  cp "$BASE_DIR/docker-compose.yml" "$BASE_DIR/docker-compose.yml.bak"

  # Buat ulang dan jalankan
  buat_docker_compose
  jalankan_docker_compose
}

# ===============================
# BAGIAN AKHIR: UI & EKSEKUSI
# ===============================

echo -e "${CYAN}"
echo "===== MENU n8n INSTANCE ====="
echo "1. Install n8n"
echo "2. Update docker-compose.yml"
echo "3. Keluar"
echo -ne "${RESET}Pilih opsi [1-3]: "
read opsi

case $opsi in
  1)
    log "$CYAN" "=== PROSES INSTALL n8n INSTANCE ==="
    install_docker
    setup_docker
    buat_docker_compose
    jalankan_docker_compose
    log "$MAGENTA" "✅ n8n siap diakses di: https://${DOMAIN}"
    log "$GREEN" "✅ dan cek dengan -sudo docker logs -f n8n"
    ;;
  2)
    update_docker_compose
    log "$YELLOW" "Updated compose selesai."
    ;;
  3)
    log "$RED" "Keluar dari program."
    exit 0
    ;;
  *)
    log "$RED" "Opsi tidak valid."
    ;;
esac

