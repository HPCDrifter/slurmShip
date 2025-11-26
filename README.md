# slurmShip


slurmShip is a Docker-compose based demonstration of a small Slurm cluster (Slurm 25.11.0). It provides container images and orchestration for a minimal cluster consisting of:

- `database` (slurmdbd backend)
- `controller` (slurmctld)
- `worker01`, `worker02` (slurmd nodes)
- `login` (user login node for job submission)

The repository includes local RPMs for an offline, reproducible build and a set of entrypoint scripts to wire up munge, SSH keys, and Slurm configuration between containers.

This README explains how to build, run, and verify the cluster, plus some troubleshooting tips.

# Architecture Diagram 


```
User
  |
  | SSH :22
  v
+--------+                    Volumes: munge_keys, slurm_state, db_data
| Login  |<------------------------------------+
|  Node  |                                     |
+--------+                                     |
  |                                            |
  | Slurm commands (srun, sbatch, sinfo)       |
  | to slurmctld :6817                         |
  v                                            |
+----------------+                             |
|  Controller    |                             |
| (slurmctld)    |<--------+                   |
|     :6817      |         |                   |
+----------------+         |                   |
   |         |             |                   |
   | Job dispatch to       |                   |
   | slurmd :6818          |                   |
   v         v             |                   |
+--------+ +--------+      |                   |
|Worker01| |Worker02|      |                   |
|(slurmd)|(slurmd)         |                   |
| :6818  | :6818  |       |                   |
+--------+ +--------+      |                   |
                           |                   |
      +--------------------+-------------------+
      |
      | Accounting (slurmdbd :6819)
      |
  +-----------------+
  |   Database      |
  | (slurmdbd)      |
  |  :6819          |
  |  MariaDB :3306  |
  +-----------------+
```

## INFO
- System Architecture: x86_64
- Operating System: Rocky (Container)
- Tested on GitHub Codespace 

## Prerequisites

- Docker (or Docker Desktop) with Buildx support
- docker-compose (or `docker compose` plugin)
- Sufficient disk space to hold images and volumes
- On systems with SELinux you may need to adjust volume mount options

## Build the images

The `login` image uses the local RPMs in `packages/rocky/rpms` so you should build images from the repository root.

From the repository root:

```bash
# Build controller, database, workers and login
make 
```

Or build a single service (example: `login`):

```bash
make -C login build
```

## Start the cluster

Bring up the cluster:

```bash
docker compose up 
or
docker compose up -d 
```

The compose file defines named volumes for `munge_keys`, `slurm_state`, and `db_data` that persist state between runs.

## Verify containers are running and healthy

List containers and health status:

```bash
docker compose ps
or 
docker ps
```

Check logs for errors (examples):

```bash
docker compose logs controller
docker compose logs worker01
docker compose logs worker02
```

## Use the login node to inspect Slurm

The `login` container is intended as the user-facing node. Use it to run `sinfo`, `scontrol`, `squeue`, `sbatch`, and `srun`.

Run these from the host to execute inside the `login` container:

```bash
# Check if nodes are visible
docker exec -it login sinfo

# See detailed node information
docker exec -it login scontrol show nodes

# Access an interactive shell as the worker user
docker exec -it login bash

# Or su to the worker user then submit a job
```

Notes:
- `sinfo` and other Slurm commands will only show nodes once `slurmctld` and `slurmd` are communicating and munge authentication is working.

- The `login` image copies `munge.key` and `slurm.conf` from the shared `/.secret` volume so its configuration matches the controller.

## Submitting a job (example)

From inside the `login` container (or via `docker exec`):

```bash
su - worker
cat > ~/hello.slurm <<'EOF'
#!/bin/bash
#SBATCH --job-name=hello
#SBATCH --output=hello.out
echo "Hello from $(hostname)"
sleep 5
EOF

sbatch ~/hello.slurm
squeue -u $USER
```

## Troubleshooting

- If `sinfo` shows nodes as `UNKNOWN` or they don't appear:
	- Check `docker compose logs controller` and `docker compose logs worker01`/`worker02` for error messages.
	- Verify `munged` is running in each relevant container and that `/etc/munge/munge.key` matches across containers.
- If munge authentication fails:
	- Ensure `munge.key` is present in `/.secret` (controller copies it there). The `login` and worker containers read it from that volume.
	- Run `munge -n | unmunge` inside a container to test.
- If Slurm client tools are missing in `login`:
	- The `login` image installs the local `slurm-25.11.0` RPMs during build from `packages/rocky/rpms`.
	- Rebuild the `login` image if RPMs have changed: `make -C login build`.

## Notes and recommendations

- The current setup mounts `./home` into `/home/worker` and uses `./secret` as the shared secret volume. The `controller` creates `/.secret/worker-secret.tar.gz`, `munge.key`, and `slurm.conf`/`cgroup.conf` there for other services to pick up.
- For a production-like setup you may prefer to:
	- Run `sshd` on the `login` container and expose SSH port(s) so users can connect using standard SSH clients.
	- Use `gosu`/`tini` for better signal handling in entrypoints.
	- Harden SSH and munge key handling (avoid disabling StrictHostKeyChecking in production).

## Cleaning up

Stop and remove containers and volumes:

```bash
docker compose down --volumes --remove-orphans
or 
make clean
```

## Want help customizing?

If you'd like I can:

- Add an SSH server to the `login` image and expose port 22
- Make the login container install RPMs at runtime if they're not present
- Add CI steps or a Makefile target to build all images in sequence

Open an issue or ask here with what you want next.

