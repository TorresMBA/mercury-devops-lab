# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repo

Infraestructura como código de un servidor doméstico de CI/CD sobre Docker Compose (Jenkins con agentes efímeros, SonarQube, registry, canal de despliegue manual, observabilidad). No hay código de aplicación: son composes, scripts bash, configuración y plantillas. Documentación, comentarios y mensajes van en español.

El repo se edita en Windows y se ejecuta en un Ubuntu Server (clonado en `/opt/mercury`). El servidor tiene 12 GB de RAM: todo servicio nuevo lleva `mem_limit` y hay que contar su coste (tabla en `README.md`).

## Validación

No hay tests ni Docker en la máquina de desarrollo. Antes de dar un cambio por bueno:

```bash
bash -n mercury pipelines/lib/mercury-ci host/*.sh        # sintaxis de scripts
npx --yes js-yaml stacks/<stack>/compose.yaml             # sintaxis YAML (un archivo)
```

La validación real solo es posible en el servidor:

```bash
./mercury config <stack>     # compose resuelto: detecta variables sin definir e include/redes inválidos
./mercury up <stack>         # stacks: edge registry jenkins sonarqube observability files management | all
./mercury logs <stack> [servicio]
```

Tras cambiar ciertas piezas hay que reconstruir, no basta con `up`:

| Cambio en | Comando |
|---|---|
| `stacks/jenkins/plugins.txt`, `JENKINS_VERSION` | `./mercury build jenkins && ./mercury up jenkins` |
| `stacks/jenkins/casc/jenkins.yaml` | `./mercury up jenkins` |
| `pipelines/lib/mercury-ci`, `apps/_templates/**`, `stacks/jenkins/agents/**` | `./mercury agents` |

Lo que no se haya ejecutado en el servidor debe declararse como no verificado; en particular la configuración JCasC de Jenkins, los permisos de `socket-proxy` y el `include` de `stacks/observability`.

## Arquitectura

### Redes: el aislamiento es por red, no por firewall

Tres redes externas creadas por `host/04-networks.sh` y declaradas `external` en cada compose:

- `net-tools`: herramientas internas. Nginx Proxy Manager (NPM) las enruta por nombre de contenedor.
- `net-apps-dev` / `net-apps-prod`: apps desplegadas. `cloudflared` solo está en `net-apps-prod`, así que internet nunca alcanza las herramientas.

Reglas que se derivan y que hay que respetar al añadir servicios:

- Solo NPM (80/443, admin :81 en la IP LAN) y Samba (:445 en la IP LAN) publican puertos. Docker salta UFW para los puertos publicados, por eso no se usa `ports:` en nada más.
- Las bases de datos van en una red propia `internal: true` del stack (modelo: `stacks/sonarqube`).
- La red `mercury-jenkins` (controller, `socket-proxy`, agentes) da acceso casi root al Docker del host: no se comparte con ningún otro servicio.
- Todas las redes salen de `10.200.0.0/16` (`host/files/daemon.json`); la regla UFW que deja a Prometheus leer node-exporter y el daemon depende de ese rango (`DOCKER_POOL` en `host/_common.sh`).

### Configuración en dos niveles

`mercury` invoca compose con `--env-file .env --env-file stacks/<stack>/.env`: el `.env` raíz tiene lo común (dominio, IP, rutas) y el del stack las versiones de imagen y los secretos. Solo se versionan los `.env.example`. Los scripts de `host/` leen el `.env` raíz a través de `host/_common.sh`.

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

### Convenciones de las que dependen varias piezas

- Toda app escucha en **8080** y su contenedor se llama **`<app>-<dev|prod>`**; NPM y el túnel apuntan a `http://<app>-<env>:8080`. El modo rápido (`compose.quick.yaml`) reutiliza el nombre `<app>-dev`.
- Nombres de app: `^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$`, validado igual en `mercury` y en `mercury-ci`.
- Imágenes: `${REGISTRY_HOST}/apps/<app>:<tag>` y `${REGISTRY_HOST}/agents/<lenguaje>:latest`.
- Dominios internos de un solo nivel bajo `*.int.<dominio>` (el wildcard no cubre más): `<app>-dev.int.<dominio>`, no `<app>.dev.int.<dominio>`.
- UID/GID 2000 (`deployer`) para lo que se sube por SFTP y Samba; UID 1000 (usuario `jenkins` de los agentes) para leer `APPS_DIR/<env>/<app>.env`.
- Las etiquetas de agente en los Jenkinsfile (`base`, `dotnet`, `maven`, `python`, `node`) deben existir como plantilla en `casc/jenkins.yaml`, como carpeta en `stacks/jenkins/agents/` y en la lista `AGENTS` de `mercury`.

### Convenciones de los compose

`name:` explícito; versión de imagen en variable del `.env` del stack (nunca `latest` para imágenes de terceros); `restart: unless-stopped`; `mem_limit`; `no-new-privileges` salvo donde rompe (Samba, cAdvisor). Un stack nuevo se añade también a la lista `STACKS` de `mercury`. La receta completa está en `docs/04-operacion-y-futuro.md`.

## Entorno de edición

- `.gitattributes` fuerza LF: los scripts se ejecutan en Linux. No introducir CRLF.
- El bit de ejecución no se conserva desde Windows; los scripts se invocan con `bash <script>` donde importa (systemd, `mercury backup`) y `docs/01-host.md` indica el `chmod` tras clonar.
- En los compose, `$` literal dentro de `command:` se escribe `$$`. En `casc/jenkins.yaml`, `${VAR}` lo sustituye JCasC con variables de entorno del controller.
