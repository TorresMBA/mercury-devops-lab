#!/usr/bin/env bash
# Backup de datos y configuración al HDD con restic. Lo ejecuta mercury-backup.timer.
# Aviso: el HDD está en la misma máquina; protege de borrados y de un fallo del SSD,
# no de robo o incendio. Para eso, añade un segundo repositorio restic remoto.
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

export RESTIC_REPOSITORY="$HDD_DIR/backups/restic"
export RESTIC_PASSWORD_FILE=/root/.mercury-restic-password

# Los archivos de una base de datos en marcha no son una copia consistente: se exporta un dump
if docker ps --format '{{.Names}}' | grep -qx sonar-db; then
  log "Dump de la base de datos de SonarQube"
  docker exec sonar-db pg_dump -U sonar sonar | gzip > "$DATA_DIR/sonarqube/db-dump.sql.gz"
fi

# Servidores de base de datos de prod (stacks/data/db-prod). Uno apagado no se vuelca:
# su último volcado sigue en dumps/. Un fallo avisa pero no detiene el backup del resto.
# Los de dev no se respaldan.
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }
dumps="$DATA_DIR/db/prod/dumps"
mkdir -p "$dumps"
if running pg-prod; then
  log "Dump de pg-prod"
  docker exec pg-prod pg_dumpall -U postgres | gzip > "$dumps/postgres.sql.gz.tmp" \
    && mv "$dumps/postgres.sql.gz.tmp" "$dumps/postgres.sql.gz" \
    || echo "AVISO: falló el volcado de pg-prod" >&2
fi
if running mariadb-prod; then
  log "Dump de mariadb-prod"
  docker exec mariadb-prod sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --all-databases --single-transaction --routines --events' \
    | gzip > "$dumps/mariadb.sql.gz.tmp" \
    && mv "$dumps/mariadb.sql.gz.tmp" "$dumps/mariadb.sql.gz" \
    || echo "AVISO: falló el volcado de mariadb-prod" >&2
fi
if running mssql-prod; then
  # SQL Server no vuelca a stdout: escribe un .bak por base en su volumen (mssql/backup)
  log "Backup de mssql-prod"
  mssql_backup_sql="DECLARE @s nvarchar(max) = N'';
SELECT @s += N'BACKUP DATABASE ' + QUOTENAME(name) + N' TO DISK = N''/var/opt/mssql/backup/' + name + N'.bak'' WITH INIT;'
FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE';
EXEC (@s);"
  docker exec -e SQL="$mssql_backup_sql" mssql-prod sh -c \
    'mkdir -p /var/opt/mssql/backup && exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -Q "$SQL"' \
    || echo "AVISO: falló el backup de mssql-prod" >&2
fi

# Configuración no versionada: los .env y los tokens de git de Jenkins
secrets=("$ROOT/.env" "$ROOT"/stacks/*/*/.env)
if [[ -f "$ROOT/stacks/devops/jenkins/credentials.env" ]]; then
  secrets+=("$ROOT/stacks/devops/jenkins/credentials.env")
fi

log "restic backup"
restic backup \
  "$DATA_DIR" "$APPS_DIR" "${secrets[@]}" \
  --exclude "$DATA_DIR/sonarqube/db" \
  --exclude "$DATA_DIR/sonarqube/data/es*" \
  --exclude "$DATA_DIR/sonarqube/logs" \
  --exclude "$DATA_DIR/db/dev" \
  --exclude "$DATA_DIR/db/prod/postgres" \
  --exclude "$DATA_DIR/db/prod/mariadb" \
  --exclude "$DATA_DIR/db/prod/mssql/data" \
  --exclude "$DATA_DIR/db/prod/mssql/log" \
  --exclude "$DATA_DIR/adguard/work" \
  --exclude "$DATA_DIR/jenkins/caches" \
  --exclude "$DATA_DIR/jenkins/war"

log "Retención: 7 diarios, 4 semanales"
restic forget --keep-daily 7 --keep-weekly 4 --prune
