#!/bin/bash

# ------------------------------
# Bagian Atas - Konfigurasi
# ------------------------------
LOCAL_DB_NAME="n8ndb"
LOCAL_DB_USER="n8nuser"
LOCAL_DB_PASSWORD="@4Exparalion"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

BACKUP_FILE="n8n_backup.dump"

# Ganti dengan koneksi Neon kamu
NEON_URL="postgresql://neondb_owner:npg_xToG21DEemRi@ep-divine-lake-a6rmww01-pooler.us-west-2.aws.neon.tech/neondb?sslmode=require"

# ------------------------------
# Bagian Tengah - Fungsi
# ------------------------------

backup_local_postgres() {
    echo ">> Membuat backup dari PostgreSQL lokal..."
    PGPASSWORD="$LOCAL_DB_PASSWORD" pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -Fc "$LOCAL_DB_NAME" \
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
