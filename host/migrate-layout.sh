#!/usr/bin/env bash
# Migración única a la estructura por grupos (stacks/<grupo>/<stack>).
# Git mueve los archivos versionados, pero no los .env: este script los lleva a su
# nueva carpeta y elimina las carpetas antiguas que queden vacías.
# Uso (tras git pull, sin sudo): bash host/migrate-layout.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS_DIR="${1:-$ROOT/stacks}"

declare -A MOVES=(
  [edge]=core/edge
  [management]=core/management
  [registry]=devops/registry
  [jenkins]=devops/jenkins
  [sonarqube]=devops/sonarqube
  [files]=storage/files
)

for old in "${!MOVES[@]}"; do
  new="${MOVES[$old]}"
  src="$STACKS_DIR/$old/.env"
  dst="$STACKS_DIR/$new/.env"
  [[ -d "$STACKS_DIR/$new" ]] || { echo "No existe stacks/$new: ejecuta antes 'git pull'." >&2; exit 1; }

  if [[ -f "$src" ]]; then
    if [[ -e "$dst" ]]; then
      echo "stacks/$new/.env ya existe; se conserva también stacks/$old/.env (revísalo a mano)"
    else
      mv "$src" "$dst"
      echo "stacks/$old/.env -> stacks/$new/.env"
    fi
  fi

  if [[ -d "$STACKS_DIR/$old" ]]; then
    rmdir "$STACKS_DIR/$old" 2>/dev/null \
      || echo "stacks/$old no está vacía; revisa su contenido y bórrala a mano"
  fi
done

# observability se dividió en tres stacks: su .env no se puede repartir automáticamente
if [[ -f "$STACKS_DIR/observability/.env" ]]; then
  echo "stacks/observability/.env: copia sus valores a los .env de stacks/monitoring/{metrics,logs,grafana} y bórralo"
elif [[ -d "$STACKS_DIR/observability" ]]; then
  rmdir "$STACKS_DIR/observability" 2>/dev/null || true
fi

echo "Listo. Comprueba con: ./mercury list"
