# Comandos y servicios

Listado completo de lo que se puede ejecutar en el proyecto, con una línea por comando. El detalle de cada uno está en [arquitectura/12-referencia.md](arquitectura/12-referencia.md) y el interior de los scripts en [scripts/](scripts/02-mercury.md).

| Dónde se ejecuta | Qué |
|---|---|
| Servidor, en `/opt/mercury` | [`./mercury`](#mercury), [scripts de `host/`](#scripts-de-host), [servicios programados](#servicios-programados) |
| Dentro de un pipeline de Jenkins | [`mercury-ci`](#mercury-ci) |
| PC de desarrollo | [Validación](#validación-en-la-pc-de-desarrollo) |

## `mercury`

Un `<destino>` es un stack (`jenkins`), un grupo (`devops`) o `all`. Un `<stack>` es solo un stack.

### Stacks

| Comando | Qué hace |
|---|---|
| `./mercury help` | Muestra la ayuda. Funciona sin `.env` |
| `./mercury list` | Grupos y stacks, y cuáles tienen su `.env` |
| `./mercury up <destino>` | Levanta. Aplica cambios del compose o de un `.env` |
| `./mercury down <destino>` | Detiene y elimina los contenedores. Los datos se conservan |
| `./mercury restart <destino>` | Reinicia los contenedores. No relee `.env` |
| `./mercury ps <destino>` | Estado de los contenedores |
| `./mercury pull <destino>` | Descarga las imágenes de las versiones fijadas en el `.env` |
| `./mercury config <destino>` | Muestra el compose resuelto. Detecta variables sin definir |
| `./mercury logs <stack> [servicio]` | Logs en vivo, desde las últimas 100 líneas |
| `./mercury build <stack>` | Reconstruye la imagen propia del stack (hoy, solo Jenkins) |
| `./mercury compose <stack> <args...>` | Pasa los argumentos directamente a `docker compose` |

### DNS interno

| Comando | Qué hace |
|---|---|
| `./mercury dns-init` | Genera la configuración inicial de AdGuard. No sobrescribe una existente |
| `./mercury check-dns [nombre]` | Diagnostica la cadena AdGuard → servidor → contenedores → HTTPS. Sin nombre, usa el del registry |

### Agentes de Jenkins

| Comando | Qué hace |
|---|---|
| `./mercury agents list` | Catálogo de versiones y cuáles están publicadas en el registry |
| `./mercury agents <agente>[:<versión>] ...` | Construye y publica solo esos. Sin versión, la de por defecto. La base no se reconstruye si ya existe |
| `./mercury agents base` | Construye y publica solo la imagen base |
| `./mercury agents` | Reconstruye la base y todos los agentes ya publicados. **Es el que aplica un cambio de `mercury-ci` o de `apps/_templates/`** |
| `./mercury agents rollback <agente>:<versión> <commit>` | Devuelve la etiqueta de versión a la imagen construida en ese commit |

### Apps

| Comando | Qué hace |
|---|---|
| `./mercury quick <app> <runtime> [versión]` | Modo rápido en dev: sirve `INBOX_DIR/<app>` sin Jenkins ni imagen. Runtimes: `dotnet`, `spring`, `flask`, `node`, `static` |
| `./mercury deploy <app> <dev\|prod> <tag>` | Despliega la imagen `apps/<app>:<tag>` del registry. Sirve para volver a una versión anterior |
| `./mercury undeploy <app> <dev\|prod>` | Elimina el contenedor de la app |

### Registry

| Comando | Qué hace |
|---|---|
| `./mercury registry-user <usuario>` | Crea un usuario del registry o cambia su contraseña |
| `./mercury registry-gc` | Libera en el HDD el espacio de las capas que ya no tienen etiqueta |

### Backup y limpieza

| Comando | Qué hace |
|---|---|
| `./mercury backup` | Ejecuta el backup ahora |
| `./mercury prune` | Libera disco del host: imágenes sin etiqueta, copias locales de imágenes de apps, etiquetas fijas de agentes y caché de build de más de 7 días |
| `./mercury prune --all` | Además, toda imagen que no use ningún contenedor (incluye las de stacks detenidos) |
| `./mercury prune --caches` | Además, vacía las cachés de dependencias (NuGet, Maven, npm, pip) y la de Trivy |

## Scripts de `host/`

Preparan y configuran Ubuntu. Se ejecutan con `sudo` y se pueden repetir sin efectos secundarios.

| Comando | Cuándo | Qué hace |
|---|---|---|
| `sudo ./host/01-base.sh` | Instalación | Paquetes, kernel, swap, usuario `deployer`, SSH y firewall |
| `sudo ./host/02-disks.sh` | Instalación, y al añadir un stack con datos | Monta el HDD y crea los directorios de datos con su dueño |
| `sudo ./host/03-docker.sh` | Instalación, y al cambiar `host/files/daemon.json` | Instala Docker y aplica `daemon.json` |
| `sudo ./host/04-networks.sh` | Instalación, y al añadir una red compartida | Crea las redes `net-tools`, `net-apps-dev`, `net-apps-prod` y `net-obs` |
| `sudo bash host/05-backup.sh` | Una vez, tras levantar los stacks | Crea el repositorio de backups y programa el backup diario |
| `sudo bash host/06-dns.sh` | Una vez, tras `./mercury up dns` | Hace que el servidor y sus contenedores resuelvan `*.int.<dominio>` con AdGuard |
| `sudo bash host/07-cleanup.sh` | Una vez, tras levantar los stacks | Programa la limpieza semanal de disco |
| `bash host/migrate-layout.sh` | Una vez, solo si vienes de la estructura antigua | Mueve los `.env` a `stacks/<grupo>/<stack>` |
| `bash stacks/monitoring/grafana/fetch-dashboards.sh` | Al instalar Grafana, y para actualizarlos | Descarga los dashboards de la comunidad |

`host/backup.sh` y `host/_common.sh` no se ejecutan a mano: el primero lo llama el servicio de backup (o `./mercury backup`) y el segundo lo cargan los demás scripts.

## Servicios programados

Dos tareas automáticas, instaladas como timers de systemd. Ninguna existe hasta ejecutar su script de instalación.

| Servicio | Cuándo se ejecuta | Qué hace | Lo instala | A mano |
|---|---|---|---|---|
| `mercury-backup` | Cada día a las 03:30 | Copia los datos y la configuración al HDD | `host/05-backup.sh` | `./mercury backup` |
| `mercury-prune` | Cada domingo a las 04:30 | Libera disco del Docker del host | `host/07-cleanup.sh` | `./mercury prune` |

Los dos llevan `Persistent=true`: si el servidor estaba apagado a esa hora, la tarea se ejecuta al arrancar. Corren con prioridad baja de CPU y de disco.

### Backup (`mercury-backup`)

1. Exporta un volcado de la base de datos de SonarQube, si está en marcha.
2. Copia con restic a `HDD_DIR/backups/restic`: `DATA_DIR`, `APPS_DIR`, todos los `.env` y el `credentials.env` de Jenkins.
3. Conserva 7 copias diarias y 4 semanales, y borra las anteriores.

No copia las imágenes del registry, las métricas ni los logs: se pueden regenerar. La contraseña del repositorio está en `/root/.mercury-restic-password`; sin ella no se puede restaurar, así que hay que guardar una copia fuera del servidor.

### Limpieza (`mercury-prune`)

Ejecuta `./mercury prune` sin opciones. Borra lo que se puede recuperar del registry o volver a construir, y nada que esté en uso:

- No borra una imagen que use algún contenedor.
- Si hay un build en marcha, no toca las imágenes de apps ni de agentes.
- No toca el registry, las cachés de dependencias ni las imágenes de stacks detenidos.

### Comandos de systemd y restic

| Comando | Qué hace |
|---|---|
| `systemctl list-timers 'mercury-*'` | Próxima y última ejecución de los dos timers |
| `systemctl status mercury-backup.service` | Resultado de la última ejecución del backup |
| `systemctl status mercury-prune.service` | Resultado de la última limpieza |
| `journalctl -u mercury-backup.service -n 100` | Salida del último backup |
| `journalctl -u mercury-prune.service -n 100` | Salida de la última limpieza, con el espacio antes y después |
| `sudo systemctl start mercury-backup.service` | Lanza el backup ahora, igual que lo haría el timer |
| `sudo systemctl start mercury-prune.service` | Lanza la limpieza ahora |
| `sudo systemctl disable --now mercury-prune.timer` | Desactiva la limpieza automática (igual con `mercury-backup.timer`) |
| `sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password snapshots` | Lista las copias disponibles |
| `sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password restore latest --target /tmp/restore` | Restaura la última copia en `/tmp/restore` |

## `mercury-ci`

Pasos que usan los Jenkinsfile. Solo existe dentro de los agentes; no se ejecuta en el servidor.

| Comando | Qué hace |
|---|---|
| `mercury-ci login` | Inicia sesión en el registry con la credencial `registry` |
| `mercury-ci image-ref <app> <tag>` | Imprime el nombre completo de la imagen |
| `mercury-ci check-inbox <app>` | Valida que `inbox/<app>` existe y tiene contenido (canal manual) |
| `mercury-ci sonar <clave> [args]` | Análisis de SonarQube del directorio actual |
| `mercury-ci semgrep` | Análisis de seguridad del código. Deja `semgrep.json` |
| `mercury-ci trivy-fs` | Dependencias vulnerables, secretos y mala configuración |
| `mercury-ci package <runtime> <dir> <app> <tag>` | Construye la imagen de la app y la publica |
| `mercury-ci trivy-image <imagen>` | Vulnerabilidades de la imagen final |
| `mercury-ci deploy <app> <dev\|prod> <tag>` | Despliega la imagen en el ambiente |

## Comandos de Docker de uso frecuente

No son del proyecto, pero se usan a diario junto a los anteriores.

| Comando | Qué hace |
|---|---|
| `docker ps --filter network=net-apps-prod` | Apps desplegadas en prod (`net-apps-dev` para dev) |
| `docker logs -f <app>-<env>` | Logs de una app |
| `docker stats --no-stream` | Consumo de CPU y memoria por contenedor |
| `docker system df` | Espacio que ocupan imágenes, contenedores, volúmenes y caché de build |
| `docker volume ls --filter name=mercury-` | Volúmenes de caché |
| `watch docker ps` | Ver aparecer y desaparecer los agentes durante un build |

## Validación en la PC de desarrollo

| Comando | Qué hace |
|---|---|
| `bash -n mercury pipelines/lib/mercury-ci host/*.sh` | Comprueba la sintaxis de los scripts |
| `npx --yes js-yaml <archivo>.yaml` | Comprueba la sintaxis de un YAML |

La prueba en seco de los scripts con un `docker` simulado está en [scripts/02-mercury.md](scripts/02-mercury.md#probar-sin-docker) y [scripts/03-mercury-ci.md](scripts/03-mercury-ci.md#probar-sin-docker).

## Qué ejecutar después de un cambio

| Cambié | Ejecuto |
|---|---|
| `compose.yaml` o `.env` de un stack | `./mercury up <stack>` |
| `stacks/devops/jenkins/casc/*.yaml` | `./mercury restart jenkins` |
| `plugins.txt` o `JENKINS_VERSION` | `./mercury build jenkins && ./mercury up jenkins` |
| `pipelines/lib/mercury-ci` o `apps/_templates/` | `./mercury agents` |
| `stacks/devops/jenkins/agents/<agente>` | `./mercury agents <agente>:<versión>` |
| La versión de una imagen de terceros | `./mercury pull <stack> && ./mercury up <stack>` |
| `host/files/daemon.json` | `sudo bash host/03-docker.sh` |

La tabla completa, con el motivo de cada caso, está en [arquitectura/13-mantenimiento-y-extension.md](arquitectura/13-mantenimiento-y-extension.md#qué-ejecutar-después-de-cada-cambio).
