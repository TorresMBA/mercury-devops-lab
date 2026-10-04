# 4. Operación y crecimiento

## Rutina

| Tarea | Cómo |
|---|---|
| Ver el estado general | Grafana > *Mercury - Resumen*, o `docker stats --no-stream` |
| Ver qué hay y qué está configurado | `./mercury list` |
| Liberar RAM | `./mercury down sonarqube` cuando no vayas a analizar código (3,5 GB); `./mercury down monitoring` libera otros 1,9 GB |
| Actualizar una imagen | Cambia la versión en `stacks/<grupo>/<stack>/.env`, luego `./mercury pull <stack> && ./mercury up <stack>` |
| Actualizar Jenkins o sus plugins | Cambia `JENKINS_VERSION` o `plugins.txt`, luego `./mercury build jenkins && ./mercury up jenkins` |
| Cambiar la configuración de Jenkins (carpetas, agentes, jobs por código) | Edita `stacks/devops/jenkins/casc/*.yaml`, luego `./mercury restart jenkins` (`up` no lo aplica si no cambió ningún `.env`) |
| Añadir una cuenta de git a Jenkins | Variables en `stacks/devops/jenkins/credentials.env` y bloque en `casc/credentials.yaml`, luego `./mercury up jenkins` ([detalle](03-despliegues.md#credenciales-de-git)) |
| Cambiar pasos de pipeline o plantillas | Edita `pipelines/lib/mercury-ci` o `apps/_templates/`, luego `./mercury agents` (reconstruye la base y los agentes ya publicados) |
| Publicar un agente para una versión nueva | `./mercury agents <agente>:<versión>`; el catálogo se ve con `./mercury agents list` |
| Volver a una imagen de agente anterior | `./mercury agents rollback <agente>:<versión> <commit>` |
| Liberar disco del host (SSD) | `./mercury prune`. Se ejecuta solo cada domingo si instalaste el timer (`sudo bash host/07-cleanup.sh`). Con `--caches` vacía además las cachés de dependencias; con `--all`, las imágenes de stacks detenidos ([detalle](../arquitectura/10-registry-e-imagenes.md#limpieza-del-host)) |
| Liberar espacio en el registry | Borra etiquetas desde la interfaz web y ejecuta `./mercury registry-gc` |
| Backup manual | `./mercury backup` |

Actualiza de una en una y lee las notas de versión de SonarQube y Jenkins antes de saltar de versión mayor: SonarQube migra su base de datos y no permite volver atrás sin restaurar un backup.

## Migrar desde la estructura anterior

Si clonaste el repo cuando los stacks estaban en `stacks/<stack>`, tras `git pull` hay que mover los `.env` (git no mueve archivos ignorados):

```bash
cd /opt/mercury && git pull
bash host/migrate-layout.sh                 # mueve los .env a stacks/<grupo>/<stack>
sudo bash host/02-disks.sh                  # crea los directorios nuevos (no toca los existentes)
sudo bash host/04-networks.sh               # crea la red net-obs
./mercury list                              # los stacks que ya usabas aparecen como "configurado"
./mercury up jenkins                        # se recrea: cambió la ruta de sus montajes
```

Los nombres de proyecto no cambian, así que `edge` y `registry` siguen en marcha sin recrearse. Después continúa con el paso 1 de la fase 1 de [02-puesta-en-marcha.md](02-puesta-en-marcha.md) para activar el DNS interno.

### Credencial `git` única a credenciales por cuenta

Si tu Jenkins se levantó cuando solo existía la credencial `git` (`GIT_USER` y `GIT_TOKEN` en el `.env` del stack), tras `git pull`:

```bash
cp stacks/devops/jenkins/credentials.env.example stacks/devops/jenkins/credentials.env
chmod 600 stacks/devops/jenkins/credentials.env
nano stacks/devops/jenkins/credentials.env  # pasa aquí los valores de GIT_USER y GIT_TOKEN
./mercury config jenkins                    # no debe avisar de variables sin definir
./mercury up jenkins
```

La credencial `git` desaparece y pasa a llamarse `github-mercury`: edita una vez cada job que la usara y elige la nueva. `GIT_USER` y `GIT_TOKEN` ya no se leen; bórralas del `.env`.

### De agentes `:latest` a agentes versionados

Si tus agentes se publicaron como `agents/<lenguaje>:latest`, tras `git pull` publica las imágenes con las etiquetas nuevas **antes** de reiniciar Jenkins; si no, los jobs existentes quedarían esperando agente:

```bash
cd /opt/mercury && git pull
./mercury build jenkins                          # plugin nuevo (lockable-resources)
./mercury agents base dotnet maven node python   # versiones por defecto, con las etiquetas nuevas
./mercury up jenkins                             # recrea el contenedor con la configuración nueva
./mercury agents list
```

Los jobs que usan `agent { label 'dotnet' }` siguen funcionando sin cambios: la etiqueta sin versión apunta ahora a la versión por defecto. En los Jenkinsfile que ya copiaste a tus repos, cambia `disableConcurrentBuilds()` por `disableConcurrentBuilds(abortPrevious: true)` para que un build esperando aprobación no bloquee el siguiente push. Las imágenes `:latest` antiguas se pueden borrar desde la interfaz del registry.

## Agentes de Jenkins

Cada imagen de agente se publica con dos etiquetas: la de versión (`agents/dotnet:8.0`), que es la que usa Jenkins y se mueve en cada construcción, y una fija con el commit de este repo (`agents/dotnet:8.0-a1b2c3d`). La fija permite saber qué contiene cada imagen y volver atrás.

**Volver atrás.** Si un agente reconstruido rompe los builds:

```bash
./mercury agents rollback dotnet:8.0 a1b2c3d     # la etiqueta de versión vuelve a esa imagen
```

Los commits disponibles se ven en la interfaz del registry (`agents/dotnet`). Un sufijo `-dirty` indica que la imagen se construyó con cambios sin confirmar en el repo.

**Añadir una versión al catálogo** (por ejemplo .NET 11):

1. `mercury`: añade `dotnet:11.0` a la lista `AGENTS` (y cambia `AGENT_DEFAULT` si pasa a ser la de por defecto).
2. `stacks/devops/jenkins/casc/jenkins.yaml`: copia una plantilla del mismo agente y cambia `name`, `labelString` e `image`. Si cambia la de por defecto, mueve la etiqueta sin versión a la nueva. Añade la versión al parámetro `RUNTIME_VERSION` de `manual-release`.
3. `./mercury restart jenkins` y `./mercury agents dotnet:11.0`.

La versión debe existir como etiqueta en la imagen de origen del agente (`dotnet/sdk`, `maven`, `node`, `python`) y en la de ejecución de la app.

**Limpieza.** Cada reconstrucción deja una etiqueta fija más. Borra las antiguas desde la interfaz del registry y ejecuta `./mercury registry-gc`.

## Backups

`host/backup.sh` copia cada noche a `/mnt/hdd/mercury/backups/restic`: los datos de `/srv/mercury`, un volcado de la base de datos de SonarQube, los archivos `.env` y el `credentials.env` de Jenkins.

```bash
sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password snapshots
sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password restore latest --target /tmp/restore
```

El HDD está en la misma máquina: protege de un borrado accidental o de la muerte del SSD, no de un robo o una subida de tensión. Cuando puedas, añade un segundo destino remoto (restic admite Backblaze B2, S3 o un servidor SFTP) y guarda la contraseña del repositorio fuera del servidor.

No se copian las imágenes del registry, las métricas ni los logs: se pueden regenerar.

## Alertas

Las reglas de `stacks/monitoring/metrics/prometheus/rules/mercury.yml` ya se evalúan y se ven en Grafana (*Alerting > Alert rules*). Para recibir avisos, la vía con menos piezas es crear un *Contact point* en Grafana (Telegram, correo, Discord) y una política de notificación. Alertmanager como contenedor aparte solo compensa cuando quieras gestionar las rutas de aviso como código; es la pieza que usa el stack equivalente en Kubernetes.

## Acceso remoto por VPN

Cuando lo necesites, instala Tailscale o WireGuard **en el host**, no en un contenedor. Con Tailscale, anuncia la subred de la LAN (`--advertise-routes`) y configura la IP LAN del servidor como DNS de la red de Tailscale (*split DNS* para `int.<dominio>`): los nombres `*.int.<dominio>` los resuelve AdGuard y funcionarán igual desde fuera. No hay que cambiar nada en los stacks.

## Añadir stacks nuevos

Cada servicio nuevo sigue la misma receta:

1. Carpeta `stacks/<grupo>/<nombre>/` con `compose.yaml` y `.env.example`. Usa un grupo existente si encaja; si no, crea uno (`nas`, `iot`).
2. `name:` explícito, versión de imagen en variable, `mem_limit`, `restart: unless-stopped`.
3. Sin `ports:` salvo que el protocolo no sea HTTP. Para interfaces web, conecta el servicio a `net-tools` y crea su *Proxy Host* en NPM.
4. Red privada `internal: true` para sus bases de datos.
5. Datos en `${DATA_DIR}/<nombre>` (SSD) o `${HDD_DIR}/<nombre>` (HDD); añade el directorio a `host/02-disks.sh`.
6. Añade `<grupo>/<nombre>` a la lista `STACKS` del script `mercury`, en la posición en que deba arrancar. El nombre corto debe ser único entre todos los grupos.

### Candidatos por grupo

| Grupo | Stack | Para qué | RAM aproximada |
|---|---|---|---|
| `monitoring` | `uptime` (Uptime Kuma) | Comprobar cada minuto que tus URLs responden y avisar si caen | 0,15 GB |
| `devops` | Dependency-Track | Inventario de dependencias vulnerables de todos tus proyectos a lo largo del tiempo (Trivy ya las detecta en cada build) | 3-4 GB |
| `devops` | DefectDojo | Panel único de hallazgos de Semgrep, Trivy y SonarQube | 2-3 GB |

Checkmarx no tiene edición gratuita autoalojada. Dependency-Track y DefectDojo son las alternativas libres para *gestionar* vulnerabilidades, pero ninguna cabe hoy junto a SonarQube en 12 GB: habría que alternarlas (`./mercury down sonarqube`) o ampliar la RAM. El análisis en sí ya lo hacen Semgrep y Trivy dentro de cada pipeline sin consumir memoria en reposo.

### Jenkins compartido

Hoy todos los usuarios de Jenkins son administradores y las credenciales sirven a cualquier job. Para que cada persona vea solo lo suyo:

- Añade el plugin `matrix-auth` a `plugins.txt` (`./mercury build jenkins && ./mercury up jenkins`) y sustituye `loggedInUsersCanDoAnything` por una matriz de permisos en `casc/jenkins.yaml`.
- Crea una carpeta por persona con sus jobs y guarda sus cuentas de git como credenciales de la carpeta, no globales. Solo `registry` y `sonar-token` siguen compartidas.

Esto evita accidentes y miradas ajenas, no a alguien malintencionado: cualquier pipeline habla con el Docker del host y equivale a root en el servidor.

### Mini NAS

- **Compartir archivos**: un stack `storage/nas` con un segundo servicio Samba sobre una carpeta de `/mnt/hdd/mercury/nas`. El stack `storage/files` muestra cómo.
- **Nube personal** (Nextcloud, Immich): cada uno en su stack, con su base de datos en red `internal`.
- Un único HDD no es almacenamiento seguro para datos irreemplazables. Antes de guardar fotos o documentos, añade un segundo disco o un backup remoto.

### IoT

Grupo `iot/` con Mosquitto (MQTT), Home Assistant y, si quieres, Node-RED:

- Crea una red `net-iot` propia en `host/04-networks.sh`. Los dispositivos IoT son la parte menos fiable de una red doméstica: no deben poder alcanzar Jenkins ni el registry.
- MQTT no es HTTP, así que Mosquitto sí publica su puerto: lígalo a la IP de la LAN (`${LAN_IP}:1883:1883`) y abre el puerto en UFW solo para la subred.
- Home Assistant descubre dispositivos por multidifusión y suele necesitar `network_mode: host`; es una excepción aceptable y documentada por el propio proyecto.

Vigila la RAM: con todo lo actual quedan unos 4 GB para agentes y apps. Home Assistant consume alrededor de 0,5 GB y Nextcloud con su base de datos cerca de 1 GB.

## Camino a Kubernetes

Lo que has montado aquí tiene equivalente directo. Cuando des el salto, estos conceptos ya los conoces:

| Aquí (Docker Compose) | En Kubernetes |
|---|---|
| Stack (`name:` del compose) | Namespace |
| Servicio de compose | Deployment + Service |
| `container_name` resuelto por DNS en la red | Service (`<nombre>.<namespace>.svc`) |
| Nginx Proxy Manager | Ingress Controller (Traefik, ingress-nginx) o Gateway API |
| Certificado wildcard por DNS-01 | cert-manager con el mismo desafío DNS de Cloudflare |
| AdGuard con la reescritura `*.int` | CoreDNS dentro del clúster; AdGuard sigue siendo el DNS de la LAN |
| Redes `net-apps-dev` / `net-apps-prod` | Namespaces + NetworkPolicy |
| `.env` y archivos `<app>.env` | ConfigMap y Secret |
| Directorios en `/srv/mercury` | PersistentVolume / PersistentVolumeClaim |
| `mem_limit` | `resources.requests` y `resources.limits` |
| `healthcheck` | Liveness y readiness probes |
| Agentes Docker de Jenkins | Agentes como Pods (plugin Kubernetes de Jenkins) |
| `compose.deploy.yaml` + `mercury-ci deploy` | Manifiestos o chart de Helm + `kubectl apply` / Argo CD |
| Prometheus + Grafana + Loki | Los mismos, instalados con kube-prometheus-stack |
| cloudflared | El mismo contenedor, como Deployment |

Recomendación para este hardware: aprende con **k3s** (Kubernetes ligero, un solo binario). El plano de control consume entre 0,6 y 1 GB, así que no cabe junto a todo lo actual con holgura. Dos opciones realistas:

1. Detener `sonarqube` y `monitoring` mientras practicas con k3s en el mismo servidor.
2. Practicar primero en tu PC con `kind` o `k3d` (Kubernetes dentro de Docker) y migrar el servidor cuando te sientas cómodo, empezando por las apps y dejando Jenkins para el final.

El orden de aprendizaje que mejor aprovecha lo que ya sabes: Pods y Deployments → Services e Ingress → ConfigMaps y Secrets → volúmenes → Helm → despliegue continuo con Argo CD.
