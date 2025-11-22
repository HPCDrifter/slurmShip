#!/usr/bin/env bash
set -euo pipefail

# === Wait for system clock to sync ===
_wait_for_time_sync() {
    echo "[DB] Checking system time synchronization..."
    local max_attempts=60
    local current_year
    local current_timestamp
    local expected_min_timestamp=1731456000  # Nov 13, 2025 00:00:00 UTC

    for i in $(seq 1 $max_attempts); do
        current_year=$(date +%Y)
        current_timestamp=$(date +%s)

        # Check if time is reasonable (timestamp after Nov 2025)
        if [[ $current_timestamp -gt $expected_min_timestamp ]]; then
            echo "[DB] Time sync OK - Timestamp: $current_timestamp, Date: $(date)"
            # Extra safety: wait 2 more seconds for clock to stabilize
            sleep 2
            echo "[DB] Final timestamp after stabilization: $(date +%s) ($(date))"
            return 0
        fi

        if [[ $((i % 5)) -eq 0 ]]; then
            echo "[DB] Time sync check $i/$max_attempts - Timestamp: $current_timestamp, Date: $(date)"
        fi
        sleep 1
    done

    echo "[DB] ERROR: Time sync failed after $max_attempts attempts!"
    echo "[DB] Current time: $(date) (timestamp: $(date +%s))"
    echo "[DB] This will cause munge authentication to fail!"
    exit 1
}

# === Environment Variables (Required) ===
DBD_HOST="${DBD_HOST:-db}"
DBD_ADDR="${DBD_ADDR:-0.0.0.0}"
DBD_PORT="${DBD_PORT:-6819}"
STORAGE_HOST="${STORAGE_HOST:-%}"  # % = allow from any host
STORAGE_PORT="${STORAGE_PORT:-3306}"
STORAGE_USER="${STORAGE_USER:-slurm}"
STORAGE_PASS="${STORAGE_PASS:-slurmsecret}"
SLURM_ACCT_DB="slurm_acct_db"

# === 1. Start SSHD ===
_sshd_host() {
    echo "[DB] Starting SSHD..."
    mkdir -p /var/run/sshd
    if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -q
    fi
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N '' -q
    fi
    /usr/sbin/sshd -D -e &
}

# === 2. Initialize MariaDB ===
_mariadb_init() {
    echo "[DB] Initializing MariaDB data directory..."
    mkdir -p /var/lib/mysql /var/log/mariadb /var/run/mariadb
    chown mysql:mysql /var/lib/mysql /var/log/mariadb /var/run/mariadb

    if [[ ! -d /var/lib/mysql/mysql ]]; then
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql
    fi
}

# === 3. Start MariaDB ===
_mariadb_start() {
    echo "[DB] Starting MariaDB..."
    exec mariadbd --user=mysql --skip-networking=0 --bind-address=0.0.0.0 &

    # Wait for MariaDB to be ready
    echo -n "[DB] Waiting for MariaDB to start"
    for i in {30..0}; do
        if mysqladmin ping --silent 2>/dev/null; then
            echo " [OK]"
            break
        fi
        echo -n "."
        sleep 1
    done
    if [ "$i" = 0 ]; then
        echo >&2 "[DB] MariaDB init failed"
        exit 1
    fi

    # Initialize Slurm accounting DB
    _init_slurm_acct_db
}

# === 4. Initialize Slurm Accounting DB ===
_init_slurm_acct_db() {
    echo "[DB] Setting up Slurm accounting database..."

    # Create database and user - slurmdbd will create the schema automatically
    if mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS $SLURM_ACCT_DB;
CREATE USER IF NOT EXISTS '$STORAGE_USER'@'$STORAGE_HOST' IDENTIFIED BY '$STORAGE_PASS';
GRANT ALL PRIVILEGES ON $SLURM_ACCT_DB.* TO '$STORAGE_USER'@'$STORAGE_HOST';
FLUSH PRIVILEGES;
EOF
    then
        echo "[DB] Database and user created successfully."
        echo "[DB] Note: slurmdbd will auto-create the schema on first run."
    else
        echo "[DB] ERROR: Failed to create database or user!"
        exit 1
    fi
}

