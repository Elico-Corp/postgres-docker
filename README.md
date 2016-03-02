# postgres-docker
Postgres Docker image based on the official Postgres image with backup support

To see the backup script help, use the following command:
docker exec -it <POSTGRES CONTAINER> /mnt/script/pg_backup.sh help

Backups will be created in this directory (you can mount a volume):
/mnt/pg_backup
