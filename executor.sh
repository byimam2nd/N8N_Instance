#!/bin/bash

# ------------------
# Konfigurasi
# ------------------
# Code untuk mengambil variable
CONFIG_FILE="$GITHUB_URL/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")

# -----------------------------
# Cek dan Install jq otomatis
# -----------------------------
if ! command -v jq &>/dev/null; then
  echo -e "${YELLOW}[!] 'jq' tidak ditemukan. Menginstal secara otomatis...${RESET}"
  sleep 1
  if command -v apt &>/dev/null; then
    $SUDO apt update && sudo apt install -y jq
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] 'jq' berhasil diinstal.${RESET}"
    else
      echo -e "${RED}[✘] Gagal menginstal 'jq'. Silakan instal manual.${RESET}"
      exit 1
    fi
  else
    echo -e "${RED}[✘] Sistem Anda tidak mendukung 'apt'. Instal 'jq' secara manual.${RESET}"
    exit 1
  fi
fi

# ------------------
# Bagian tengah: Ambil daftar file .sh dari GitHub
# ------------------
FILE_NAMES=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL" | jq -r '.[] | select(.type == "file") | select(.name | endswith(".sh")) | .name')

declare -A RAW_FILES
for fname in $FILE_NAMES; do
  RAW_FILES["$fname"]="$GITHUB_URL/$fname"
done

# ------------------
# Bagian akhir: Menu interaktif
# ------------------
while true; do
  echo -e "\n${BOLD}${CYAN}========= MENU EXECUTOR =========${RESET}"
  i=1
  OPTIONS=()
  for name in "${!RAW_FILES[@]}"; do
    echo -e "${YELLOW}$i)${RESET} ${GREEN}$name${RESET}"
    OPTIONS[$i]="$name"
    ((i++))
  done
  echo -e "${YELLOW}0)${RESET} ${RED}Keluar${RESET}"
  echo -e "${CYAN}=================================${RESET}"

  read -p "$(echo -e "${BOLD}Pilih opsi [0-${#OPTIONS[@]}]: ${RESET}")" choice

  if [[ "$choice" == "0" ]]; then
    echo -e "${RED}[!] Keluar dari program.${RESET}"
    exit 0
  elif [[ -n "${OPTIONS[$choice]}" ]]; then
    file_name="${OPTIONS[$choice]}"
    script_url="${RAW_FILES[$file_name]}"

    echo -e "${BLUE}[▶] Menjalankan:${RESET} ${BOLD}$file_name${RESET}"
    echo -e "${CYAN}URL:${RESET} $script_url"
    echo ""
    bash <(curl -s "$script_url")
  else
    echo -e "${RED}[!] Pilihan tidak valid.${RESET}"
  fi
done