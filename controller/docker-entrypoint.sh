#!/usr/bin/env bash
set -euo pipefail

# === Wait for system clock to sync ===
_wait_for_time_sync() {
    echo "[CTRL] Checking system time synchronization..."
    local max_attempts=60
    local current_timestamp
    local EXPECTED_MIN_DATE="${EXPECTED_MIN_DATE:-2025-11-13 00:00:00 UTC}"
    local expected_min_timestamp
    expected_min_timestamp=$(date -d "$EXPECTED_MIN_DATE" +%s)

    for i in $(seq 1 $max_attempts); do
        current_timestamp=$(date +%s)

        if [[ $current_timestamp -gt $expected_min_timestamp ]]; then
            echo "[CTRL] Time sync OK - Timestamp: $current_timestamp, Date: $(date)"
            return 0
        fi

        if [[ $((i % 10)) -eq 0 ]]; then
            echo "[CTRL] Time sync check $i/$max_attempts - Timestamp: $current_timestamp"
        fi
        sleep 1
    done

    echo "[CTRL] WARNING: Time sync uncertain after $max_attempts attempts"
    echo "[CTRL] Current time: $(date) (timestamp: $(date +%s))"
    echo "[CTRL] Continuing anyway..."
}

# === Configuration Variables (set via env or defaults) ===
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
CONTROL_MACHINE="${CONTROL_MACHINE:-controller}"
SLURMCTLD_PORT="${SLURMCTLD_PORT:-6817}"
SLURMD_PORT="${SLURMD_PORT:-6818}"
PARTITION_NAME="${PARTITION_NAME:-compute}"
ACCOUNTING_STORAGE_HOST="${ACCOUNTING_STORAGE_HOST:-db}"
ACCOUNTING_STORAGE_PORT="${ACCOUNTING_STORAGE_PORT:-6819}"
USE_SLURMDBD="${USE_SLURMDBD:-false}"

# === 1. Start SSHD ===
_sshd_host() {
    echo "Starting SSHD..."
    mkdir -p /var/run/sshd
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N '' -q
    fi
    if [[ ! -f /etc/ssh/ssh_host_ecdsa_key ]]; then
        ssh-keygen -t ecdsa -b 521 -f /etc/ssh/ssh_host_ecdsa_key -N '' -q
    fi
    if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -q
    fi
    /usr/sbin/sshd -D -e &
}

# === 2. Setup Worker SSH (Passwordless) ===
_ssh_worker() {
    echo "Setting up worker SSH..."
    mkdir -p /home/worker
    chown worker:worker /home/worker

    local setup_script="/home/worker/setup-worker-ssh.sh"
    cat > "$setup_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [[ ! -f ~/.ssh/id_rsa ]]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -q -N "" -C "$(whoami)@$(hostname)-$(date -Iseconds)"
fi
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

cat > ~/.ssh/config <<EOF2
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    IdentityFile ~/.ssh/id_rsa
EOF2
chmod 600 ~/.ssh/config

# Package for distribution
cd ~/
tar -czf ~/worker-secret.tar.gz .ssh
cd -
EOF

    chmod +x "$setup_script"
    chown worker:worker "$setup_script"
    sudo -u worker "$setup_script"
}

# === 3. Start Munge with Modern Key Generation ===
_munge_start() {
    echo "[CTRL] Starting Munge..."
    local current_time
    current_time=$(date +%s)
    echo "[CTRL] Munge startup timestamp: $current_time ($(date))"

    mkdir -p /etc/munge /var/lib/munge /var/log/munge /var/run/munge
    chown munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge
    chmod 700 /etc/munge /var/log/munge
    chmod 711 /var/lib/munge
    chmod 755 /var/run/munge

    # Modern key generation (create-munge-key deprecated)
    if [[ ! -f /etc/munge/munge.key ]]; then
        echo "[CTRL] Generating new munge key..."
        dd if=/dev/urandom bs=1024 count=1 > /etc/munge/munge.key 2>/dev/null
        chown munge:munge /etc/munge/munge.key
        chmod 600 /etc/munge/munge.key
    fi

    echo "[CTRL] Starting munged..."
    sudo -u munge /usr/sbin/munged --force &
    sleep 3

    # Test munge
    echo "[CTRL] Testing munge authentication..."
    if ! munge -n | unmunge >/dev/null 2>&1; then
        echo "[CTRL] Munge authentication failed!"
        exit 1
    fi
    echo "[CTRL] Munge authentication successful at $(date +%s) ($(date))"
    remunge
}

# === 4. Copy Secrets to Shared Volume ===
_copy_secrets() {
    echo "Copying secrets to /.secret..."
    mkdir -p /.secret
    cp /home/worker/worker-secret.tar.gz /.secret/
    cp /home/worker/setup-worker-ssh.sh /.secret/
    cp /etc/munge/munge.key /.secret/
}

