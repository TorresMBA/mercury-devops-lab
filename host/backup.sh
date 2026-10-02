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
  --exclude "$DATA_DIR/adguard/work" \
  --exclude "$DATA_DIR/jenkins/caches" \
  --exclude "$DATA_DIR/jenkins/war"

log "Retención: 7 diarios, 4 semanales"
restic forget --keep-daily 7 --keep-weekly 4 --prune
