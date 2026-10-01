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
