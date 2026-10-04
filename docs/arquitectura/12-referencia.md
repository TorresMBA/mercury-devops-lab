# 12. Referencia

Comandos, variables y scripts, para consultar. Las explicaciones están en los documentos 06 a 11; el interior de `mercury` y `mercury-ci`, en la carpeta [scripts](../scripts/02-mercury.md).

Para un listado rápido de todos los comandos y de los servicios programados, sin el detalle: [comandos.md](../comandos.md).

## `mercury`

Script bash de la raíz del repo. Se ejecuta en el servidor, desde cualquier directorio. Exige el `.env` raíz, salvo para `help`.

Un `<destino>` es un stack (`jenkins`), un grupo (`devops`), la ruta completa (`devops/jenkins`) o `all`.

### Stacks

| Comando | Equivale a | Notas |
|---|---|---|
| `list` | — | Grupos, stacks y cuáles tienen `.env` |
| `up <destino>` | `compose up -d` | |
| `down <destino>` | `compose down` | Elimina los contenedores; los datos se conservan |
| `restart <destino>` | `compose restart` | No relee `.env` ni el compose |
| `ps <destino>` | `compose ps` | |
| `pull <destino>` | `compose pull --ignore-buildable` | Descarga las versiones fijadas en el `.env` |
| `config <destino>` | `compose config` | Compose resuelto: detecta variables sin definir y redes inválidas |
| `logs <stack> [servicio]` | `compose logs -f --tail 100` | Solo un stack |
| `build <stack>` | `compose build --pull` | Solo un stack; hoy solo Jenkins tiene imagen propia |
| `compose <stack> <args...>` | `compose <args...>` | Paso directo a `docker compose`, con los dos `.env` |

Con un grupo o `all`, los stacks sin `.env` se omiten con un aviso. Con un único stack sin `.env`, el comando falla. Jenkins exige además `credentials.env`.

### DNS

| Comando | Qué hace |
|---|---|
| `dns-init` | Genera `DATA_DIR/adguard/conf/AdGuardHome.yaml` desde la plantilla. No sobrescribe uno existente. Exige `ADGUARD_PASSWORD` cambiada y `htpasswd` |
| `check-dns [nombre]` | Comprueba AdGuard → servidor → contenedor nuevo → HTTPS, y se detiene en el primer fallo. Por defecto usa `REGISTRY_HOST`; admite un nombre corto |

### Agentes

| Comando | Qué hace |
|---|---|
| `agents list` | Catálogo, etiqueta de Jenkins de cada entrada y si está publicada |
| `agents <agente>[:<versión>] ...` | Construye y publica solo esos. Sin versión, la de por defecto. Admite `base` |
| `agents` | Reconstruye la base y los agentes ya publicados |
| `agents rollback <agente>:<versión> <commit>` | Reasigna la etiqueta móvil a la imagen de ese commit. Admite `base` |

