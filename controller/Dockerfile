# Use the latest available base image
FROM hpcdrifter/slurm.base:25.11.0
LABEL maintainer="HPCDrifter"

# Install dependencies for building OpenMPI and Lmod
RUN dnf -y install epel-release && \
    dnf -y groupinstall "Development Tools" && \
    dnf -y install \
      gcc-c++ \
      gcc-gfortran \
      lua-posix \
      lua \
      lua-filesystem \
      lua-devel \
      wget \
      bzip2 \
      expect \
      bc \
      tcl \
      tcl-devel \
      procps-ng \
      make
# Install the latest OpenMPI available in the repository
RUN dnf -y install openmpi openmpi-devel

# Install the latest Lmod (8.7.53 as of the latest knowledge cutoff)
ENV LMOD_VERSION=8.7.53
RUN wget https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz && \
    tar -xzvf ${LMOD_VERSION}.tar.gz
WORKDIR /Lmod-${LMOD_VERSION}
RUN ./configure --prefix=/opt/apps && \
    make install && \
    ln -s /opt/apps/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh && \
    ln -s /opt/apps/lmod/lmod/init/cshrc /etc/profile.d/z00_lmod.csh
WORKDIR /

ENV USE_SLURMDBD=true \
    CLUSTER_NAME=snowflake \
    CONTROL_MACHINE=controller \
    SLURMCTLD_PORT=6817 \
    SLURMD_PORT=6818 \
    ACCOUNTING_STORAGE_HOST=database \
    ACCOUNTING_STORAGE_PORT=6819 \
    PARTITION_NAME=docker

# Clean up
RUN rm -rf /var/cache/dnf ${LMOD_VERSION}.tar.gz /Lmod-${LMOD_VERSION}
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/tini", "--", "/docker-entrypoint.sh"]