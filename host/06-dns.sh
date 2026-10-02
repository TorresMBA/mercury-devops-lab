#!/usr/bin/env bash
# Hace que el servidor y sus contenedores resuelvan los nombres internos con AdGuard Home.
# Requiere AdGuard en marcha: ./mercury dns-init && ./mercury up dns
# Uso: sudo ./host/06-dns.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

probe="comprobacion.$INT_DOMAIN"

log "Comprobando que AdGuard responde"
answer="$(docker exec adguard nslookup "$probe" 127.0.0.1 2>/dev/null \
  | awk '/^Name:/ {f = 1} f && /^Address/ {print $NF; exit}' || true)"
if [[ "$answer" != "$LAN_IP" ]]; then
  echo "AdGuard no devuelve $LAN_IP para *.$INT_DOMAIN (respuesta: '${answer:-ninguna}')." >&2
  echo "Levántalo antes de continuar: ./mercury dns-init && ./mercury up dns" >&2
  exit 1
fi
echo "*.$INT_DOMAIN -> $answer"

log "Servidor: los nombres internos se consultan a AdGuard"
# Dominio de enrutamiento (~): solo *.INT_DOMAIN va a AdGuard. El resto sigue usando
# el DNS de la red, así que el servidor conserva internet aunque AdGuard esté caído.
mkdir -p "$(dirname "$RESOLVED_DROPIN")"
cat > "$RESOLVED_DROPIN" <<EOF
[Resolve]
DNS=$LAN_IP
Domains=~$INT_DOMAIN
EOF
systemctl restart systemd-resolved

log "Contenedores: DNS en daemon.json"
if install_daemon_json; then
  # Con live-restore los contenedores siguen en marcha durante el reinicio
  systemctl restart docker
else
  echo "daemon.json sin cambios"
fi

log "Verificación"
resolved="$(getent ahostsv4 "$probe" | awk '{print $1; exit}' || true)"
if [[ "$resolved" != "$LAN_IP" ]]; then
  echo "El servidor aún no resuelve $probe (obtiene '${resolved:-nada}'). Revisa: resolvectl status" >&2
  exit 1
fi
echo "El servidor resuelve $probe -> $resolved"

cat <<EOF

Los contenedores toman el DNS nuevo al crearse. Recrea los que ya estaban en marcha
y usan nombres internos:
  ./mercury compose jenkins up -d --force-recreate

Para tus equipos de la LAN, ver "Usar AdGuard en la red" en docs/02-puesta-en-marcha.md.
EOF
