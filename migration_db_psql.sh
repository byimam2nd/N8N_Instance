#!/bin/bash

# ------------------------------
# Bagian Atas - Konfigurasi
# ------------------------------

# Mengambil data variable dengan raw
CONFIG_FILE="https://raw.githubusercontent.com/byimam2nd/N8N_Instance/main/data_n8n.conf"
source <(curl -s "$CONFIG_FILE")

# ------------------------------
# Bagian Tengah - Fungsi
# ------------------------------

backup_local_postgres() {
    echo ">> Membuat backup dari PostgreSQL lokal..."
    PGPASSWORD="$DB_PASSWORD" pg_dump -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -Fc "$DB_NAME" \
        --no-owner --no-privileges --no-acl -f "$BACKUP_FILE"
}

restore_to_neon() {
    echo ">> Restore ke Neon DB..."
    pg_restore --verbose --clean --no-owner --no-privileges --no-acl \
        --dbname="$NEON_URL" "$BACKUP_FILE"
}

# ------------------------------
# Bagian Akhir - Eksekusi
# ------------------------------

echo "=== One Click Transfer Lokal PostgreSQL ke Neon ==="
backup_local_postgres

if [ $? -eq 0 ]; then
    restore_to_neon
    if [ $? -eq 0 ]; then
        echo ">>> Restore ke Neon berhasil!"
    else
        echo ">>> Restore gagal. Coba cek versi dan struktur backup-nya."
    fi
else
    echo ">>> Backup gagal. Cek koneksi atau kredensial lokal PostgreSQL."
fi
