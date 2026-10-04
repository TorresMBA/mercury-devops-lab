# 5. Requisitos y conceptos

Qué hay que saber, qué hay que tener y qué significa cada término antes de tocar el proyecto.

## Qué es Mercury Server

Un servidor doméstico de CI/CD definido por completo como código: composes de Docker, scripts bash, configuración y plantillas. No contiene código de aplicación. Su trabajo es recibir el código o el compilado de una app, analizarlo, empaquetarlo en una imagen y desplegarlo en un ambiente `dev` o `prod` del propio servidor.

Tres ideas condicionan casi todas las decisiones:

1. **La RAM es el recurso escaso.** El servidor tiene 12 GB. Todo contenedor lleva límite de memoria y el número de builds simultáneos está acotado.
2. **El aislamiento es por red de Docker, no por firewall.** Qué puede hablar con qué se decide conectando cada contenedor a unas redes y no a otras.
3. **El repo es la fuente de verdad de la configuración; los datos y los secretos viven fuera.** Lo que se cambia desde una interfaz web y no está en el repo se pierde o queda sin documentar.

## Conocimientos mínimos

| Área | Nivel necesario | Dónde se usa |
|---|---|---|
| Linux y bash | Leer y modificar scripts con `set -euo pipefail`, arrays, `case`, expansión de parámetros (`${x%%/*}`) | `mercury`, `pipelines/lib/mercury-ci`, `host/*.sh` |
| Docker | Imágenes, etiquetas, capas, build multi-etapa, `ARG` y `ENV`, volúmenes y bind-mounts, redes, límites de memoria | Todo el repo |
| Docker Compose | Proyectos (`name:`), `--env-file`, redes `external` e `internal`, perfiles, `healthcheck`, `depends_on` | `stacks/**/compose.yaml`, `apps/_templates/` |
| Redes | DNS (resolución, reescrituras, DNS dividido), proxy inverso, TLS y certificados wildcard, subredes | `stacks/core`, `host/06-dns.sh` |
| Jenkins | Pipeline declarativo, etiquetas de agente, credenciales, `input`, `lock`, parámetros | `apps/_templates/*/Jenkinsfile*`, `pipelines/manual-release` |
| Jenkins como código | JCasC (plugin `configuration-as-code`), job-dsl, anclas YAML (`&`, `*`, `<<:`) | `stacks/devops/jenkins/casc/` |
| Git | Ramas, commits, tokens de acceso de GitHub y GitLab | Credenciales de Jenkins, etiquetas de imagen por commit |
| YAML y Groovy | Sintaxis; Groovy básico para job-dsl y Jenkinsfile | `casc/jenkins.yaml`, Jenkinsfile |
| Observabilidad | Qué es una métrica y un *scrape*, PromQL y LogQL básicos | `stacks/monitoring` |
| Ubuntu Server | systemd (servicios, timers, `systemd-resolved`), UFW, `sshd_config`, `fstab` | `host/` |

