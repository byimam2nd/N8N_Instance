#!/bin/bash

# Mengambil data variable dengan raw
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")
FUNC_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/universal_lib_func.sh"
source <(curl -s "$FUNC_FILE")

# -------------------------------
# Fungsi Kirim Telegram
# -------------------------------
kirim_telegram() {
    curl -s -X POST "https://api.telegram.org/$TOKEN_TELEGRAM/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        --data-urlencode "text=$1" > /dev/null
}

# -------------------------------
# Fungsi Hapus Instalasi
# -------------------------------
hapus_instalasi() {
    log -e "${YELLOW}>> Menghapus service dan file terkait...${RESET}"
    $SUDO systemctl stop $SERVICE_NAME
    $SUDO systemctl disable $SERVICE_NAME
    $SUDO rm -f "$SERVICE_FILE"
    rm -f "$SCRIPT_PATH" "$IP_FILE"

    $SUDO systemctl daemon-reload
    $SUDO systemctl daemon-reexec

    log -e "${GREEN}✓ Otomatisasi berhasil dihapus.${RESET}"
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
DOMAIN="exlionn8n.duckdns.org"
DUCKDNS_TOKEN="60e9ee0f-dc88-4206-8e1b-28989c117b96"
TOKEN_TELEGRAM="bot7643811939:AAF60CGNfupKFoyDwN7rT2_Jai3qglUftIw"
TELEGRAM_CHAT_ID="832658254"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/$TOKEN_TELEGRAM/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        --data-urlencode "text=$1"
}

while true; do
    CURRENT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

    if [ ! -f "$IP_FILE" ]; then
        log "$CURRENT_IP" > "$IP_FILE"
        send_telegram "👀 *[IP Watcher]* Pertama kali mendeteksi IP: \`$CURRENT_IP\`"
    else
        LAST_IP=$(cat "$IP_FILE")
        if [ "$CURRENT_IP" != "$LAST_IP" ]; then
            log "$CURRENT_IP" > "$IP_FILE"
            curl -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$DUCKDNS_TOKEN&ip=$CURRENT_IP" > /dev/null

            TEXT="⚠️ *Perubahan IP Terdeteksi!*

*🆕 IP Baru:* \`$CURRENT_IP\`
*📦 IP Lama:* \`$LAST_IP\`

🔄 DuckDNS telah diperbarui dan pengecekan SSL sedang dilakukan. Tetap siaga!"
            send_telegram "$TEXT"

            $SUDO certbot renew --quiet
        fi
    fi
    sleep 5
done
EOF

chmod +x "$SCRIPT_PATH"

# -------------------------------
# Buat File systemd service
# -------------------------------
$SUDO tee "$SERVICE_FILE" > /dev/null <<EOF
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
log -e "${CYAN}>> Menyiapkan service systemd...${RESET}"
$SUDO systemctl daemon-reexec
$SUDO systemctl daemon-reload
$SUDO systemctl enable $SERVICE_NAME
$SUDO systemctl restart $SERVICE_NAME

# -------------------------------
# Kirim Notifikasi Awal
# -------------------------------
kirim_telegram "✅ *Setup Berhasil!* IP Watchdog sekarang aktif di servermu. Aku akan kabari kamu kalau ada perubahan IP!"

# -------------------------------
# Bagian Akhir: Output ke Terminal
# -------------------------------
log -e "${GREEN}✓ Setup selesai!${RESET}"
log -e "${CYAN}- Script   :${RESET} $SCRIPT_PATH"
log -e "${CYAN}- Service  :${RESET} $SERVICE_NAME"
log -e "${CYAN}- Log IP   :${RESET} $IP_FILE"
