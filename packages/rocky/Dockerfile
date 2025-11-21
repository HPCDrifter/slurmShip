FROM rockylinux:9
LABEL maintainer="HPCDrifter"

ENV SLURM_VERSION=25.11.0
ENV TZ=UTC
ENV PMIX_VERSION=5.0.1
ENV PRRTE_VERSION=3.0.12

RUN dnf update -y && \
    dnf install -y tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dnf reinstall -y ca-certificates && \
    dnf clean all

# Enable EPEL and CRB, then install all required packages
RUN dnf -y install epel-release && \
    dnf -y config-manager --set-enabled crb && \
    dnf -y install \
    which \
    wget \
    munge \
    munge-libs \
    munge-devel \
    rpm-build \
    rpmdevtools \
    gcc \
    gcc-c++ \
    gcc-gfortran \
    make \
    openssl \
    openssl-devel \
    libssh2-devel \
    pam-devel \
    numactl \
    numactl-devel \
    hwloc \
    hwloc-devel \
    lua \
    lua-devel \
    readline-devel \
    rrdtool-devel \
    ncurses-devel \
    gtk2-devel \
    libibmad \
    libibumad \
    perl \
    perl-Switch \
    perl-ExtUtils-MakeMaker \
    mariadb-server \
    mariadb-devel \
    libevent-devel \
    rdma-core-devel \
    libtool \
    autoconf \
    automake \
    pkgconf \
    http-parser-devel \
    json-c-devel && \
    dnf -y groupinstall "Development Tools" && \
    dnf clean all

# Build and install PMIx (external, >=4.2.0)
RUN wget https://github.com/openpmix/openpmix/releases/download/v${PMIX_VERSION}/pmix-${PMIX_VERSION}.tar.gz && \
    tar -xzf pmix-${PMIX_VERSION}.tar.gz && \
    cd pmix-${PMIX_VERSION} && \
    ./configure --prefix=/usr && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd .. && rm -rf pmix-${PMIX_VERSION} pmix-${PMIX_VERSION}.tar.gz

# Build and install PRRTE (external, >=3.0.0)
RUN wget https://github.com/openpmix/prrte/releases/download/v${PRRTE_VERSION}/prrte-${PRRTE_VERSION}.tar.gz && \
    tar -xzf prrte-${PRRTE_VERSION}.tar.gz && \
    cd prrte-${PRRTE_VERSION} && \
    PKG_CONFIG_PATH=/usr/lib64/pkgconfig ./configure --prefix=/usr && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf prrte-${PRRTE_VERSION} prrte-${PRRTE_VERSION}.tar.gz

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
VOLUME ["/packages"]
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["ls", "-alh", "/packages"]
