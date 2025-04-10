  #!/bin/bash

# ------------------
# Bagian atas kode: Konfigurasi
# ------------------
# URL konfigurasi
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"

# Load konfigurasi utama
echo "[INFO] Memuat konfigurasi"

source <(curl -s "$CONFIG_FILE") || { echo "[ERROR] Gagal memuat konfigurasi."; exit 1; }

TOKEN_FILE_URL="$GITHUB_TOKEN_URL"

echo $GITHUB_URL
echo $GITHUB_TOKEN_URL

# Cek apakah variabel penting terdefinisi
if [[ -z "$CONFIG_FILE" || -z "$TOKEN_FILE_URL" ]]; then
  echo -e "[ERROR] GITHUB_URL atau GITHUB_TOKEN_URL belum terdefinisi!"
  exit 1
fi

# Ambil GitHub Token
echo "[INFO] Mengambil GitHub Token dari: $TOKEN_FILE_URL"

# Ambil GitHub Token yang tersimpan dalam format GITHUB_TOKEN="...."
GITHUB_TOKEN=$(curl -s "$TOKEN_FILE_URL" | grep GITHUB_TOKEN | cut -d '=' -f2 | tr -d '"')

echo $GITHUB_TOKEN

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "[ERROR] Token GitHub kosong atau tidak valid!"
  exit 1
fi

# Validasi token GitHub
VALID_USER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login')
if [[ "$VALID_USER" == "null" || -z "$VALID_USER" ]]; then
  echo "[ERROR] Token GitHub tidak valid atau gagal otentikasi."
  exit 1
else
  echo "[INFO] Otentikasi GitHub berhasil sebagai: $VALID_USER"
fi

# -----------------------------
# Cek dan Install jq otomatis
# -----------------------------
if ! command -v jq &>/dev/null; then
  echo "[WARN] 'jq' tidak ditemukan. Menginstal secara otomatis..."
  sleep 1
  if command -v apt &>/dev/null; then
    $SUDO apt update && $SUDO apt install -y jq
    if [ $? -eq 0 ]; then
      echo "[INFO] 'jq' berhasil diinstal."
    else
      echo "[ERROR] Gagal menginstal 'jq'."
      exit 1
    fi
  else
    echo "[ERROR] Sistem tidak mendukung APT. Instal 'jq' secara manual."
    exit 1
  fi
fi

# ------------------
# Bagian tengah: Ambil daftar file .sh dari GitHub
# ------------------
echo "[INFO] Mengambil daftar file .sh dari repository..."
RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL")
if [[ -z "$RESPONSE" ]]; then
  echo "[ERROR] Gagal mengambil data dari API GitHub."
  exit 1
fi

FILE_NAMES=$(echo "$RESPONSE" | jq -r '.[] | select(.type == "file") | select(.name | endswith(".sh")) | .name')
if [[ -z "$FILE_NAMES" ]]; then
  echo "[INFO] Tidak ditemukan file .sh di repositori."
  exit 0
fi

declare -A RAW_FILES
for fname in $FILE_NAMES; do
  RAW_FILES["$fname"]="$GITHUB_URL/$fname"
done

# ------------------
# Bagian akhir: Menu interaktif
# ------------------
while true; do
  echo -e "\n========= MENU EXECUTOR ========="
  i=1
  OPTIONS=()
  for name in "${!RAW_FILES[@]}"; do
    echo -e "$i) $name"
    OPTIONS[$i]="$name"
    ((i++))
  done
  echo -e "0) Keluar"
  echo -e "================================="

  read -p "Pilih opsi [0-$((i-1))]: " choice

  if [[ "$choice" == "0" ]]; then
    echo "[INFO] Keluar dari program."
    exit 0
  elif [[ -n "${OPTIONS[$choice]}" ]]; then
    file_name="${OPTIONS[$choice]}"
    script_url="${GITHUB_URL}/${file_name/#\//}"

    echo "[INFO] Menjalankan: $file_name"
    echo "[INFO] URL: $script_url"
    echo ""
    bash <(curl -s "$script_url") || echo "[ERROR] Gagal menjalankan $file_name"
  else
    echo "[WARN] Pilihan tidak valid. Coba lagi."
  fi
done