Lee el `.env` de Jenkins (`AGENT_VERSION`). Detalle en [08-jenkins-y-agentes.md](08-jenkins-y-agentes.md#imágenes-de-agente).

### Apps

| Comando | Qué hace |
|---|---|
| `quick <app> <runtime> [versión]` | Modo rápido en dev. Runtimes: `dotnet`, `spring`, `flask`, `node`, `static` |
| `deploy <app> <dev\|prod> <tag>` | Despliega `apps/<app>:<tag>` del registry |
| `undeploy <app> <dev\|prod>` | `docker compose -p <app>-<env> down` |

### Registry y operación

| Comando | Qué hace |
|---|---|
| `registry-user <usuario>` | Crea o actualiza un usuario en el `htpasswd` (pide contraseña) |
| `registry-gc` | Libera el espacio de las capas sin etiqueta |
| `backup` | Ejecuta `host/backup.sh` ahora. Requiere haber ejecutado `host/05-backup.sh` |
| `prune` | Libera disco del host: imágenes sin etiqueta, copias locales de imágenes de apps que no usa ningún contenedor, etiquetas fijas de agentes, caché de build de más de 7 días. Muestra `docker system df` antes y después |
| `prune --all` | Además, toda imagen sin contenedor, incluidas las de stacks detenidos |
| `prune --caches` | Además, borra los volúmenes `mercury-cache-*` y `mercury-trivy-cache` |

Detalle de `prune` en [10-registry-e-imagenes.md](10-registry-e-imagenes.md#limpieza-del-host).

## `mercury-ci`

Script bash instalado en los agentes. Exige `REGISTRY_HOST`. Los pasos están descritos en [09-pipelines-y-despliegue.md](09-pipelines-y-despliegue.md#mercury-ci).

```
mercury-ci login
mercury-ci image-ref <app> <tag>
mercury-ci check-inbox <app>
mercury-ci sonar <clave> [args de sonar-scanner]
mercury-ci semgrep
mercury-ci trivy-fs
mercury-ci package <runtime> <dir> <app> <tag>
mercury-ci trivy-image <imagen>
mercury-ci deploy <app> <dev|prod> <tag>
```

## Variables

### `.env` raíz

Lo leen `mercury`, todos los compose y los scripts de `host/`.

| Variable | Ejemplo | Uso |
|---|---|---|
| `BASE_DOMAIN` | `ejemplo.com` | Dominio gestionado en Cloudflare. Informativa: ningún script ni compose la lee |
| `INT_DOMAIN` | `int.ejemplo.com` | Sufijo de los nombres internos: reescritura de AdGuard, dominio de enrutamiento del host, URLs de Jenkins, SonarQube y Grafana |
| `REGISTRY_HOST` | `registry.int.ejemplo.com` | Prefijo de todas las imágenes propias |
| `LAN_IP` | `192.168.1.50` | IP a la que se ligan los puertos 53, 81 y 445; respuesta de la reescritura DNS |
| `LAN_SUBNET` | `192.168.1.0/24` | Origen permitido en las reglas UFW de 53, 81 y 445 |
| `HDD_UUID` | UUID de `blkid` | Partición ext4 del HDD. Vacío: no se monta y `HDD_DIR` queda en el disco del sistema |
| `DATA_DIR` | `/srv/mercury/data` | Datos de servicios (SSD) |
| `APPS_DIR` | `/srv/mercury/apps` | Archivos `<env>/<app>.env` |
| `INBOX_DIR` | `/srv/mercury/sftp/inbox` | Canal manual. Su directorio padre es el chroot de SFTP |
| `HDD_DIR` | `/mnt/hdd/mercury` | Registry, métricas, logs, backups. Su directorio padre es el punto de montaje del HDD |
| `TZ` | `UTC` | Zona horaria de NPM, Jenkins y Grafana |

`mercury-ci` asume que `APPS_DIR` es `/srv/mercury/apps` y las plantillas de agente lo montan en esa ruta fija. Si se cambia `APPS_DIR` en el host, hay que revisar ambos.

### `.env` de cada stack

| Stack | Variable | Uso |
|---|---|---|
| `core/dns` | `ADGUARD_VERSION` | Versión de la imagen |
| | `ADGUARD_USER`, `ADGUARD_PASSWORD` | Solo para `dns-init`. Después la contraseña se cambia en el panel |
| `core/edge` | `NPM_VERSION`, `CLOUDFLARED_VERSION`, `WHOAMI_VERSION` | Versiones |
| | `TUNNEL_TOKEN` | Token del túnel de Cloudflare |
| | `COMPOSE_PROFILES` | `tunnel` (cloudflared), `test` (whoami), separados por coma |
| `core/management` | `PORTAINER_VERSION` | Versión |
| `devops/registry` | `REGISTRY_VERSION`, `REGISTRY_UI_VERSION` | Versiones |
| `devops/jenkins` | `JENKINS_VERSION` | Versión del controller. Cambiarla exige `build` |
| | `AGENT_VERSION` | Versión de `jenkins/agent`, base de los agentes. Cambiarla exige `./mercury agents` |
| | `SOCKET_PROXY_VERSION` | Versión |
| | `JENKINS_MAX_AGENTS` | Agentes simultáneos en todo el servidor (2 por defecto) |
| | `JENKINS_ADMIN_ID`, `JENKINS_ADMIN_PASSWORD` | Usuario administrador |
| | `REGISTRY_USER`, `REGISTRY_PASSWORD` | Usuario creado con `./mercury registry-user` |
| | `SONAR_TOKEN` | Token de análisis generado en SonarQube |
| `devops/sonarqube` | `SONARQUBE_VERSION`, `POSTGRES_VERSION` | Versiones |
| | `SONAR_DB_PASSWORD` | Contraseña de la base de datos |
| `monitoring/metrics` | `PROMETHEUS_VERSION`, `NODE_EXPORTER_VERSION`, `CADVISOR_VERSION` | Versiones |
| `monitoring/logs` | `LOKI_VERSION`, `ALLOY_VERSION` | Versiones |
| `monitoring/grafana` | `GRAFANA_VERSION` | Versión |
| | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` | Usuario administrador. Solo se aplican en el primer arranque |
| `storage/files` | `SAMBA_VERSION` | Versión |
| | `SAMBA_USER`, `SAMBA_PASSWORD` | Acceso a la carpeta compartida |

### `credentials.env` de Jenkins

Un par de variables por cuenta de git, sin comillas ni espacios alrededor del `=`:

```
GITHUB_MERCURY_USER=...
GITHUB_MERCURY_TOKEN=...
```

Cada par corresponde a un bloque de `casc/credentials.yaml`. Basta un token de solo lectura (GitHub: *Contents read*; GitLab: `read_repository`). Proteger con `chmod 600`.

### Variables de `mercury-ci` y de los Jenkinsfile

Se definen en el bloque `environment` del Jenkinsfile de la app, salvo que se indique otra cosa.

| Variable | Por defecto | Efecto |
|---|---|---|
| `APP` | — | Nombre de la app: imagen, contenedor y clave de proyecto en SonarQube |
| `TAG` | `BUILD_NUMBER` | Etiqueta de la imagen |
| `MERCURY_SCAN_STRICT` | `0` | `1`: los hallazgos de Semgrep y Trivy rompen el build |
| `MERCURY_SCAN_SEVERITY` | `HIGH,CRITICAL` | Severidades que informa Trivy |
| `MERCURY_SCAN_MEMORY` | `1536m` | Límite de memoria de cada escáner |
| `MERCURY_DOCKERFILE` | vacía | Ruta de un Dockerfile del repo, o `template` para forzar la plantilla |
| `APP_MEM_LIMIT` | `512m` | Límite de memoria de la app desplegada |
| `RUNTIME_VERSION` | La del agente | Versión de la imagen de ejecución. La exporta la imagen del agente; en el canal manual es un parámetro |
| `TRIVY_IMAGE`, `SEMGREP_IMAGE`, `SONAR_SCANNER_IMAGE` | Fijadas en `mercury-ci` | Imagen de cada escáner |
| `SOLUTION`, `PROJECT` | — | Solo .NET: solución que se compila y proyecto web que se publica |
| `DIST_DIR` | — | Solo Angular, React y Vue: carpeta con `index.html` tras el build |
| `SITE_DIR` | `.` | Solo estático: carpeta con `index.html` |

Variables que pone la plataforma en todo agente (ancla `x-agent-base`): `DOCKER_HOST=tcp://socket-proxy:2375` y `REGISTRY_HOST`.

Variables que lee la app en ejecución, y que se definen en `APPS_DIR/<env>/<app>.env`:

| Variable | Runtime | Efecto |
|---|---|---|
| `APP_DLL` | `dotnet` | Ensamblado a ejecutar, si hay más de un `*.runtimeconfig.json` |
| `JAVA_OPTS` | `spring` | Opciones de la JVM (por defecto `-XX:MaxRAMPercentage=75.0`) |
| `APP_MODULE` | `flask` | `<módulo>:<objeto>`; por defecto `app:app` |

## Scripts de `host/`

Todos se ejecutan con `sudo`, cargan `host/_common.sh` y leen el `.env` raíz. Son idempotentes.

| Script | Cuándo | Qué hace |
|---|---|---|
| `01-base.sh` | Instalación | Paquetes (`ufw`, `jq`, `apache2-utils`, `restic`...), actualizaciones automáticas de seguridad, parámetros de kernel, swap hasta 8 GB, usuario `deployer`, configuración de SSH, reglas UFW |
| `02-disks.sh` | Instalación, y tras añadir un stack con datos | Monta el HDD por UUID con `nofail` y crea los directorios con su dueño. No particiona ni formatea. No toca lo existente |
| `03-docker.sh` | Instalación | Docker Engine, buildx y compose desde el repositorio oficial; instala `daemon.json`; añade al operador al grupo `docker` |
| `04-networks.sh` | Instalación, y tras añadir una red compartida | Crea `net-tools`, `net-apps-dev`, `net-apps-prod` y `net-obs` (interna) si no existen |
| `05-backup.sh` | Tras levantar los stacks | Contraseña y repositorio restic; servicio y timer de systemd (03:30) |
| `06-dns.sh` | Tras `./mercury up dns` | Comprueba que AdGuard responde; drop-in de systemd-resolved; añade `dns` a `daemon.json` y reinicia Docker |
| `07-cleanup.sh` | Tras levantar los stacks | Servicio y timer de systemd que ejecutan `./mercury prune` cada domingo a las 04:30 |
| `backup.sh` | Lo llama el timer o `./mercury backup` | Volcado de SonarQube, `restic backup`, retención |
| `migrate-layout.sh` | Una vez, sin `sudo`, al migrar desde la estructura antigua | Mueve los `.env` de `stacks/<stack>` a `stacks/<grupo>/<stack>` |

Constantes de `host/_common.sh`:

| Constante | Valor | Uso |
|---|---|---|
| `DOCKER_POOL` | `10.200.0.0/16` | Regla UFW para Prometheus. Debe coincidir con `default-address-pools` de `files/daemon.json` |
| `DEPLOY_USER`, `DEPLOY_GROUP`, `DEPLOY_ID` | `deployer`, `mercury-deploy`, `2000` | Usuario del canal manual. El `2000` se repite en el compose de Samba |
| `RESOLVED_DROPIN` | `/etc/systemd/resolved.conf.d/mercury.conf` | Su existencia indica que el host ya usa AdGuard |
| `ADMIN_USER` | Quien invocó `sudo` | Se añade al grupo `docker`; se comprueba que tenga llaves SSH |

Comportamientos que conviene conocer:

- **`01-base.sh` solo desactiva el acceso por contraseña si el operador tiene llaves** en `authorized_keys`. Si no, avisa y lo mantiene, para no dejar el servidor inaccesible.
- **`install_daemon_json`** valida el archivo generado con `dockerd --validate` antes de instalarlo (un `daemon.json` inválido impide arrancar Docker), guarda una copia del anterior junto al original y solo reinicia Docker si el archivo cambió.
- **`builder.gc`** en `daemon.json` limita la caché de build a 10 GB.
- **`live-restore`** en `daemon.json` mantiene los contenedores en marcha mientras se reinicia el daemon.

### Archivos que escriben en el sistema

| Ruta | Script | Contenido |
|---|---|---|
| `/etc/sysctl.d/99-mercury.conf` | `01-base.sh` | `vm.max_map_count=524288`, `fs.file-max=131072`, `vm.swappiness=10` |
| `/etc/apt/apt.conf.d/20auto-upgrades` | `01-base.sh` | Actualizaciones de seguridad automáticas |
| `/swapfile-mercury` y línea en `/etc/fstab` | `01-base.sh` | Swap adicional |
| `/etc/ssh/sshd_config.d/10-mercury.conf` | `01-base.sh` | Sin root, sin contraseña, bloque SFTP |
| Línea del HDD en `/etc/fstab` | `02-disks.sh` | Montaje por UUID |
| `/etc/docker/daemon.json` | `03-docker.sh`, `06-dns.sh` | Rotación de logs, `live-restore`, rango de redes, métricas, tope de la caché de build, DNS |
| `/etc/systemd/system/mercury-prune.{service,timer}` | `07-cleanup.sh` | Limpieza semanal de disco |
| `/etc/systemd/resolved.conf.d/mercury.conf` | `06-dns.sh` | Dominio de enrutamiento hacia AdGuard |
| `/etc/systemd/system/mercury-backup.{service,timer}` | `05-backup.sh` | Backup diario |
| `/root/.mercury-restic-password` | `05-backup.sh` | Contraseña del repositorio de backups |

## Rutas dentro de los contenedores

| Contenedor | Ruta | Origen |
|---|---|---|
| `jenkins` | `/var/jenkins_home` | `DATA_DIR/jenkins` |
| `jenkins` | `/usr/share/jenkins/casc` | `stacks/devops/jenkins/casc`, solo lectura |
| `jenkins` | `/usr/share/jenkins/pipelines` | `pipelines/`, solo lectura |
| Agentes | `/home/jenkins/agent` | *Workspace*, efímero |
| Agentes | `/inbox` | `INBOX_DIR`, solo lectura |
| Agentes | `/srv/mercury/apps` | `APPS_DIR`, solo lectura |
| Agentes | `/usr/local/bin/mercury-ci` | `pipelines/lib/mercury-ci`, copiado al construir la base |
| Agentes | `/opt/mercury/templates` | `apps/_templates`, copiado al construir la base |
| Agentes | `/opt/java/openjdk` | Java de la imagen base: lo usa el proceso del agente |
| Agentes | `/home/jenkins/.nuget/packages`, `.m2/repository`, `.npm`, `.cache/pip` | Volúmenes `mercury-cache-*`, compartidos entre builds |
| Agentes | `/tmp/mercury-trivy-db-al-dia` | Marcador que deja `trivy-fs` para que `trivy-image` no actualice de nuevo la base de datos |
| Agentes `maven` | `/opt/jdk` | JDK del proyecto |
