FROM hpcdrifter/slurm.base:25.11.0
LABEL maintainer="HPCDrifter"
ENV LMOD_VERSION=8.7.53

# install openmpi
RUN yum -y install \
  gcc-c++ \
  gcc-gfortran \
  epel-release \
  && yum -y localinstall \
  /packages/openmpi-*.rpm

# install lmod
RUN yum -y install \
  lua-posix \
  lua \
  lua-filesystem \
  lua-devel \
  wget \
  bzip2 \
  tcl \
  tcl-devel \
  procps-ng \
  bc \
  make

RUN wget https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz && \
    tar -xzvf ${LMOD_VERSION}.tar.gz
WORKDIR /Lmod-${LMOD_VERSION}
RUN ./configure --prefix=/opt/apps && \
    make install && \
    ln -s /opt/apps/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh && \
    ln -s /opt/apps/lmod/lmod/init/cshrc /etc/profile.d/z00_lmod.csh

WORKDIR /home/worker

# clean up
RUN rm -f /packages/slurm-*.rpm /packages/openmpi-*.rpm \
  && yum clean all \
  && rm -rf /var/cache/dnf ${LMOD_VERSION}.tar.gz /Lmod-${LMOD_VERSION}

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/tini", "--", "/docker-entrypoint.sh"]