# === 5. Start Munge (using shared key) ===
_munge_start_using_key() {
    echo "[DB] Waiting for munge.key from controller..."
    while [[ ! -f /.secret/munge.key ]]; do
        echo -n "."
        sleep 1
    done
    echo " [OK]"

    # Verify clock is reasonable before starting munge
    local current_time=$(date +%s)
    local expected_min_timestamp=1731456000  # Nov 13, 2025 00:00:00 UTC

    echo "[DB] Pre-munge timestamp check: $current_time ($(date))"

    if [[ $current_time -lt $expected_min_timestamp ]]; then
        echo "[DB] ERROR: System clock is still at epoch time!"
        echo "[DB] Munge will fail with this clock. Timestamp: $current_time"
        echo "[DB] Expected minimum: $expected_min_timestamp (Nov 13, 2025)"
        exit 1
    fi

    # Create directories FIRST
    mkdir -p /etc/munge /var/lib/munge /var/log/munge /var/run/munge
    chown munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge
    chmod 700 /etc/munge /var/log/munge
    chmod 711 /var/lib/munge
    chmod 755 /var/run/munge

    # Copy key with correct permissions
    cp /.secret/munge.key /etc/munge/munge.key
    chown munge:munge /etc/munge/munge.key
    chmod 600 /etc/munge/munge.key

    echo "[DB] Starting munged at timestamp: $(date +%s) ($(date))"
    sudo -u munge /usr/sbin/munged --force &
    local munge_pid=$!

    # Wait longer for munge to fully initialize
    sleep 5

    # Verify munge is working
    echo "[DB] Testing munge authentication..."
    for i in {1..10}; do
        if munge -n 2>&1 | unmunge 2>&1 | grep -q "STATUS:"; then
            echo "[DB] Munge authentication successful at $(date) (timestamp: $(date +%s))"
            remunge
            return 0
        fi
        echo "[DB] Munge test attempt $i/10 failed (time: $(date +%s)), retrying..."
        sleep 2
    done

    echo "[DB] FATAL: Munge authentication failed after 10 attempts!"
    echo "[DB] Final timestamp: $(date +%s) ($(date))"
    echo "[DB] This usually means the system clock is not synchronized properly."
    exit 1
}

# === 6. Wait for Worker SSH Key ===
_wait_for_worker() {
    echo -n "[DB] Waiting for worker SSH key"
    while [[ ! -f /home/worker/.ssh/id_rsa.pub ]]; do
        echo -n "."
        sleep 1
    done
    echo " [OK]"
}

# === 7. Generate slurmdbd.conf ===
_generate_slurmdbd_conf() {
    echo "[DB] Generating slurmdbd.conf..."
    cat > /etc/slurm/slurmdbd.conf <<EOF
# slurmdbd.conf - Slurm 25.11.0
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2

DbdHost=$DBD_HOST
DbdAddr=$DBD_ADDR
DbdPort=$DBD_PORT

StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=$STORAGE_PORT
StorageUser=$STORAGE_USER
StoragePass=$STORAGE_PASS
StorageLoc=$SLURM_ACCT_DB

SlurmUser=slurm
PidFile=/var/run/slurmdbd.pid
LogFile=/var/log/slurmdbd.log
DebugLevel=info

# Optional: Archive old jobs
# ArchiveJobs=yes
# ArchiveDir=/var/lib/slurm/archive
EOF
}

# === 8. Start slurmdbd ===
_slurmdbd() {
    echo "[DB] Starting slurmdbd..."

    mkdir -p /var/spool/slurm/d /var/log/slurm
    chown slurm:slurm /var/spool/slurm/d /var/log/slurm

    if [[ -f /home/config/slurmdbd.conf ]]; then
        echo "[DB] Using provided slurmdbd.conf"
        cp /home/config/slurmdbd.conf /etc/slurm/slurmdbd.conf
    else
        _generate_slurmdbd_conf
    fi

    # Set correct permissions and ownership (REQUIRED: must be 600 or 640)
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf

    # Copy to shared volume with correct permissions
    cp /etc/slurm/slurmdbd.conf /.secret/slurmdbd.conf
    chmod 600 /.secret/slurmdbd.conf

    # Start in foreground
    exec /usr/sbin/slurmdbd -D
}

# === Main ===
echo "=== Slurm Database Node (Slurm 25.11.0) ==="
echo "[DB] Container startup at: $(date +%s) ($(date))"

# Give Docker Desktop time to sync clocks on container start
echo "[DB] Waiting 3 seconds for Docker clock sync..."
sleep 3

_wait_for_time_sync
_sshd_host
_mariadb_init
_mariadb_start
_munge_start_using_key
_wait_for_worker
_slurmdbd

# Fallback (should not reach)
exec tail -f /dev/null