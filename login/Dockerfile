# Login image for submitting SLURM jobs and interactive use
FROM hpcdrifter/slurm.base:25.11.0
LABEL maintainer="HPCDrifter"

# Example slurm-25.11.0-1.el9.x86_64.rpm
ENV SLURM_VERSION=25.11.0
ENV PLT=x86_64
ENV EnterpriseLinux=el9
ENV releaseNumber=1

# Install minimal clients: SSH client and Slurm client utilities
RUN dnf -y install --setopt=tsflags=nodocs \
    openssh-clients \
    munge \
    munge-libs \
    procps-ng \
    which \
    sudo \
  && dnf clean all || true

# Copy local RPMs from repository (build context must be repo root)
COPY /rpms/slurm-${SLURM_VERSION}-${releaseNumber}.${EnterpriseLinux}.${PLT}.rpm /tmp/rpms/

    
# If local rpms were copied, install the slurm client RPMs so the image is self-contained
RUN if [ -d /tmp/rpms ]; then \
      ls -1 /tmp/rpms || true; \
      dnf -y localinstall /tmp/rpms/*.rpm || true; \
      rm -rf /tmp/rpms; \
    fi

# Create a non-root user matching the cluster worker account
RUN useradd -m -s /bin/bash worker || true

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
