# 2. Puesta en marcha de los stacks

Levanta un stack, verifícalo y pasa al siguiente. En cada uno el patrón es el mismo:

```bash
cd /opt/mercury
cp stacks/<stack>/.env.example stacks/<stack>/.env
nano stacks/<stack>/.env          # contraseñas y tokens
./mercury up <stack>
./mercury ps <stack>
./mercury logs <stack>            # Ctrl+C para salir
```

`./mercury config <stack>` muestra el compose ya resuelto: úsalo para detectar variables sin definir antes de levantar nada.

## Fase 1. Edge: Nginx Proxy Manager y Cloudflare

### DNS interno

En Cloudflare, en la zona de tu dominio, crea un registro:

| Tipo | Nombre | Contenido | Proxy |
|---|---|---|---|
| A | `*.int` | IP LAN del servidor | Solo DNS (nube gris) |

Así `jenkins.int.tudominio.com` resuelve a la IP privada desde cualquier equipo, sin tocar archivos `hosts`. La IP es privada: desde internet no lleva a ningún sitio.

> Algunos routers bloquean respuestas DNS que apuntan a IP privadas (protección contra *DNS rebinding*). Si los nombres no resuelven en tu LAN, añade una excepción para tu dominio en el router o usa otro DNS en los equipos (1.1.1.1).

### Nginx Proxy Manager

```bash
./mercury up edge
```

1. Abre `http://IP_DEL_SERVIDOR:81` y crea el usuario administrador.
2. **SSL Certificates > Add > Let's Encrypt**: dominio `*.int.tudominio.com`, activa *Use a DNS Challenge*, proveedor Cloudflare y pega un token de API de Cloudflare con permiso *Zone > DNS > Edit* sobre tu zona. El certificado se emite sin abrir ningún puerto.
3. Crea un *Proxy Host* por herramienta a medida que las levantes. En todos: pestaña SSL con el certificado wildcard, *Force SSL* y *HTTP/2*.

| Dominio | Destino (http) | Notas |
|---|---|---|
| `jenkins.int.<dominio>` | `jenkins:8080` | Activar *Websockets Support* |
| `sonar.int.<dominio>` | `sonarqube:9000` | |
| `registry.int.<dominio>` | `registry-ui:80` | Ver fase 2: ubicación `/v2/` |
| `grafana.int.<dominio>` | `grafana:3000` | Activar *Websockets Support* |
| `portainer.int.<dominio>` | `portainer:9000` | Activar *Websockets Support* |
| `<app>-dev.int.<dominio>` | `<app>-dev:8080` | Una por app en dev |
| `<app>.int.<dominio>` | `<app>-prod:8080` | Una por app en prod (acceso LAN) |

El certificado `*.int.<dominio>` cubre un solo nivel: por eso dev usa `<app>-dev.int...` y no `<app>.dev.int...`.

### Túnel de Cloudflare

1. Cloudflare Zero Trust > Networks > Tunnels > *Create a tunnel* (tipo cloudflared). Copia el token.
2. En `stacks/edge/.env`: pega `TUNNEL_TOKEN` y pon `COMPOSE_PROFILES=tunnel,test`.
3. `./mercury up edge`
4. En el túnel, añade un *Public Hostname*: `whoami.tudominio.com` → servicio `http://whoami-prod:8080`.

**Verificación.** `https://whoami.tudominio.com` responde desde el móvil con datos (sin wifi). Después quita `test` de `COMPOSE_PROFILES`, ejecuta `./mercury compose edge --profile test down` y borra ese hostname.

Para publicar una app real: *Public Hostname* `app.tudominio.com` → `http://<app>-prod:8080`. El túnel solo puede alcanzar contenedores de `net-apps-prod`; aunque añadas por error un hostname hacia `jenkins:8080`, no resolverá.

## Fase 2. Registry

```bash
cp stacks/registry/.env.example stacks/registry/.env
./mercury registry-user jenkins      # usuario para Jenkins (pide contraseña)
./mercury registry-user tu-usuario   # tu usuario personal
docker login registry.int.tudominio.com   # tras crear el Proxy Host de abajo
./mercury up registry
```

En NPM, crea `registry.int.<dominio>` → `registry-ui:80` y además:

