#!/usr/bin/env bash
# Instala Docker Engine desde el repositorio oficial y aplica daemon.json.
# Uso: sudo ./host/03-docker.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log "Repositorio oficial de Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
  > /etc/apt/sources.list.d/docker.list

log "Docker Engine + plugins compose y buildx"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "daemon.json"
target=/etc/docker/daemon.json
if [[ -f "$target" ]] && ! cmp -s "$HOST_DIR/files/daemon.json" "$target"; then
  cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
  echo "Copia del daemon.json anterior guardada junto al original"
fi
install -m 0644 "$HOST_DIR/files/daemon.json" "$target"
systemctl enable docker >/dev/null
systemctl restart docker

if [[ "$ADMIN_USER" != root ]]; then
  log "Añadiendo $ADMIN_USER al grupo docker (equivale a root: solo el operador)"
  usermod -aG docker "$ADMIN_USER"
  echo "Cierra sesión y vuelve a entrar para que el grupo tenga efecto."
fi

docker version --format 'Docker {{.Server.Version}}'
docker compose version

log "Listo. Siguiente: sudo ./host/04-networks.sh"
