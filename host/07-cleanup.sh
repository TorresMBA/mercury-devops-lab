#!/usr/bin/env bash
# Programa la limpieza semanal de disco del Docker del host: ./mercury prune
# (imágenes sin etiqueta, copias locales de imágenes de apps y de agentes antiguos,
# caché de build). No toca el registry, los contenedores en marcha ni las cachés de
# dependencias. Uso: sudo bash host/07-cleanup.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log "Timer de systemd (semanal, domingo 04:30)"
cat > /etc/systemd/system/mercury-prune.service <<EOF
[Unit]
Description=Limpieza de disco de Mercury (docker)
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $ROOT/mercury prune
Nice=10
IOSchedulingClass=idle
EOF

cat > /etc/systemd/system/mercury-prune.timer <<'EOF'
[Unit]
Description=Limpieza semanal de disco de Mercury

[Timer]
OnCalendar=Sun *-*-* 04:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mercury-prune.timer
systemctl list-timers mercury-prune.timer --no-pager

cat <<EOF

Para ejecutarla ahora: ./mercury prune
Su salida queda en: journalctl -u mercury-prune.service
EOF
