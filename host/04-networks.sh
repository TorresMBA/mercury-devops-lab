#!/usr/bin/env bash
# Crea las redes compartidas entre stacks. Cada compose las declara como "external".
#   net-tools      herramientas internas (Jenkins, SonarQube, Grafana, registry...)
#   net-apps-dev   apps desplegadas en dev
#   net-apps-prod  apps desplegadas en prod (única red que ve cloudflared)
# Uso: sudo ./host/04-networks.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

for net in net-tools net-apps-dev net-apps-prod; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    echo "$net ya existe"
  else
    docker network create "$net" >/dev/null
    echo "$net creada"
  fi
done

log "Listo. Siguiente: docs/02-puesta-en-marcha.md"
