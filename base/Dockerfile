FROM rockylinux:9
LABEL maintainer="HPCDrifter"

# === Build args (override at build time if needed) ===
ARG SLURM_VERSION=25.11.0
ARG MUNGE_UID=981
ARG SLURM_UID=982
ARG WORKER_UID=1000
ARG TINI_VERSION=0.19.0
ARG TINIPLT=amd64
ARG TZ=UTC

# === Environment variables (available at runtime) ===
ENV SLURM_VERSION=${SLURM_VERSION} \
    MUNGE_UID=${MUNGE_UID} \
    SLURM_UID=${SLURM_UID} \
    WORKER_UID=${WORKER_UID} \
    TZ=${TZ}

# === Timezone & base update ===
RUN set -eux \
    && dnf update -y \
     && dnf install -y tzdata \
     && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
     && echo $TZ > /etc/timezone \
     && dnf reinstall -y ca-certificates \
     && dnf clean all

# === Install Tini (init system) ===
ADD https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-${TINIPLT} /usr/local/bin/tini
RUN chmod +x /usr/local/bin/tini
ENTRYPOINT ["/usr/local/bin/tini", "--"]

# === Create users ===
RUN set -eux \
    && groupadd -g $MUNGE_UID munge \
    && useradd -m -c "MUNGE Uid 'N' Gid Emporium" -d /var/lib/munge -u $MUNGE_UID -g munge -s /sbin/nologin munge \
    && groupadd -g $SLURM_UID slurm \
    && useradd -m -c "Slurm workload manager" -d /var/lib/slurm -u $SLURM_UID -g slurm -s /bin/bash slurm \
    && groupadd -g $WORKER_UID worker \
    && useradd -m -c "Workflow user" -d /home/worker -u $WORKER_UID -g worker -s /bin/bash worker

# === Install base packages ===
RUN set -eux \
    && dnf -y install epel-release \
    && dnf -y config-manager --set-enabled crb \
    && dnf -y install \
        sudo wget which tree \
        mariadb-server mariadb-devel \
        munge munge-libs munge-devel \
        openssh-server openssh-clients \
        procps-ng bc tcl tcl-devel bash \
        http-parser http-parser-devel postfix ssmtp dbus-devel \
    && dnf clean all

# === Copy RPMs (from your local ./rpms/) ===
COPY rpms /packages

# === Install Slurm RPMs (skip torque/openmpi) ===
WORKDIR /packages
RUN set -eux \
    && dnf -y localinstall $(ls | grep -v -e 'torque' -e 'openmpi') || true

# === Reset workdir & expose ports ===
WORKDIR /
VOLUME ["/home", "/.secret"]
EXPOSE 22 3306 6817 6818 6819

CMD ["/bin/bash"]