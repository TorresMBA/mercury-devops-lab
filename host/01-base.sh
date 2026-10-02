#!/usr/bin/env bash
# Base del host: paquetes, kernel, swap, usuario del canal manual, SSH y firewall.
# Idempotente: se puede volver a ejecutar. Uso: sudo ./host/01-base.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log "Paquetes base"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ufw unattended-upgrades ca-certificates curl gnupg git jq htop apache2-utils restic

log "Actualizaciones de seguridad automáticas"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

log "Parámetros de kernel (requisitos de SonarQube y uso moderado de swap)"
install -m 0644 "$HOST_DIR/files/99-mercury-sysctl.conf" /etc/sysctl.d/99-mercury.conf
sysctl --system >/dev/null

log "Swap: completar hasta 8 GB"
swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
if (( swap_mb < 7000 )) && [[ ! -f /swapfile-mercury ]]; then
  fallocate -l "$(( 8192 - swap_mb ))M" /swapfile-mercury
  chmod 600 /swapfile-mercury
  mkswap /swapfile-mercury >/dev/null
  swapon /swapfile-mercury
  echo '/swapfile-mercury none swap sw 0 0' >> /etc/fstab
else
  echo "Swap actual: ${swap_mb} MB, sin cambios"
fi

log "Usuario del canal manual ($DEPLOY_USER, solo SFTP)"
getent group "$DEPLOY_GROUP" >/dev/null || groupadd -g "$DEPLOY_ID" "$DEPLOY_GROUP"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  useradd -u "$DEPLOY_ID" -g "$DEPLOY_GROUP" -M -d /inbox -s /usr/sbin/nologin "$DEPLOY_USER"
  echo "Define su contraseña con: sudo passwd $DEPLOY_USER"
fi

log "SSH"
sftp_root="$(dirname "$INBOX_DIR")"
# 10- para que tenga prioridad sobre 50-cloud-init.conf (gana el primer valor leído)
conf=/etc/ssh/sshd_config.d/10-mercury.conf
{
  echo "PermitRootLogin no"
  admin_home="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
  if [[ -s "$admin_home/.ssh/authorized_keys" ]]; then
    echo "PasswordAuthentication no"
  else
    echo "AVISO: $ADMIN_USER no tiene llaves en authorized_keys; se mantiene el acceso por contraseña." >&2
    echo "       Copia tu llave (ssh-copy-id) y vuelve a ejecutar este script." >&2
  fi
  cat <<EOF

Match Group $DEPLOY_GROUP
    ChrootDirectory $sftp_root
    ForceCommand internal-sftp -u 0002 -d /inbox
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
Match all
EOF
} > "$conf"
mkdir -p "$sftp_root"
sshd -t
systemctl restart ssh

log "Firewall (UFW)"
# Ojo: los puertos que Docker publica NO pasan por UFW. La protección real es
# no publicar puertos en los compose; estas reglas cubren los servicios del host.
ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from "$LAN_SUBNET" to any port 81,445 proto tcp
# DNS de la LAN (AdGuard Home)
ufw allow from "$LAN_SUBNET" to any port 53
# Prometheus (contenedor) lee node-exporter y las métricas del daemon de Docker en el host
ufw allow from "$DOCKER_POOL" to any port 9100,9323 proto tcp
ufw --force enable
ufw status verbose

log "Listo. Siguiente: sudo ./host/02-disks.sh"
