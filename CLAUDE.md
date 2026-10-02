# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repo

Infraestructura como código de un servidor doméstico de CI/CD sobre Docker Compose (Jenkins con agentes efímeros, SonarQube, registry, canal de despliegue manual, DNS interno con AdGuard Home, observabilidad). No hay código de aplicación: son composes, scripts bash, configuración y plantillas. Documentación, comentarios y mensajes van en español.

El repo se edita en Windows y se ejecuta en un Ubuntu Server (clonado en `/opt/mercury`). El servidor tiene 12 GB de RAM: todo servicio nuevo lleva `mem_limit` y hay que contar su coste (tabla en `README.md`).

## Validación

No hay tests ni Docker en la máquina de desarrollo. Antes de dar un cambio por bueno:

```bash
bash -n mercury pipelines/lib/mercury-ci host/*.sh        # sintaxis de scripts
npx --yes js-yaml stacks/<grupo>/<stack>/compose.yaml     # sintaxis YAML (un archivo)
```

La validación real solo es posible en el servidor:

```bash
./mercury list               # grupos y stacks, y cuáles tienen .env
./mercury config <destino>   # compose resuelto: detecta variables sin definir y redes inválidas
./mercury up <destino>       # destino = stack (jenkins), grupo (devops) o all
./mercury check-dns [nombre] # diagnostica la cadena AdGuard → servidor → contenedores → HTTPS
./mercury logs <stack> [servicio]
```

Tras cambiar ciertas piezas hay que reconstruir, no basta con `up`:

| Cambio en | Comando |
|---|---|
| `stacks/devops/jenkins/plugins.txt`, `JENKINS_VERSION` | `./mercury build jenkins && ./mercury up jenkins` |
| `stacks/devops/jenkins/casc/*.yaml` | `./mercury restart jenkins` (el YAML va montado: `up` no recrea el contenedor si no cambió el compose ni un `.env`) |
| `stacks/devops/jenkins/.env`, `stacks/devops/jenkins/credentials.env` | `./mercury up jenkins` |
| `pipelines/lib/mercury-ci`, `apps/_templates/**`, `stacks/devops/jenkins/agents/**` | `./mercury agents` |
| `stacks/core/dns/AdGuardHome.yaml.tmpl` | Solo afecta a instalaciones nuevas: `dns-init` no sobrescribe una configuración existente |

Lo que no se haya ejecutado en el servidor debe declararse como no verificado; en particular los permisos de `socket-proxy` para builds, el arranque de AdGuard desde la plantilla, `host/06-dns.sh`, las credenciales por dominio de Jenkins (`casc/credentials.yaml` con `credentials.env`), las carpetas de Jenkins por job-dsl y el runtime `spa`. En el servidor ya funcionan `edge`, `registry` y `jenkins`.

## Arquitectura

### Redes: el aislamiento es por red, no por firewall

Los stacks viven en `stacks/<grupo>/<stack>` (`core`, `devops`, `monitoring`, `storage`). El grupo solo organiza: cada stack es un proyecto compose independiente cuyo `name:` es el nombre corto, único entre grupos. La lista ordenada `STACKS` de `mercury` es la fuente de verdad de qué existe y en qué orden arranca.

Redes externas creadas por `host/04-networks.sh` y declaradas `external` en cada compose:

- `net-tools`: herramientas internas. Nginx Proxy Manager (NPM) las enruta por nombre de contenedor.
- `net-apps-dev` / `net-apps-prod`: apps desplegadas. `cloudflared` solo está en `net-apps-prod` y apunta directo a la app (no pasa por NPM), así que internet nunca alcanza las herramientas. Es una decisión del usuario: no enrutar el túnel por NPM.
- `net-obs`: interna, compartida por los tres stacks de `monitoring`.

Reglas que se derivan y que hay que respetar al añadir servicios:

