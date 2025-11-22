FROM hpcdrifter/slurm.base:25.11.0
LABEL maintainer="HPCDrifter"

ENV DBD_ADDR=database \
  DBD_HOST=database \
  DBD_PORT=6819 \
  STORAGE_HOST=database.local.dev \
  STORAGE_PORT=3306 \
  STORAGE_PASS=password \
  STORAGE_USER=slurm

# clean up
RUN rm -f /packages/slurm-*.rpm /packages/openmpi-*.rpm \
  && yum clean all \
  && rm -rf /var/cache/yum

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/tini", "--", "/docker-entrypoint.sh"]