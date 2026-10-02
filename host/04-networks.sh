#!/usr/bin/env bash
# Crea las redes compartidas entre stacks. Cada compose las declara como "external".
#   net-tools      herramientas internas (Jenkins, SonarQube, Grafana, registry...)
#   net-apps-dev   apps desplegadas en dev
#   net-apps-prod  apps desplegadas en prod (única red que ve cloudflared)
#   net-obs        privada del grupo monitoring, sin salida a otras redes
# Uso: sudo ./host/04-networks.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

create() { # create <red> [opciones de docker network create]
  local net="$1"; shift
  if docker network inspect "$net" >/dev/null 2>&1; then
    echo "$net ya existe"
  else
    docker network create "$@" "$net" >/dev/null
    echo "$net creada"
  fi
}

create net-tools
create net-apps-dev
create net-apps-prod
create net-obs --internal

log "Listo. Siguiente: docs/02-puesta-en-marcha.md"
