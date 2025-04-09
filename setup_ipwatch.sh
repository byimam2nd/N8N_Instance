#!/bin/bash

# Mengambil data variable di gist langsung
CONFIG_FILE="https://gist.github.com/byimam2nd/4b25332b43d59689e759088ad8053f22/raw/data_n8n.conf"
source <(curl -s "$CONFIG_URL")

# -------------------------------
# Bagian Atas: Variabel Konfigurasi
# -------------------------------
DUCKDNS_DOMAIN="exlionn8n.duckdns.org"
DUCKDNS_TOKEN="60e9ee0f-dc88-4206-8e1b-28989c117b96"
TELEGRAM_TOKEN="bot7643811939:AAF60CGNfupKFoyDwN7rT2_Jai3qglUftIw"
TELEGRAM_CHAT_ID="832658254"

SERVICE_NAME="ipwatch"
USERNAME=$(whoami)
HOME_DIR="/home/$USERNAME"
SCRIPT_PATH="$HOME_DIR/ip_watchdog.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
IP_FILE="$HOME_DIR/.last_ip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

# -------------------------------
# Fungsi Kirim Telegram
# -------------------------------
kirim_telegram() {
    curl -s -X POST "https://api.telegram.org/$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        --data-urlencode "text=$1" > /dev/null
}

# -------------------------------
# Fungsi Hapus Instalasi
# -------------------------------
hapus_instalasi() {
    echo -e "${YELLOW}>> Menghapus service dan file terkait...${RESET}"
    sudo systemctl stop $SERVICE_NAME
    sudo systemctl disable $SERVICE_NAME
    sudo rm -f "$SERVICE_FILE"
    rm -f "$SCRIPT_PATH" "$IP_FILE"

    sudo systemctl daemon-reload
    sudo systemctl daemon-reexec

    echo -e "${GREEN}✓ Otomatisasi berhasil dihapus.${RESET}"
    kirim_telegram "🛑 *[IP Watchdog]* Otomatisasi berhasil dihentikan dan semua file dihapus dari sistem."
    exit 0
}

# -------------------------------
# Mode Uninstall Jika Diminta
# -------------------------------
if [[ "$1" == "uninstall" ]]; then
    read -p "Apakah kamu yakin ingin menghapus sistem otomatisasi ini? (y/n): " confirm
    [[ "$confirm" == "y" || "$confirm" == "Y" ]] && hapus_instalasi || exit 0
fi

# -------------------------------
# Bagian Tengah: Script IP Watcher
# -------------------------------
cat <<'EOF' > "$SCRIPT_PATH"
#!/bin/bash

IP_FILE="$HOME/.last_ip"
DUCKDNS_DOMAIN="exlionn8n.duckdns.org"
DUCKDNS_TOKEN="60e9ee0f-dc88-4206-8e1b-28989c117b96"
TELEGRAM_TOKEN="bot7643811939:AAF60CGNfupKFoyDwN7rT2_Jai3qglUftIw"
TELEGRAM_CHAT_ID="832658254"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        --data-urlencode "text=$1"
}

while true; do
    CURRENT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

    if [ ! -f "$IP_FILE" ]; then
        echo "$CURRENT_IP" > "$IP_FILE"
        send_telegram "👀 *[IP Watcher]* Pertama kali mendeteksi IP: \`$CURRENT_IP\`"
    else
        LAST_IP=$(cat "$IP_FILE")
        if [ "$CURRENT_IP" != "$LAST_IP" ]; then
            echo "$CURRENT_IP" > "$IP_FILE"
            curl -s "https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=$CURRENT_IP" > /dev/null

            TEXT="⚠️ *Perubahan IP Terdeteksi!*

*🆕 IP Baru:* \`$CURRENT_IP\`
*📦 IP Lama:* \`$LAST_IP\`

🔄 DuckDNS telah diperbarui dan pengecekan SSL sedang dilakukan. Tetap siaga!"
            send_telegram "$TEXT"

            sudo certbot renew --quiet
        fi
    fi
    sleep 5
done
EOF

chmod +x "$SCRIPT_PATH"

# -------------------------------
# Buat File systemd service
# -------------------------------
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Realtime IP Watcher for DuckDNS + Telegram + SSL Check
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------
# Reload & Aktifkan Service
# -------------------------------
echo -e "${CYAN}>> Menyiapkan service systemd...${RESET}"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME

# -------------------------------
# Kirim Notifikasi Awal
# -------------------------------
kirim_telegram "✅ *Setup Berhasil!* IP Watchdog sekarang aktif di servermu. Aku akan kabari kamu kalau ada perubahan IP!"

# -------------------------------
# Bagian Akhir: Output ke Terminal
# -------------------------------
echo -e "${GREEN}✓ Setup selesai!${RESET}"
echo -e "${CYAN}- Script   :${RESET} $SCRIPT_PATH"
echo -e "${CYAN}- Service  :${RESET} $SERVICE_NAME"
echo -e "${CYAN}- Log IP   :${RESET} $IP_FILE"