- Solo NPM (80/443, admin :81 en la IP LAN), AdGuard (:53 en la IP LAN) y Samba (:445 en la IP LAN) publican puertos. Docker salta UFW para los puertos publicados, por eso no se usa `ports:` en nada más.
- Las bases de datos van en una red propia `internal: true` del stack (modelo: `stacks/devops/sonarqube`).
- La red `mercury-jenkins` (controller, `socket-proxy`, agentes) da acceso casi root al Docker del host: no se comparte con ningún otro servicio.
- Todas las redes salen de `10.200.0.0/16` (`host/files/daemon.json`); la regla UFW que deja a Prometheus leer node-exporter y el daemon depende de ese rango (`DOCKER_POOL` en `host/_common.sh`).

### DNS interno

AdGuard Home (`stacks/core/dns`) reescribe `*.${INT_DOMAIN}` hacia `LAN_IP`; esos nombres no existen en el DNS público. Cloudflare solo interviene en el túnel y en el desafío DNS-01 del certificado wildcard de NPM. Tres consumidores, cada uno configurado en un sitio distinto:

- **Host**: `host/06-dns.sh` escribe un drop-in de systemd-resolved con dominio de enrutamiento (`~INT_DOMAIN`), de modo que solo los nombres internos van a AdGuard y el host conserva internet si AdGuard cae.
- **Contenedores**: clave `dns` en `/etc/docker/daemon.json`, generada por `install_daemon_json` en `host/_common.sh` (la comparten `03-docker.sh` y `06-dns.sh`; `host/files/daemon.json` es solo la base). Los contenedores la toman al crearse.
- **Equipos de la LAN**: configuración manual del usuario (adaptador o DHCP del router).

La configuración inicial de AdGuard sale de `AdGuardHome.yaml.tmpl` vía `./mercury dns-init`; después AdGuard reescribe su propio YAML, así que el repo no es la fuente de verdad de su estado. `schema_version` de la plantilla debe corresponder a la versión fijada en `.env.example`.

### Configuración en dos niveles

`mercury` invoca compose con `--env-file .env --env-file stacks/<grupo>/<stack>/.env`: el `.env` raíz tiene lo común (dominio, IP, rutas) y el del stack las versiones de imagen y los secretos. Solo se versionan los `.env.example`. Los scripts de `host/` leen el `.env` raíz a través de `host/_common.sh`.

Excepción en Jenkins: los tokens de las cuentas de git van en `stacks/devops/jenkins/credentials.env` (no versionado, con su `credentials.env.example`), que el compose pasa entero al controller con `env_file`. `casc/credentials.yaml` define con ellos las credenciales, agrupadas en dominios por proveedor (ID `<proveedor>-<dueño>`). `registry` y `sonar-token` son globales y sus ID no se cambian: los usan las plantillas de agente, `mercury-ci` y los Jenkinsfile.

Datos fuera del repo: `DATA_DIR` (`/srv/mercury/data`, SSD) y `HDD_DIR` (`/mnt/hdd/mercury`). Los directorios y sus dueños (UID de cada imagen) se crean en `host/02-disks.sh`; un servicio nuevo con bind-mount necesita su línea ahí.

### Los dos canales de despliegue convergen

```
Canal CI:     Jenkinsfile del repo de la app → agente efímero → build/test → sonar → semgrep/trivy ─┐
Canal manual: compilado copiado a INBOX_DIR/<app> → job manual-release ────────────────────────────┤
                                                                                                    ▼
                  mercury-ci package (Dockerfile de apps/_templates/<runtime>) → registry → mercury-ci deploy
```

