#!/usr/bin/env bash
# Prepara el repositorio restic en el HDD y programa el backup diario.
# Uso: sudo ./host/05-backup.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

pass_file=/root/.mercury-restic-password
repo="$HDD_DIR/backups/restic"

if [[ ! -f "$pass_file" ]]; then
  log "Generando contraseña del repositorio en $pass_file"
  (umask 077; head -c 32 /dev/urandom | base64 > "$pass_file")
  echo "Guarda una copia fuera del servidor: sin ella el backup no se puede restaurar."
fi

if [[ ! -d "$repo" ]]; then
  log "Inicializando repositorio restic"
  restic -r "$repo" --password-file "$pass_file" init
fi

log "Timer de systemd (diario, 03:30)"
cat > /etc/systemd/system/mercury-backup.service <<EOF
[Unit]
Description=Backup de Mercury (restic)
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $HOST_DIR/backup.sh
Nice=10
IOSchedulingClass=idle
EOF

cat > /etc/systemd/system/mercury-backup.timer <<'EOF'
[Unit]
Description=Backup diario de Mercury

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mercury-backup.timer
systemctl list-timers mercury-backup.timer --no-pager
