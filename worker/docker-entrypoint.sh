#!/usr/bin/env bash
set -euo pipefail

# === Environment (Optional Overrides) ===
SLURM_NODE_NAME="${SLURM_NODE_NAME:-$(hostname)}"
SLURM_NODEID="${SLURM_NODEID:-0}"
SLURM_NNODES="${SLURM_NNODES:-1}"

# === 1. Start SSHD ===
_sshd_host() {
    echo "[WORKER] Starting SSHD on $SLURM_NODE_NAME..."
    mkdir -p /var/run/sshd

    # Generate host keys if missing
    [[ ! -f /etc/ssh/ssh_host_ed25519_key ]] && \
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -q
    [[ ! -f /etc/ssh/ssh_host_rsa_key ]] && \
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N '' -q

    # Start in background
    /usr/sbin/sshd -D -e &
}

# === 2. Start Munge (using shared key) ===
_munge_start_using_key() {
    echo -n "[WORKER] Waiting for munge.key"
    while [[ ! -f /.secret/munge.key ]]; do
        echo -n "."
        sleep 1
    done
    echo " [OK]"

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

    echo "[WORKER] Starting munged..."
    sudo -u munge /usr/sbin/munged --force &

    # Wait for munge to be ready
    sleep 3

    # Verify munge is working
    if ! munge -n | unmunge >/dev/null 2>&1; then
        echo "[WORKER] Munge test failed!"
        exit 1
    fi
    remunge
}

# === 3. Wait for Worker SSH Setup ===
_wait_for_worker() {
    echo -n "[WORKER] Waiting for worker SSH keys"
    while [[ ! -f /home/worker/.ssh/id_rsa.pub ]]; do
        echo -n "."
        sleep 1
    done
    echo " [OK]"

    # Apply SSH config if missing
    if [[ ! -f /home/worker/.ssh/config ]]; then
        sudo -u worker mkdir -p /home/worker/.ssh
        cat > /home/worker/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
        chown worker:worker /home/worker/.ssh/config
        chmod 600 /home/worker/.ssh/config
    fi
}

# === 4. Wait for slurm.conf & Start slurmd ===
_slurmd() {
    echo -n "[WORKER] Waiting for slurm.conf"
    while [[ ! -f /.secret/slurm.conf ]]; do
        echo -n "."
        sleep 1
    done
    echo " [OK]"

    # Ensure /etc/slurm directory exists
    mkdir -p /etc/slurm

    # Copy slurm.conf
    cp /.secret/slurm.conf /etc/slurm/slurm.conf
    cp /.secret/cgroup.conf /etc/slurm/cgroup.conf

    # Hide cgroup filesystem from SLURM
    mkdir -p /tmp/fake-cgroup
    mount --bind /tmp/fake-cgroup /sys/fs/cgroup 2>/dev/null || true

    mkdir -p /var/spool/slurm/d /var/log/slurm
    chown -R slurm:slurm /var/spool/slurm/d /var/log/slurm

    # Log node info
    echo "[WORKER] Node: $SLURM_NODE_NAME"
    slurmd -C

    # Verify configuration
    echo "[WORKER] Verifying configuration:"
    grep -E "(TaskPlugin|ProctrackType|JobAcctGatherType)" /etc/slurm/slurm.conf

    echo "[WORKER] Container environment detected - using configuration from controller"

    # Set multiple environment variables to disable cgroup detection
    export SLURM_CONF=/etc/slurm/slurm.conf
    export SLURM_CGROUP_DISABLE=1
    export SLURM_DISABLE_CGROUPS=1
    export SLURM_NO_CGROUPS=1
    unset CGROUP_ROOT
    unset CGROUP_MOUNT_POINT

    # Start slurmd with verbose logging to see what's happening
    echo "[WORKER] Starting slurmd with container-safe configuration..."
    exec /usr/sbin/slurmd -D -f /etc/slurm/slurm.conf -vvv
}


# === Main ===
echo "=== Slurm Worker Node ($SLURM_NODE_NAME) ==="

_sshd_host
_munge_start_using_key
_wait_for_worker
_slurmd

# Fallback (should not reach)
exec tail -f /dev/null