No hace falta conocer Kubernetes. La tabla de equivalencias de [04-operacion-y-futuro.md](../instalacion/04-operacion-y-futuro.md#camino-a-kubernetes) sirve de puente para quien venga de ahí.

## Requisitos del entorno

### Servidor

| Requisito | Valor de referencia | Notas |
|---|---|---|
| Sistema | Ubuntu Server 24.04 LTS, instalado sobre el hardware | Los scripts de `host/` asumen `apt`, systemd, `systemd-resolved` y UFW |
| CPU | Intel i7 de 3ª generación (x86-64) | Las imágenes son `amd64` |
| RAM | 12 GB | Los límites actuales suman unos 8,5 GB; ver [06-arquitectura.md](06-arquitectura.md#presupuesto-de-memoria) |
| SSD | 512 GB, sistema y datos (`/srv/mercury`) | Datos de servicios y configuración de apps |
| HDD | 512 GB, montado en `/mnt/hdd` | Registry, métricas, logs y backups. Opcional: sin `HDD_UUID` todo queda en el SSD |
| Red | IP fija en la LAN | Es `LAN_IP`; los puertos administrativos se ligan a ella |
| Dominio | Uno gestionado en Cloudflare | Para el certificado wildcard (desafío DNS-01) y, opcionalmente, el túnel |

### Máquina de desarrollo

El repo se edita en Windows y se ejecuta en Linux. En la máquina de desarrollo no hay Docker, así que no se pueden levantar los stacks: solo se valida sintaxis.

| Herramienta | Para qué |
|---|---|
| Git | Clonar y versionar. `.gitattributes` fuerza finales de línea LF |
| Bash (Git Bash en Windows) | `bash -n` para validar la sintaxis de los scripts |
| Node.js (`npx`) | `npx --yes js-yaml <archivo>` para validar YAML |
| Cliente SSH | Acceder al servidor y ejecutar la validación real |

El procedimiento completo de validación está en [13-mantenimiento-y-extension.md](13-mantenimiento-y-extension.md#validar-un-cambio).

### Cuentas externas

| Cuenta | Para qué | Dónde se configura |
|---|---|---|
| Cloudflare | DNS público del dominio, token de API para el certificado, túnel | NPM (certificado), `stacks/core/edge/.env` (`TUNNEL_TOKEN`) |
| GitHub, GitLab o Bitbucket | Repos de las apps; tokens de solo lectura | `stacks/devops/jenkins/credentials.env` |

## Herramientas que componen la plataforma

| Componente | Imagen | Versión fijada | Función | Stack |
|---|---|---|---|---|
| AdGuard Home | `adguard/adguardhome` | `v0.107.79` | DNS de la LAN: resuelve `*.int.<dominio>` hacia el servidor | `core/dns` |
| Nginx Proxy Manager (NPM) | `jc21/nginx-proxy-manager` | `2.16.0` | Proxy inverso con HTTPS y certificado wildcard | `core/edge` |
| cloudflared | `cloudflare/cloudflared` | `2026.9.3` | Túnel saliente hacia Cloudflare para publicar apps de prod | `core/edge` (perfil `tunnel`) |
| whoami | `traefik/whoami` | `v1.12.0` | App de prueba para validar NPM y el túnel | `core/edge` (perfil `test`) |
| Portainer CE | `portainer/portainer-ce` | `2.39.8` | Vista web de Docker. Opcional | `core/management` |
| Registry | `registry` | `3.1.2` | Almacén privado de imágenes (agentes y apps) | `devops/registry` |
| Registry UI | `joxit/docker-registry-ui` | `2.6.0` | Interfaz web del registry | `devops/registry` |
| Jenkins (controller) | `jenkins/jenkins`, reconstruida como `mercury/jenkins` | `2.580.1-lts-jdk21` | Orquesta los pipelines; no ejecuta builds | `devops/jenkins` |
| Agente de Jenkins | `jenkins/agent` | `3391.va_37fa_a_305d6d-3-jdk21` | Base de todas las imágenes de agente | `devops/jenkins/agents` |
| docker-socket-proxy | `tecnativa/docker-socket-proxy` | `v0.5.0` | Expone a Jenkins una parte de la API de Docker | `devops/jenkins` |
| SonarQube Community | `sonarqube` | `26.9.0.129388-community` | Calidad de código y *quality gate* | `devops/sonarqube` |
| PostgreSQL | `postgres` | `17.11-alpine` | Base de datos de SonarQube | `devops/sonarqube` |
| Prometheus | `prom/prometheus` | `v3.15.0` | Recoge y guarda métricas; evalúa alertas | `monitoring/metrics` |
| node-exporter | `prom/node-exporter` | `v1.12.1` | Métricas del host | `monitoring/metrics` |
| cAdvisor | `gcr.io/cadvisor/cadvisor` | `v0.55.1` | Métricas por contenedor | `monitoring/metrics` |
| Loki | `grafana/loki` | `3.7.8` | Almacén de logs | `monitoring/logs` |
| Alloy | `grafana/alloy` | `v1.20.1` | Recolector de logs de los contenedores | `monitoring/logs` |
| Grafana | `grafana/grafana` | `13.2.3` | Paneles y alertas | `monitoring/grafana` |
| Samba | `dockurr/samba` | `4.23.10` | Carpeta compartida del canal manual | `storage/files` |

Herramientas que no son servicios permanentes: se lanzan durante un build y desaparecen.

| Herramienta | Imagen | Versión | Función | Dónde se fija |
|---|---|---|---|---|
| Trivy | `aquasec/trivy` | `0.75.0` | Dependencias vulnerables, secretos, mala configuración e imagen final | `pipelines/lib/mercury-ci` |
| Semgrep | `semgrep/semgrep` | `1.178.0` | Análisis estático de seguridad del código (SAST) | `pipelines/lib/mercury-ci` |
| sonar-scanner | `sonarsource/sonar-scanner-cli` | `12.2` | Envía el análisis a SonarQube (lenguajes sin escáner propio) | `pipelines/lib/mercury-ci` |
| Escáner de SonarQube para Maven | plugin `org.sonarsource.scanner.maven:sonar-maven-plugin` | `5.8.0.7211` | Análisis de proyectos Maven desde el propio build | `apps/_templates/spring/Jenkinsfile` |
| restic | paquete de Ubuntu | la del repositorio | Backups cifrados y deduplicados | `host/01-base.sh` |

Los plugins de Jenkins (`stacks/devops/jenkins/plugins.txt`) no llevan versión fija: se instala la última compatible en el momento de construir la imagen del controller.

## Glosario

### Organización del repo

**Stack.** Un proyecto de Docker Compose independiente: una carpeta `stacks/<grupo>/<stack>` con su `compose.yaml` y su `.env.example`. Se levanta y se detiene por separado. Su `name:` es el nombre corto (`jenkins`), único entre todos los grupos.

**Grupo.** Carpeta que agrupa stacks por función (`core`, `devops`, `monitoring`, `storage`). Solo organiza: no tiene efecto en Docker.

**Destino.** Lo que aceptan los comandos de `mercury`: un stack (`jenkins`), un grupo (`devops`) o `all`.

**`.env` en dos niveles.** El `.env` de la raíz tiene lo común (dominio, IP, rutas); el de cada stack, sus versiones de imagen y secretos. `mercury` pasa ambos a compose.

### Redes y acceso

**Red externa.** Red de Docker creada fuera de los compose (`host/04-networks.sh`) y que cada compose declara con `external: true`. Es la forma de que stacks distintos compartan red.

**Red interna.** Red con `internal: true`: sus contenedores no tienen salida a internet ni a otras redes. Se usa para bases de datos y para la observabilidad.

**Proxy Host.** Regla de Nginx Proxy Manager que asocia un dominio con un contenedor y un puerto. Se crea a mano desde el panel de NPM; no está en el repo.

**DNS dividido.** El mismo dominio resuelve distinto según quién pregunte. Aquí, `*.int.<dominio>` solo existe en AdGuard, dentro de la LAN.

**Dominio de enrutamiento.** Función de `systemd-resolved` (`Domains=~int.<dominio>`): solo las consultas de ese dominio van a un servidor DNS concreto.

**Desafío DNS-01.** Forma de obtener un certificado de Let's Encrypt demostrando control del dominio mediante un registro DNS temporal, sin abrir ningún puerto. Es la única que permite certificados wildcard.

**Túnel de Cloudflare.** Conexión saliente que `cloudflared` mantiene con Cloudflare. El tráfico público entra por ella, sin abrir puertos en el router.

### CI/CD

**Controller.** El proceso central de Jenkins. Aquí tiene 0 ejecutores: planifica, pero nunca ejecuta un build.

**Agente efímero.** Contenedor que Jenkins crea para un build y destruye al terminar. Cada lenguaje y versión tiene su imagen.

**Etiqueta de agente (*label*).** Nombre con el que un Jenkinsfile pide un agente: `agent { label 'dotnet-8.0' }`. No confundir con la etiqueta (*tag*) de una imagen.

**socket-proxy.** Contenedor que recibe las llamadas a la API de Docker y solo deja pasar las familias de operaciones habilitadas. Jenkins y los agentes hablan con él, no con el socket real.

**Contenedor hermano.** Contenedor lanzado desde un agente, pero creado por el Docker del host, al mismo nivel que el agente. Los agentes no tienen Docker propio dentro.

**JCasC.** *Jenkins Configuration as Code*: la configuración de Jenkins descrita en YAML y aplicada al arrancar.

**job-dsl.** Plugin que crea jobs y carpetas a partir de un script Groovy. Aquí va incrustado en el YAML de JCasC.

**Quality gate.** Umbral de calidad que SonarQube evalúa tras el análisis. Si no se supera, el pipeline se detiene.

**SAST / SCA.** Análisis estático del código propio (Semgrep) y análisis de las dependencias de terceros (Trivy). Como referencia frente a herramientas comerciales: Semgrep hace el papel de Checkmarx o Snyk Code, y Trivy el de Snyk Open Source.

**Canal CI.** El pipeline nace de un `git push`: compila, prueba, analiza, empaqueta y despliega.

**Canal manual.** Se copia un compilado ya hecho a una carpeta y un job de Jenkins lo empaqueta y despliega. No compila ni analiza código.

**Inbox.** Carpeta del servidor (`INBOX_DIR`) donde se deja el compilado del canal manual, por SFTP o por Samba.

**Modo rápido.** `./mercury quick`: sirve la carpeta de inbox con un bind-mount, sin Jenkins ni imagen. Solo `dev`.

**Runtime.** El tipo de empaquetado de una app: `dotnet`, `spring`, `flask`, `node`, `static` o `spa`. Determina qué `Dockerfile` de `apps/_templates/` se usa.

**Agente frente a runtime.** El agente es *con qué se compila* (imagen con SDK); el runtime es *sobre qué se ejecuta* (imagen ligera sin SDK). La versión del segundo sigue a la del primero.

### Imágenes

**Etiqueta móvil.** Etiqueta que cambia de imagen con el tiempo: `agents/dotnet:8.0` apunta siempre a la última construcción de ese agente.

**Etiqueta fija.** Etiqueta que nunca se reasigna: `agents/dotnet:8.0-a1b2c3d` incluye el commit del repo con el que se construyó.

**Catálogo de agentes.** La lista `AGENTS` de `mercury`: qué combinaciones de agente y versión *se pueden* construir. No dice cuáles están construidas.

### Datos

**Bind-mount.** Montar una ruta del host dentro de un contenedor. Todos los datos persistentes usan bind-mounts bajo `DATA_DIR` o `HDD_DIR`, no volúmenes con nombre (salvo la caché de Trivy).

**`DATA_DIR`, `HDD_DIR`, `APPS_DIR`, `INBOX_DIR`.** Las cuatro raíces de datos fuera del repo. Ver [06-arquitectura.md](06-arquitectura.md#datos-fuera-del-repo).
