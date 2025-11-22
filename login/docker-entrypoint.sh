#!/usr/bin/env bash
set -euo pipefail

echo "[LOGIN] Starting login container at: $(date)"

# If a secret tarball exists (created by controller), extract it for the worker user
if [[ -f /.secret/worker-secret.tar.gz ]]; then
  echo "[LOGIN] Found worker-secret.tar.gz, extracting to /home/worker"
  mkdir -p /home/worker
  tar -xzf /.secret/worker-secret.tar.gz -C /home/worker || true
  chown -R worker:worker /home/worker
  if [[ -d /home/worker/.ssh ]]; then
    chmod 700 /home/worker/.ssh
    chmod 600 /home/worker/.ssh/authorized_keys || true
  fi
fi

# If a setup-worker-ssh.sh is present, copy it so user can inspect or re-run
if [[ -f /.secret/setup-worker-ssh.sh ]]; then
  cp /.secret/setup-worker-ssh.sh /home/worker/
  chown worker:worker /home/worker/setup-worker-ssh.sh
  chmod 700 /home/worker/setup-worker-ssh.sh
fi

# Ensure a permissive system-wide SSH client config so the login node can connect to compute nodes easily
mkdir -p /etc/ssh/ssh_config.d
cat > /etc/ssh/ssh_config.d/99-slurm.conf <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

echo "[LOGIN] SSH client configured"

# Restore munge key and start munged if provided by controller
if [[ -f /.secret/munge.key ]]; then
  echo "[LOGIN] Found munge.key in /.secret, installing..."
  mkdir -p /etc/munge /var/lib/munge /var/log/munge /var/run/munge
  cp /.secret/munge.key /etc/munge/munge.key
  chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge
  chmod 700 /etc/munge
  chmod 600 /etc/munge/munge.key || true

  echo "[LOGIN] Starting munged..."
  if command -v munged >/dev/null 2>&1; then
    sudo -u munge /usr/sbin/munged --force &
    sleep 2
    if munge -n | unmunge >/dev/null 2>&1; then
      echo "[LOGIN] Munge authentication OK"
    else
      echo "[LOGIN] WARNING: Munge test failed"
    fi
  else
    echo "[LOGIN] munged binary not found; munge service not started"
  fi
fi

# Copy slurm configuration from shared secrets so client and controller match
if [[ -f /.secret/slurm.conf ]]; then
  echo "[LOGIN] Copying slurm.conf from /.secret to /etc/slurm/slurm.conf"
  mkdir -p /etc/slurm
  cp /.secret/slurm.conf /etc/slurm/slurm.conf
  chown slurm:slurm /etc/slurm/slurm.conf || true
  chmod 644 /etc/slurm/slurm.conf || true
fi
if [[ -f /.secret/cgroup.conf ]]; then
  echo "[LOGIN] Copying cgroup.conf from /.secret to /etc/slurm/cgroup.conf"
  mkdir -p /etc/slurm
  cp /.secret/cgroup.conf /etc/slurm/cgroup.conf
  chown slurm:slurm /etc/slurm/cgroup.conf || true
  chmod 644 /etc/slurm/cgroup.conf || true
fi

# Give a small informative message about SLURM tools availability
if command -v srun >/dev/null 2>&1; then
  echo "[LOGIN] Slurm client tools: srun, sbatch, squeue available"
else
  echo "[LOGIN] Warning: Slurm client tools not found"
fi

# If no command passed, open an interactive shell as `worker`; otherwise exec given command as `worker`
if [[ "$#" -eq 0 ]]; then
  echo "[LOGIN] Dropping to interactive shell as 'worker' (/bin/bash)"
  exec su -s /bin/bash worker -c "/bin/bash"
else
  echo "[LOGIN] Executing command as 'worker': $*"
  exec su -s /bin/bash worker -c "$*"
fi
