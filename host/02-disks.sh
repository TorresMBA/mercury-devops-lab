#!/usr/bin/env bash
# Monta el HDD y crea el árbol de directorios con los dueños que espera cada imagen.
# No particiona ni formatea: eso se hace a mano una vez (ver docs/01-host.md).
# Uso: sudo ./host/02-disks.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

hdd_mount="$(dirname "$HDD_DIR")"

if [[ -n "${HDD_UUID:-}" ]]; then
  log "HDD en $hdd_mount"
  blkid -U "$HDD_UUID" >/dev/null || { echo "No existe una partición con UUID $HDD_UUID" >&2; exit 1; }
  mkdir -p "$hdd_mount"
  if ! grep -q "$HDD_UUID" /etc/fstab; then
    # nofail: si el HDD falla, el servidor arranca igual
    echo "UUID=$HDD_UUID $hdd_mount ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
  fi
  mountpoint -q "$hdd_mount" || mount "$hdd_mount"
else
  echo "AVISO: HDD_UUID vacío; $HDD_DIR quedará en el disco del sistema." >&2
fi

mk() { # mk <dueño> <modo> <ruta>
  install -d -o "${1%%:*}" -g "${1##*:}" -m "$2" "$3"
}

log "Directorios de datos"
mk root:root 755 "$DATA_DIR"
mk root:root 755 "$HDD_DIR"

mk root:root 755 "$DATA_DIR/npm/data"
mk root:root 755 "$DATA_DIR/npm/letsencrypt"
mk root:root 755 "$DATA_DIR/registry/auth"
mk root:root 755 "$HDD_DIR/registry"
mk root:root 755 "$DATA_DIR/portainer"
mk root:root 755 "$DATA_DIR/alloy"
mk root:root 755 "$DATA_DIR/sonarqube"
mk root:root 755 "$DATA_DIR/sonarqube/db"          # postgres ajusta el dueño al iniciar

# Las imágenes siguientes no corren como root: el dueño debe coincidir con su UID
mk 1000:1000 755 "$DATA_DIR/jenkins"               # jenkins
mk 1000:1000 755 "$DATA_DIR/sonarqube/data"        # sonarqube
mk 1000:1000 755 "$DATA_DIR/sonarqube/extensions"
mk 1000:1000 755 "$DATA_DIR/sonarqube/logs"
mk 472:472 755 "$DATA_DIR/grafana"                 # grafana
mk 65534:65534 755 "$HDD_DIR/prometheus"           # nobody
mk 10001:10001 755 "$HDD_DIR/loki"                 # loki

mk root:root 700 "$HDD_DIR/backups"

log "Canal manual"
# El directorio del chroot SFTP debe ser de root y no escribible por otros
mk root:root 755 "$(dirname "$INBOX_DIR")"
# setgid: lo que se suba hereda el grupo y queda legible para los contenedores
mk "$DEPLOY_USER:$DEPLOY_GROUP" 2775 "$INBOX_DIR"

log "Configuración por app y ambiente (archivos <app>.env)"
# UID 1000 = usuario jenkins de los agentes, que lee estos archivos al desplegar
mk 1000:1000 750 "$APPS_DIR"
mk 1000:1000 750 "$APPS_DIR/dev"
mk 1000:1000 750 "$APPS_DIR/prod"

log "Listo. Siguiente: sudo ./host/03-docker.sh"
