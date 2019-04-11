FROM postgres:11.2
MAINTAINER Elico Corp <webmaster@elico-corp.com>
RUN apt-get update && \
  apt-get install -y bzip2
RUN mkdir /mnt/script /mnt/pg_backup
ADD pg_backup.sh /mnt/script/pg_backup.sh
RUN chmod +x /mnt/script/pg_backup.sh
VOLUME ["/mnt/pg_backup"]
