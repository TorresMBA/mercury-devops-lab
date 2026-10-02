# 1. Preparar el host

## Instalar Ubuntu Server 24.04 LTS

Durante la instalación:

- **Disco**: instala en el SSD usando el disco entero con LVM. No toques el HDD todavía.
- **Red**: asigna una IP fija (o reserva la IP en el router para la MAC del servidor).
- **SSH**: marca "Install OpenSSH server". Si tienes tu llave pública en GitHub, impórtala ahí mismo.
- No instales Docker desde la lista de snaps del instalador: se instala después desde el repositorio oficial.

Tras el primer arranque, amplía el volumen raíz si el instalador dejó espacio sin asignar (lo hace por defecto con LVM):

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

Desde tu PC con Windows, copia tu llave SSH al servidor para poder desactivar el acceso por contraseña:

```powershell
ssh-keygen -t ed25519                      # si aún no tienes llave
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh usuario@IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

## Preparar el HDD

Solo la primera vez. **Esto borra el contenido del HDD.** Identifica el disco con `lsblk` (el HDD suele ser `/dev/sdb`; comprueba el tamaño y que no sea el disco del sistema).

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
sudo parted /dev/sdX --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L mercury-hdd /dev/sdX1
sudo blkid -s UUID -o value /dev/sdX1      # este UUID va en .env como HDD_UUID
```

## Clonar el repositorio y configurar

```bash
sudo mkdir -p /opt/mercury && sudo chown $USER: /opt/mercury
git clone <url-de-tu-repo> /opt/mercury
cd /opt/mercury
chmod +x mercury host/*.sh
git config core.fileMode false             # el bit de ejecución no cuenta como cambio
cp .env.example .env
nano .env                                  # dominio, IP, subred, HDD_UUID, zona horaria
```

## Ejecutar los scripts

Son idempotentes: se pueden repetir sin efectos secundarios.

```bash
sudo ./host/01-base.sh       # paquetes, kernel, swap, usuario SFTP, SSH, firewall
sudo ./host/02-disks.sh      # monta el HDD y crea /srv/mercury y /mnt/hdd/mercury
sudo ./host/03-docker.sh     # Docker Engine + daemon.json
sudo ./host/04-networks.sh   # redes net-tools, net-apps-dev, net-apps-prod
sudo passwd deployer         # contraseña del usuario del canal manual (SFTP)
```

Cierra la sesión SSH y vuelve a entrar para que tu usuario pertenezca al grupo `docker`.

Hay dos scripts más que se ejecutan más adelante, cuando lo indique la guía siguiente: `host/06-dns.sh` (tras levantar AdGuard) y `host/05-backup.sh`.

Qué hace cada cosa y por qué:

| Ajuste | Motivo |
|---|---|
| `vm.max_map_count=524288` | Requisito del Elasticsearch embebido de SonarQube; sin él no arranca |
| Swap hasta 8 GB, `swappiness=10` | Colchón para picos de memoria durante los builds sin usar swap en condiciones normales |
| SSH sin root y solo con llaves | El acceso por contraseña solo queda para `deployer`, que está limitado a SFTP dentro de su carpeta |
| UFW: denegar todo lo entrante salvo 22, 80, 443 (y 53, 81, 445 desde la LAN) | Reduce lo expuesto al mínimo |
| `daemon.json`: rotación de logs | Sin ella, los logs de los contenedores crecen hasta llenar el disco |
| `daemon.json`: `live-restore` | Los contenedores siguen en marcha mientras se actualiza el daemon de Docker |
| `daemon.json`: `default-address-pools` | Todas las redes de Docker salen de `10.200.0.0/16`: predecible y sin choques con la LAN |
| `daemon.json`: `metrics-addr` | Prometheus lee las métricas del propio daemon |

> **Docker y UFW.** Los puertos que un contenedor publica con `ports:` no pasan por UFW: Docker escribe sus propias reglas de red. Por eso la protección real es que solo Nginx Proxy Manager, AdGuard y Samba publiquen puertos, y que los puertos de administración se liguen a la IP de la LAN.

## Verificación

```bash
sudo ufw status verbose
sysctl vm.max_map_count                    # 524288
free -h                                    # swap total ~8 GB
df -h /srv /mnt/hdd                        # el HDD montado en /mnt/hdd
docker info | grep -A3 "Default Address"   # 10.200.0.0/16
docker network ls                          # net-tools, net-apps-dev, net-apps-prod
```

Desde otra PC de la LAN, comprueba que solo responden los puertos previstos (22 ahora; 53, 80, 443, 81 y 445 cuando levantes los stacks):

```powershell
22,53,80,443,81,445,8080,9000,9090 | % { "$_ : " + (Test-NetConnection IP_DEL_SERVIDOR -Port $_ -WarningAction SilentlyContinue).TcpTestSucceeded }
```