# === 5. Generate slurm.conf (Slurm 25.11.0 compatible) ===
_generate_slurm_conf() {
    echo "Generating slurm.conf..."
    cat > /etc/slurm/slurm.conf <<EOF
# slurm.conf - Generated for Slurm 25.11.0
ClusterName=$CLUSTER_NAME
SlurmctldHost=$CONTROL_MACHINE
SlurmctldAddr=$CONTROL_MACHINE
SlurmUser=slurm
SlurmdUser=root

# Ports
SlurmctldPort=$SLURMCTLD_PORT
SlurmdPort=$SLURMD_PORT

# Authentication
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2

# Storage
StateSaveLocation=/var/spool/slurm/ctld
SlurmdSpoolDir=/var/spool/slurm/d
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid

# Scheduling
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU_Memory
PrivateData=jobs,accounts,users,usage

# Node Definition
NodeName=worker[01-02] CPUs=2 Sockets=1 CoresPerSocket=1 ThreadsPerCore=2 RealMemory=7944 State=UNKNOWN
PartitionName=$PARTITION_NAME Nodes=ALL Default=YES MaxTime=INFINITE State=UP

# Logging
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurmd.log

# Accounting (if enabled)
$(if $USE_SLURMDBD; then
    echo "AccountingStorageType=accounting_storage/slurmdbd"
    echo "AccountingStorageHost=$ACCOUNTING_STORAGE_HOST"
    echo "AccountingStoragePort=$ACCOUNTING_STORAGE_PORT"
else
    echo "AccountingStorageType=accounting_storage/none"
fi)

# Task and Process Tracking (disable cgroups for containers)
ProctrackType=proctrack/pgid
TaskPlugin=task/none
JobAcctGatherType=jobacct_gather/none

# Modern container handling (replaces JobContainerType)
NamespaceType=namespace/none

# Misc
ReturnToService=2
SlurmctldTimeout=120
SlurmdTimeout=120
InactiveLimit=0
MinJobAge=300
KillWait=30
SlurmctldParameters=idle_on_node_suspend,power_save_interval=300,disable_cgroup
EOF

    # Generate cgroup.conf to explicitly disable cgroups
    echo "Generating cgroup.conf (disabled)..."
    cat > /etc/slurm/cgroup.conf <<EOF
###
# Slurm cgroup support configuration file
# This file disables all cgroup functionality
###
CgroupPlugin=disabled
ConstrainCores=no
ConstrainRAMSpace=no
ConstrainDevices=no
ConstrainSwapSpace=no
EOF
}

# === 6. Start slurmctld ===
_slurmctld() {
    echo "Starting slurmctld..."

    # Wait for slurmdbd.conf if using database
    if $USE_SLURMDBD; then
        echo -n "Waiting for slurmdbd.conf"
        while [[ ! -f /.secret/slurmdbd.conf ]]; do
            echo -n "."
            sleep 1
        done
        echo " found!"
        cp /.secret/slurmdbd.conf /etc/slurm/slurmdbd.conf
        chown slurm:slurm /etc/slurm/slurmdbd.conf
        chmod 600 /etc/slurm/slurmdbd.conf
    fi

    # Create spool & log dirs
    mkdir -p /var/spool/slurm/ctld /var/spool/slurm/d /var/log/slurm
    chown -R slurm:slurm /var/spool/slurm /var/log/slurm

    # Use provided config or generate
    if [[ -f /home/config/slurm.conf ]]; then
        echo "Using provided slurm.conf"
        cp /home/config/slurm.conf /etc/slurm/slurm.conf
    else
        _generate_slurm_conf
    fi

    # Copy config to shared volume
    cp /etc/slurm/slurm.conf /.secret/
    cp /etc/slurm/cgroup.conf /.secret/

    # Add cluster (non-interactive) - non-fatal if it fails
    if $USE_SLURMDBD; then
        echo "Attempting to register cluster with slurmdbd..."
        if sacctmgr -i show cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
            echo "Cluster $CLUSTER_NAME already registered"
        elif sacctmgr -i add cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
            echo "Cluster $CLUSTER_NAME registered successfully"
        else
            echo "WARNING: Could not register cluster (will retry after slurmctld starts)"
        fi
    fi

    # Start slurmctld in foreground
    exec /usr/sbin/slurmctld -D
}

# === Main Execution ===
echo "Starting Slurm Controller (Slurm 25.11.0)"
echo "[CTRL] Container startup at: $(date +%s) ($(date))"

# Ensure time is synchronized before munge starts
_wait_for_time_sync

_sshd_host
_ssh_worker
_munge_start
_copy_secrets
_slurmctld

# Fallback (should never reach)
tail -f /dev/null