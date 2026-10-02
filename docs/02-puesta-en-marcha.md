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

> **Los valores reales van en `.env`, nunca en `.env.example`.** Los `.env.example` se suben a git; los `.env` no. Un token pegado en un `.env.example` acaba publicado en GitHub.

## Fase 1. Edge: Nginx Proxy Manager y Cloudflare

Esta fase tiene cuatro pasos y **todos son requisito de las fases siguientes**: sin el registro DNS y el certificado, ni `docker login` ni Jenkins ni SonarQube funcionarán.

### Paso 1. Registro DNS interno (en Cloudflare)

Cloudflare > tu dominio > **DNS > Records > Add record**:

| Campo | Valor |
|---|---|
| Type | `A` |
| Name | `*.int` |
| IPv4 address | la IP LAN del servidor (`LAN_IP` de tu `.env`) |
| Proxy status | **DNS only** (nube gris). Con la nube naranja no funciona |

Con esto, cualquier nombre `algo.int.tudominio.com` resuelve a la IP privada del servidor desde cualquier equipo, sin tocar archivos `hosts`. La IP es privada: desde internet no lleva a ningún sitio.

**Verificación.** No sigas hasta que el primer punto salga bien:

```bash
./mercury check-dns
```

```
ok     DNS público: 192.168.1.50
ok     DNS local: 192.168.1.50
FALLO  HTTPS: ...            <- normal por ahora: se arregla en los pasos 2 a 4
```

### Paso 2. Nginx Proxy Manager

```bash
cp stacks/edge/.env.example stacks/edge/.env
./mercury up edge
```

Abre `http://IP_DEL_SERVIDOR:81` y crea el usuario administrador.

### Paso 3. Certificado wildcard

1. En Cloudflare: **My Profile > API Tokens > Create Token**, plantilla *Edit zone DNS*, limitada a tu zona. Copia el token.
2. En NPM: **SSL Certificates > Add SSL Certificate > Let's Encrypt**.
   - Domain Names: `*.int.tudominio.com`
   - Activa *Use a DNS Challenge*, proveedor **Cloudflare**, y sustituye el valor de `dns_cloudflare_api_token` por tu token.
3. Guarda. Tarda alrededor de un minuto y no requiere abrir ningún puerto.

### Paso 4. Proxy Hosts

Crea un *Proxy Host* por herramienta a medida que las levantes. En todos: esquema `http`, pestaña **SSL** con el certificado wildcard, *Force SSL* y *HTTP/2 Support*.

| Dominio | Destino | Notas |
|---|---|---|
| `registry.int.<dominio>` | `registry-ui` : `80` | Ver fase 2: ubicación `/v2/` |
| `jenkins.int.<dominio>` | `jenkins` : `8080` | Activar *Websockets Support* |
| `sonar.int.<dominio>` | `sonarqube` : `9000` | |
| `grafana.int.<dominio>` | `grafana` : `3000` | Activar *Websockets Support* |
| `portainer.int.<dominio>` | `portainer` : `9000` | Activar *Websockets Support* |
| `<app>-dev.int.<dominio>` | `<app>-dev` : `8080` | Una por app en dev |
| `<app>.int.<dominio>` | `<app>-prod` : `8080` | Una por app en prod (acceso LAN) |

El certificado `*.int.<dominio>` cubre un solo nivel: por eso dev usa `<app>-dev.int...` y no `<app>.dev.int...`.

Si NPM muestra el destino como *Offline* es porque ese contenedor aún no existe; pasará a *Online* cuando levantes su stack.

### Si el nombre no resuelve

`./mercury check-dns [nombre]` distingue los tres casos posibles:

| Resultado | Causa | Solución |
|---|---|---|
| `FALLO DNS público: el nombre no existe` | Falta el registro del paso 1 | Créalo en Cloudflare. Es el origen del error `lookup ... no such host` de `docker login` |
| `FALLO DNS público: resuelve a ...` | El registro apunta a otra IP o tiene el proxy activado | Corrige la IP y deja la nube gris |
| `FALLO DNS local` | El router descarta respuestas DNS con IP privadas (protección contra *DNS rebinding*) | Ver abajo |

Para el tercer caso, haz que el servidor consulte a un DNS público en lugar de al router. Averigua el nombre de la interfaz con `ip -br a` y crea `/etc/netplan/60-mercury-dns.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp3s0:                       # tu interfaz
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [1.1.1.1, 1.0.0.1]
```

```bash
sudo chmod 600 /etc/netplan/60-mercury-dns.yaml
sudo netplan apply
./mercury check-dns
```

En los demás equipos de la LAN (tu PC) pasará lo mismo: pon `1.1.1.1` como DNS en el adaptador de red, o añade en el router una excepción de *rebinding* para tu dominio si lo permite.

### Túnel de Cloudflare

Solo hace falta para publicar apps en internet; puedes dejarlo para después.

1. Cloudflare Zero Trust > Networks > Tunnels > *Create a tunnel* (tipo cloudflared). Copia el token.
2. En `stacks/edge/.env` (no en `.env.example`): pega `TUNNEL_TOKEN` y pon `COMPOSE_PROFILES=tunnel,test`.
3. `./mercury up edge`
4. En el túnel, añade un *Public Hostname*: `whoami.tudominio.com` → servicio `http://whoami-prod:8080`.

**Verificación.** `https://whoami.tudominio.com` responde desde el móvil con datos (sin wifi). Después quita `test` de `COMPOSE_PROFILES`, ejecuta `./mercury compose edge --profile test down` y borra ese hostname.

Para publicar una app real: *Public Hostname* `app.tudominio.com` → `http://<app>-prod:8080`. El túnel solo puede alcanzar contenedores de `net-apps-prod`; aunque añadas por error un hostname hacia `jenkins:8080`, no resolverá.

## Fase 2. Registry

El orden importa: `docker login` es el último paso, porque necesita el registry en marcha y su Proxy Host creado.

1. Crea los usuarios y levanta el stack:

   ```bash
   cp stacks/registry/.env.example stacks/registry/.env
   ./mercury registry-user jenkins      # usuario para Jenkins (pide contraseña)
   ./mercury registry-user tu-usuario   # tu usuario personal
   ./mercury up registry
   ```

2. En NPM, crea el Proxy Host `registry.int.<dominio>` → `http` `registry-ui` : `80`, con el certificado wildcard, y además:

   - Pestaña **Custom locations**: ubicación `/v2/` → `http` `registry` puerto `5000`.
   - Pestaña **Advanced**: `client_max_body_size 0;` (las capas de imagen superan el límite por defecto).

3. Comprueba el camino completo antes de iniciar sesión:

   ```bash
   ./mercury check-dns                  # los tres puntos en "ok"
   ```

**Verificación.**

```bash
docker login registry.int.tudominio.com
docker pull traefik/whoami:v1.12.0
docker tag traefik/whoami:v1.12.0 registry.int.tudominio.com/test/whoami:1
docker push registry.int.tudominio.com/test/whoami:1
```

La imagen aparece en `https://registry.int.tudominio.com`.

| Error de `docker login` | Causa |
|---|---|
| `lookup ... no such host` | DNS: `./mercury check-dns` |
| `x509: certificate ...` | El Proxy Host no tiene asignado el certificado wildcard |
| `502 Bad Gateway` | El stack `registry` no está en marcha (`./mercury ps registry`) |
| `404` o respuesta HTML | Falta la ubicación `/v2/` en el Proxy Host |
| `401 Unauthorized` | Usuario o contraseña distintos de los creados con `./mercury registry-user` |

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