- `pipelines/lib/mercury-ci` es el único lugar con la lógica de escaneo, empaquetado y despliegue. Se copia a la imagen base de agentes junto con `apps/_templates` (en `/opt/mercury/templates`); el contexto de build de esa imagen es la raíz del repo, filtrada por `.dockerignore`.
- Los agentes no tienen daemon propio (`DOCKER_HOST=tcp://socket-proxy:2375`). Consecuencia: `-v <ruta>` desde un agente monta rutas del host, no del agente. Los escáneres se lanzan como contenedores hermanos con `--volumes-from <id del agente>`.
- `apps/_templates/compose.deploy.yaml` es el único compose de despliegue, para cualquier runtime y ambos canales. También lo usa `./mercury deploy` desde el host.
- El `Dockerfile` de cada runtime empaqueta un compilado ya hecho (no compila): por eso sirve igual para el canal manual y para el CI.
- El job `manual-release` se define en `casc/jenkins.yaml` (job-dsl), con sus parámetros ahí y no en el Jenkinsfile, que se lee del repo montado en el controller (`/usr/share/jenkins/pipelines`).
- Las carpetas de Jenkins por tecnología y framework (`dotnet`, `java/spring`, `javascript/angular`...) también salen de job-dsl en `casc/jenkins.yaml` (mapa `carpetas`). Los jobs de cada app se crean a mano dentro y viven en `DATA_DIR/jenkins`, no en el repo. La tabla carpeta → agente → plantilla → runtime está en `docs/03-despliegues.md`.
- Runtimes de empaquetado: `dotnet`, `spring`, `flask`, `node`, `static` y `spa` (nginx con retorno a `index.html`; lo usan Angular, React y Vue, con plantillas `spa/Jenkinsfile.angular`, `spa/Jenkinsfile.react` y `spa/Jenkinsfile.vue`). Un runtime nuevo se añade también al `choiceParam` `RUNTIME` de `manual-release`; la lista `RUNTIMES` de `mercury` solo cubre los que tienen `compose.quick.yaml` (`spa` no).

### Convenciones de las que dependen varias piezas

- Toda app escucha en **8080** y su contenedor se llama **`<app>-<dev|prod>`**; NPM y el túnel apuntan a `http://<app>-<env>:8080`. El modo rápido (`compose.quick.yaml`) reutiliza el nombre `<app>-dev`.
- Nombres de app: `^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$`, validado igual en `mercury` y en `mercury-ci`.
- Imágenes: `${REGISTRY_HOST}/apps/<app>:<tag>` y `${REGISTRY_HOST}/agents/<lenguaje>:latest`.
- Dominios internos de un solo nivel bajo `*.int.<dominio>` (el wildcard no cubre más): `<app>-dev.int.<dominio>`, no `<app>.dev.int.<dominio>`.
- UID/GID 2000 (`deployer`) para lo que se sube por SFTP y Samba; UID 1000 (usuario `jenkins` de los agentes) para leer `APPS_DIR/<env>/<app>.env`.
- Las etiquetas de agente en los Jenkinsfile (`base`, `dotnet`, `maven`, `python`, `node`) deben existir como plantilla en `casc/jenkins.yaml`, como carpeta en `stacks/devops/jenkins/agents/` y en la lista `AGENTS` de `mercury`.

### Convenciones de los compose

`name:` explícito; versión de imagen en variable del `.env` del stack (nunca `latest` para imágenes de terceros); `restart: unless-stopped`; `mem_limit`; `no-new-privileges` salvo donde rompe o no está probado (Samba, cAdvisor, AdGuard). Un stack nuevo se añade también a la lista `STACKS` de `mercury` como `<grupo>/<stack>`, y sus directorios de datos a `host/02-disks.sh` (que solo crea lo que falta, nunca cambia dueños de lo existente). La receta completa está en `docs/04-operacion-y-futuro.md`.

## Entorno de edición

- `.gitattributes` fuerza LF: los scripts se ejecutan en Linux. No introducir CRLF.
- El bit de ejecución no se conserva desde Windows; los scripts se invocan con `bash <script>` donde importa (systemd, `mercury backup`) y `docs/01-host.md` indica el `chmod` tras clonar. Los scripts añadidos después del clonado inicial se documentan siempre como `bash host/<script>`.
- Mover o renombrar un stack deja atrás su `.env` no versionado en el servidor: hay que acompañarlo de un paso de migración (precedente: `host/migrate-layout.sh`).
- En los compose, `$` literal dentro de `command:` se escribe `$$`. En `casc/jenkins.yaml`, `${VAR}` lo sustituye JCasC con variables de entorno del controller, también dentro de los scripts de `jobs:`.