- Pestaña **Custom locations**: ubicación `/v2/` → `http` `registry` puerto `5000`.
- Pestaña **Advanced**: `client_max_body_size 0;` (las capas de imagen superan el límite por defecto).

**Verificación.**

```bash
docker login registry.int.tudominio.com
docker pull traefik/whoami:v1.12.0
docker tag traefik/whoami:v1.12.0 registry.int.tudominio.com/test/whoami:1
docker push registry.int.tudominio.com/test/whoami:1
```

La imagen aparece en `https://registry.int.tudominio.com`.

## Fase 3. Jenkins

```bash
cp stacks/jenkins/.env.example stacks/jenkins/.env
nano stacks/jenkins/.env             # admin, usuario del registry, token de git
./mercury agents                     # construye y publica las imágenes de agentes (tarda)
./mercury up jenkins
```

Jenkins arranca ya configurado desde `stacks/jenkins/casc/jenkins.yaml`: usuario administrador, credenciales, la nube Docker con una plantilla de agente por lenguaje y el job `manual-release`. No hay asistente inicial.

**Verificación.** Crea un job *Pipeline* con este script y ejecútalo mientras miras `watch docker ps` en el servidor: aparece un contenedor de agente y desaparece al terminar.

```groovy
pipeline {
  agent { label 'dotnet' }
  stages { stage('Hola') { steps { sh 'dotnet --version && docker version' } } }
}
```

Si el agente no llega a conectar, revisa `./mercury logs jenkins` y `./mercury logs jenkins socket-proxy`. Causas habituales: la imagen del agente no está en el registry (`./mercury agents`) o las credenciales `REGISTRY_USER`/`REGISTRY_PASSWORD` no coinciden con las de `./mercury registry-user`.

## Fase 4. SonarQube

```bash
cp stacks/sonarqube/.env.example stacks/sonarqube/.env
./mercury up sonarqube               # tarda 2-3 minutos en estar listo
```

1. Entra en `https://sonar.int.<dominio>` con `admin` / `admin` y cambia la contraseña.
2. **Mi cuenta > Seguridad**: genera un token de tipo *Global Analysis Token*. Ponlo en `stacks/jenkins/.env` como `SONAR_TOKEN` y ejecuta `./mercury up jenkins`.
3. **Administration > Configuration > Webhooks**: crea uno con URL `http://jenkins:8080/sonarqube-webhook/`. Es lo que avisa a Jenkins del resultado del *quality gate*.

**Verificación.** El primer pipeline de la fase siguiente crea el proyecto en SonarQube y la etapa *Quality gate* termina en verde.

## Fase 5. Canal manual

```bash
cp stacks/files/.env.example stacks/files/.env
./mercury up files
```

- **Samba**: en el Explorador de Windows, `\\IP_DEL_SERVIDOR\inbox` con el usuario y contraseña de `stacks/files/.env`.
- **SFTP**: WinSCP o FileZilla a `IP_DEL_SERVIDOR`, puerto 22, usuario `deployer`. Entra directamente en `/inbox`.

Ambos escriben en la misma carpeta (`INBOX_DIR`) con el mismo usuario, así que puedes alternarlos.

## Fase 6. Observabilidad

```bash
cp stacks/observability/.env.example stacks/observability/.env
bash stacks/observability/grafana/fetch-dashboards.sh    # dashboards de la comunidad
./mercury up observability
```

**Verificación.**

- En Grafana (`https://grafana.int.<dominio>`), carpeta *Mercury*: el dashboard *Mercury - Resumen* muestra CPU, RAM, discos y consumo por contenedor.
- *Explore > Loki*: la consulta `{stack="jenkins"}` devuelve los logs de Jenkins.
- Prometheus no se publica. Para ver sus *targets*: `docker exec prometheus wget -qO- localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'`. Todos deben estar `up`.

## Fase 7. Backups y Portainer

```bash
sudo ./host/05-backup.sh             # repositorio restic en el HDD + timer diario
./mercury backup                     # primera copia

cp stacks/management/.env.example stacks/management/.env
./mercury up management              # opcional
```

Portainer exige crear el administrador en los primeros minutos tras arrancar; si se pasa el plazo, `./mercury restart management`.
