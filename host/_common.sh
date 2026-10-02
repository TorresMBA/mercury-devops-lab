# Cargado por los scripts de host/. No ejecutar directamente.
set -euo pipefail

HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HOST_DIR")"

[[ $EUID -eq 0 ]] || { echo "Ejecutar con sudo" >&2; exit 1; }
[[ -f "$ROOT/.env" ]] || { echo "Falta $ROOT/.env (copia .env.example y ajústalo)" >&2; exit 1; }
set -a; . "$ROOT/.env"; set +a

# Usuario que invocó sudo: será el operador del servidor
ADMIN_USER="${SUDO_USER:-root}"

# Rango del que Docker toma las subredes de sus redes (ver files/daemon.json)
DOCKER_POOL="10.200.0.0/16"

# Usuario y grupo del canal manual (SFTP y Samba escriben con este UID/GID)
DEPLOY_USER="deployer"
DEPLOY_GROUP="mercury-deploy"
DEPLOY_ID=2000

log() { printf '\n==> %s\n' "$*"; }

# Lo escribe 06-dns.sh; su existencia indica que el host ya usa AdGuard
RESOLVED_DROPIN=/etc/systemd/resolved.conf.d/mercury.conf

# Instala /etc/docker/daemon.json a partir de files/daemon.json, añadiendo los DNS
# de los contenedores si 06-dns.sh ya se aplicó. Devuelve 0 solo si el archivo cambió.
install_daemon_json() {
  local target=/etc/docker/daemon.json tmp
  tmp="$(mktemp)"
  if [[ -f "$RESOLVED_DROPIN" ]]; then
    # AdGuard primero; 1.1.1.1 de respaldo si AdGuard está caído
    jq --arg ip "$LAN_IP" '. + {dns: [$ip, "1.1.1.1"]}' "$HOST_DIR/files/daemon.json" > "$tmp"
  else
    cat "$HOST_DIR/files/daemon.json" > "$tmp"
  fi
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ -f "$target" ]]; then
    cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
    echo "Copia del daemon.json anterior guardada junto al original"
  fi
  install -m 0644 "$tmp" "$target"
  rm -f "$tmp"
}
