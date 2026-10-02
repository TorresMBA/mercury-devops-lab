#!/usr/bin/env bash
# Descarga dashboards de la comunidad (grafana.com) a dashboards/ y los enlaza
# con la fuente de datos "prometheus". Grafana los carga solo en menos de un minuto.
# Uso: bash stacks/monitoring/grafana/fetch-dashboards.sh
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dashboards"

# id en grafana.com -> nombre del archivo
declare -A DASHBOARDS=(
  [1860]=node-exporter-full
  [14282]=cadvisor
  [9964]=jenkins
)

for id in "${!DASHBOARDS[@]}"; do
  out="$dir/community-${DASHBOARDS[$id]}.json"
  echo "Descargando $id -> $(basename "$out")"
  curl -fsSL "https://grafana.com/api/dashboards/$id/revisions/latest/download" \
    | sed -E 's/\$\{DS_[A-Z0-9_]+\}/prometheus/g' > "$out"
done
