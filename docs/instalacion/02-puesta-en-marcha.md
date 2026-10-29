# 2. Puesta en marcha de los stacks

Los stacks están agrupados por función en `stacks/<grupo>/<stack>`. `./mercury list` muestra todos y cuáles tienen ya su `.env`:

| Grupo | Stacks |
|---|---|
| `core` | `dns` (AdGuard Home), `edge` (Nginx Proxy Manager + túnel), `management` (Portainer) |
| `devops` | `registry`, `jenkins`, `sonarqube` |
| `monitoring` | `metrics`, `logs`, `grafana` |
| `storage` | `files` (Samba) |
| `data` | `db-dev`, `db-prod` (PostgreSQL, MariaDB y SQL Server de las apps, a demanda) |

Levanta un stack, verifícalo y pasa al siguiente. El patrón es siempre el mismo:

```bash
cd /opt/mercury
cp stacks/<grupo>/<stack>/.env.example stacks/<grupo>/<stack>/.env
nano stacks/<grupo>/<stack>/.env   # contraseñas y tokens
./mercury up <stack>               # también acepta un grupo (devops) o all
./mercury ps <stack>
./mercury logs <stack>             # Ctrl+C para salir
```

`./mercury config <stack>` muestra el compose ya resuelto: úsalo para detectar variables sin definir antes de levantar nada.

> **Los valores reales van en `.env`, nunca en `.env.example`.** Los `.env.example` se suben a git; los `.env` no. Un token pegado en un `.env.example` acaba publicado en GitHub.

## Fase 1. Core: DNS interno, Nginx Proxy Manager y certificado

Todo lo demás depende de esta fase: sin DNS interno y certificado, ni `docker login` ni Jenkins ni SonarQube funcionan.

```
                      tudominio.com
              ┌────────────┴────────────┐
           Público                   Interno
        Cloudflare DNS            Cloudflare DNS (A *.int, equipos de la LAN)
              │                   AdGuard Home (servidor y contenedores)
              │                         │
      app.tudominio.com        *.int.tudominio.com → IP LAN
              │                         │
       Cloudflare Tunnel       Nginx Proxy Manager (:443)
              │                         │
        apps en prod           herramientas y apps (dev y prod)
```

### Paso 1. DNS interno con AdGuard Home

AdGuard resuelve cualquier nombre `algo.int.tudominio.com` hacia la IP LAN del servidor y reenvía el resto a internet. Lo usan el servidor y sus contenedores; los equipos de la LAN resuelven esos nombres con un registro público de Cloudflare (ver [Resolver los nombres desde la LAN](#resolver-los-nombres-desde-la-lan)).

```bash
cp stacks/core/dns/.env.example stacks/core/dns/.env
nano stacks/core/dns/.env          # usuario y contraseña del panel
./mercury dns-init                 # genera la configuración inicial (con la reescritura *.int)
./mercury up dns
sudo bash host/06-dns.sh           # el servidor y sus contenedores pasan a usar AdGuard
```

Qué hace `host/06-dns.sh`:

- **Servidor**: envía a AdGuard solo las consultas de `*.int.tudominio.com`. El resto sigue yendo al DNS de tu red, así que si AdGuard se cae el servidor conserva internet.
- **Contenedores**: añade AdGuard como DNS en `/etc/docker/daemon.json`, con `1.1.1.1` de respaldo. Los contenedores lo toman al crearse; los que ya existían hay que recrearlos (`./mercury compose <stack> up -d --force-recreate`).

**Verificación.**

```bash
./mercury check-dns
```

```
ok     AdGuard: 192.168.1.50
ok     Servidor: 192.168.1.50
ok     Contenedores: 192.168.1.50
FALLO  HTTPS: ...            <- normal por ahora: se arregla en los pasos 2 a 4
```

### Paso 2. Nginx Proxy Manager

```bash
cp stacks/core/edge/.env.example stacks/core/edge/.env
./mercury up edge
```

Abre `http://IP_DEL_SERVIDOR:81` y crea el usuario administrador.

### Paso 3. Certificado wildcard

El certificado se valida creando un registro temporal en tu zona pública, por eso se necesita un token de Cloudflare aunque los nombres internos no estén publicados.

1. En Cloudflare: **My Profile > API Tokens > Create Token**, plantilla *Edit zone DNS*, limitada a tu zona. Copia el token.
2. En NPM: **SSL Certificates > Add SSL Certificate > Let's Encrypt**.
   - Domain Names: `*.int.tudominio.com`
   - Activa *Use a DNS Challenge*, proveedor **Cloudflare**, y sustituye el valor de `dns_cloudflare_api_token` por tu token.
3. Guarda. Tarda alrededor de un minuto y no requiere abrir ningún puerto.

### Paso 4. Proxy Hosts

Crea un *Proxy Host* por herramienta a medida que las levantes. En todos: esquema `http`, pestaña **SSL** con el certificado wildcard, *Force SSL* y *HTTP/2 Support*.

| Dominio | Destino | Notas |
|---|---|---|
| `adguard.int.<dominio>` | `adguard` : `80` | Panel de AdGuard |
| `registry.int.<dominio>` | `registry-ui` : `80` | Ver fase 2: ubicación `/v2/` |
| `jenkins.int.<dominio>` | `jenkins` : `8080` | Activar *Websockets Support* |
| `sonar.int.<dominio>` | `sonarqube` : `9000` | |
| `grafana.int.<dominio>` | `grafana` : `3000` | Activar *Websockets Support* |
| `portainer.int.<dominio>` | `portainer` : `9000` | Activar *Websockets Support* |
| `<app>-dev.int.<dominio>` | `<app>-dev` : `8080` | Una por app en dev |
| `<app>.int.<dominio>` | `<app>-prod` : `8080` | Una por app en prod (acceso LAN) |

El certificado `*.int.<dominio>` cubre un solo nivel: por eso dev usa `<app>-dev.int...` y no `<app>.dev.int...`.

Si NPM muestra el destino como *Offline* es porque ese contenedor aún no existe; pasará a *Online* cuando levantes su stack.

### Resolver los nombres desde la LAN

El servidor y sus contenedores ya consultan a AdGuard. Los equipos de la LAN no necesitan configurar nada: resuelven `*.int.tudominio.com` con su DNS de siempre (router o proveedor) gracias a un registro público en Cloudflare.

En Cloudflare > DNS > Records:

| Tipo | Nombre | Contenido | Proxy |
|---|---|---|---|
| `A` | `*.int` | IP LAN del servidor | *DNS only* (nube gris) |

Con la nube naranja Cloudflare intentaría hacer de proxy hacia una IP privada y no funcionaría. Lo que implica este registro:

- **Cualquier equipo de la LAN funciona sin tocar su DNS**, y el servidor apagado no deja la red sin navegación.
- **La IP privada del servidor queda publicada.** No da acceso desde internet (no es enrutable), pero revela el direccionamiento de la red.
- **Fuera de casa los nombres resuelven a una IP que no responde.** Es el comportamiento esperado: las herramientas solo se ven en la LAN.
- **Si cambia `LAN_IP`** hay que cambiar este registro además del `.env` raíz y la reescritura de AdGuard.
- Algunos routers con protección contra *DNS rebinding* descartan respuestas públicas que apuntan a IP privadas. Si un equipo no resuelve los nombres y `nslookup jenkins.int.tudominio.com 1.1.1.1` sí da la IP, es eso: desactiva esa protección para el dominio o pasa ese equipo a AdGuard (paso 1 de abajo).

El certificado no depende de este registro: el desafío DNS-01 solo crea un registro TXT temporal.

#### Plan sin el registro público

Si prefieres no publicar la IP privada, los equipos de la LAN tienen que consultar a AdGuard:

1. **Primero solo tu PC.** En Windows: Configuración > Red e Internet > tu adaptador > *Asignación de servidor DNS* > Manual > IPv4, DNS preferido = IP LAN del servidor. Vacía la caché con `ipconfig /flushdns` y comprueba con `nslookup jenkins.int.tudominio.com`: el servidor que responde debe ser la IP LAN del servidor.
2. **Después toda la red.** En el router, en la configuración de DHCP, pon la IP LAN del servidor como servidor DNS. Los equipos lo toman al renovar la conexión.
3. **Borra el registro `*.int`** en Cloudflare > DNS > Records cuando `./mercury check-dns` dé los cuatro puntos en `ok` y los equipos resuelvan a través de AdGuard. Comprueba que ya no existe con `nslookup prueba.int.tudominio.com 1.1.1.1`, que debe responder que no hay registro.

Antes del paso 2 ten en cuenta:

- Si el servidor se apaga, toda la red se queda sin DNS (sin navegación) hasta que vuelva o cambies el DNS del router.
- Poner un DNS secundario público en el router evita ese corte, pero los equipos lo usarán a ratos y entonces los nombres internos fallarán de forma intermitente y la publicidad dejará de bloquearse. Es preferible un solo DNS y tener a mano cómo revertirlo.

Para volver atrás, crea de nuevo el registro de la tabla anterior y devuelve el DNS del router y de los adaptadores a automático.

AdGuard arranca sin listas de bloqueo. Para filtrar publicidad en los equipos que lo usen: panel > *Filtros > Listas de bloqueo DNS > Añadir lista de bloqueo* y elige de la lista predefinida.

### Si el nombre no resuelve

| Resultado de `check-dns` | Causa | Solución |
|---|---|---|
| `aviso AdGuard no está en marcha` | El stack `dns` está parado | `./mercury up dns` y `./mercury logs dns` |
| `FALLO AdGuard: responde ...` | Falta la reescritura, o se cambió desde el panel | Panel > *Filtros > Reescrituras DNS*: `*.int.<dominio>` → IP LAN |
| `FALLO Servidor` | El servidor no consulta a AdGuard | `sudo bash host/06-dns.sh`; revisa con `resolvectl status` |
| `FALLO Contenedores` | Falta `dns` en `daemon.json` | `sudo bash host/06-dns.sh` |
| `FALLO HTTPS` | Falta el Proxy Host o su certificado | Pasos 3 y 4 |

Si el contenedor de AdGuard no arranca porque el puerto 53 está ocupado, comprueba quién lo usa con `sudo ss -lntup | grep ':53 '`. El resolver de Ubuntu escucha en `127.0.0.53` y no interfiere; un conflicto real sería otro servidor DNS instalado en el host.

### Túnel de Cloudflare

Solo hace falta para publicar apps en internet; puedes dejarlo para después.

1. Cloudflare Zero Trust > Networks > Tunnels > *Create a tunnel* (tipo cloudflared). Copia el token.
2. En `stacks/core/edge/.env` (no en `.env.example`): pega `TUNNEL_TOKEN` y pon `COMPOSE_PROFILES=tunnel,test`.
3. `./mercury up edge`
4. En el túnel, añade un *Public Hostname*: `whoami.tudominio.com` → servicio `http://whoami-prod:8080`.

**Verificación.** `https://whoami.tudominio.com` responde desde el móvil con datos (sin wifi). Después quita `test` de `COMPOSE_PROFILES`, ejecuta `./mercury compose edge --profile test rm -s -f whoami` y borra ese hostname. (`down` sin nombre de servicio eliminaría también `npm` y `cloudflared`.)

Para publicar una app real: *Public Hostname* `app.tudominio.com` → `http://<app>-prod:8080`. El túnel también ve dev, el ambiente donde usuarios de prueba buscan bugs antes de prod: `app-dev.tudominio.com` → `http://<app>-dev:8080`. Apunta directo a la app y solo alcanza contenedores de `net-apps-dev` y `net-apps-prod`; aunque añadas por error un hostname hacia `jenkins:8080`, no resolverá.

## Fase 2. Registry

El orden importa: `docker login` es el último paso, porque necesita el registry en marcha y su Proxy Host creado.

1. Crea los usuarios y levanta el stack:

   ```bash
   cp stacks/devops/registry/.env.example stacks/devops/registry/.env
   ./mercury registry-user jenkins      # usuario para Jenkins (pide contraseña)
   ./mercury registry-user tu-usuario   # tu usuario personal
   ./mercury up registry
   ```

2. En NPM, crea el Proxy Host `registry.int.<dominio>` → `http` `registry-ui` : `80`, con el certificado wildcard, y además:

   - Pestaña **Custom locations**: ubicación `/v2/` → `http` `registry` puerto `5000`.
   - Pestaña **Advanced**: `client_max_body_size 0;` (las capas de imagen superan el límite por defecto).

3. Comprueba el camino completo antes de iniciar sesión:

   ```bash
   ./mercury check-dns                  # todos los puntos en "ok"
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
cp stacks/devops/jenkins/.env.example stacks/devops/jenkins/.env
nano stacks/devops/jenkins/.env      # admin y usuario del registry
cp stacks/devops/jenkins/credentials.env.example stacks/devops/jenkins/credentials.env
chmod 600 stacks/devops/jenkins/credentials.env
nano stacks/devops/jenkins/credentials.env   # usuario y token de cada cuenta de git
./mercury agents base dotnet maven node python   # imagen base y la versión por defecto de cada lenguaje (tarda)
./mercury up jenkins
```

Jenkins arranca ya configurado desde `stacks/devops/jenkins/casc/`: usuario administrador, la nube Docker con una plantilla de agente por lenguaje y versión, las carpetas por tecnología y el job `manual-release` (`jenkins.yaml`), y las credenciales (`credentials.yaml`). No hay asistente inicial. Si más adelante editas solo esos YAML, aplícalos con `./mercury restart jenkins`. Para usar más de una cuenta de git, mira [Credenciales de git](03-despliegues.md#credenciales-de-git).

**Verificación.** Crea un job *Pipeline* con este script y ejecútalo mientras miras `watch docker ps` en el servidor: aparece un contenedor de agente y desaparece al terminar.

```groovy
pipeline {
  agent { label 'dotnet' }
  stages { stage('Hola') { steps { sh 'dotnet --version && docker version' } } }
}
```

Solo hace falta publicar los agentes que vayas a usar: el resto de versiones del catálogo (`./mercury agents list`) se construyen cuando llegue un proyecto que las necesite, con `./mercury agents <agente>:<versión>`.

Si el agente no llega a conectar, revisa `./mercury logs jenkins` y `./mercury logs jenkins socket-proxy`. Causas habituales: la imagen del agente no está en el registry (`./mercury agents list`) o las credenciales `REGISTRY_USER`/`REGISTRY_PASSWORD` no coinciden con las de `./mercury registry-user`.

## Fase 4. SonarQube

```bash
cp stacks/devops/sonarqube/.env.example stacks/devops/sonarqube/.env
./mercury up sonarqube               # tarda 2-3 minutos en estar listo
```

1. Entra en `https://sonar.int.<dominio>` con `admin` / `admin` y cambia la contraseña.
2. **Mi cuenta > Seguridad**: genera un token de tipo *Global Analysis Token*. Ponlo en `stacks/devops/jenkins/.env` como `SONAR_TOKEN` y ejecuta `./mercury up jenkins`.
3. **Administration > Configuration > Webhooks**: crea uno con URL `http://jenkins:8080/sonarqube-webhook/`. Es lo que avisa a Jenkins del resultado del *quality gate*.

**Verificación.** El primer pipeline de la fase siguiente crea el proyecto en SonarQube y la etapa *Quality gate* termina en verde.

## Fase 5. Canal manual

```bash
cp stacks/storage/files/.env.example stacks/storage/files/.env
./mercury up files
```

- **Samba**: en el Explorador de Windows, `\\IP_DEL_SERVIDOR\inbox` con el usuario y contraseña de `stacks/storage/files/.env`.
- **SFTP**: WinSCP o FileZilla a `IP_DEL_SERVIDOR`, puerto 22, usuario `deployer`. Entra directamente en `/inbox`.

Ambos escriben en la misma carpeta (`INBOX_DIR`) con el mismo usuario, así que puedes alternarlos.

## Fase 6. Monitoring

Tres stacks que se pueden levantar por separado o juntos con el nombre del grupo:

```bash
for s in metrics logs grafana; do cp stacks/monitoring/$s/.env.example stacks/monitoring/$s/.env; done
nano stacks/monitoring/grafana/.env                      # contraseña de Grafana
bash stacks/monitoring/grafana/fetch-dashboards.sh       # dashboards de la comunidad
./mercury up monitoring
```

| Stack | Servicios | Si no lo levantas |
|---|---|---|
| `metrics` | Prometheus, node-exporter, cAdvisor | No hay métricas ni alertas |
| `logs` | Loki, Alloy | Los logs siguen en `docker logs`, sin búsqueda centralizada |
| `grafana` | Grafana | No hay paneles; Prometheus y Loki siguen recogiendo datos |

**Verificación.**

- En Grafana (`https://grafana.int.<dominio>`), ☰ > Dashboards > carpeta *Mercury* (la página de inicio no la muestra): *Mercury - Resumen*, *Mercury - Host*, *Mercury - CI/CD* y *Mercury - Apps* tienen datos. Cómo leerlos: [monitorizacion.md](../monitorizacion.md).
- *Explore > Loki*: la consulta `{stack="jenkins"}` devuelve los logs de Jenkins.
- Prometheus no se publica. Para ver sus *targets*: `docker exec prometheus wget -qO- localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'`. Todos deben estar `up`.

## Fase 7. Backups, limpieza y Portainer

```bash
sudo bash host/05-backup.sh          # repositorio restic en el HDD + timer diario
./mercury backup                     # primera copia
sudo bash host/07-cleanup.sh         # limpieza semanal de disco (./mercury prune)

cp stacks/core/management/.env.example stacks/core/management/.env
./mercury up management              # opcional
```

Portainer exige crear el administrador en los primeros minutos tras arrancar; si se pasa el plazo, `./mercury restart management`.

## Fase 8. Bases de datos de las apps

Solo hace falta cuando una app necesite base de datos. Si el servidor se instaló antes de existir esta fase, aplica primero lo que falta en el host (los scripts solo crean lo que no existe):

```bash
sudo bash host/04-networks.sh        # redes net-db-dev y net-db-prod
sudo bash host/02-disks.sh           # DATA_DIR/db/<env>/<motor>
sudo ufw allow from <LAN_SUBNET> to any port 1433,3306,5432 proto tcp   # o repite host/01-base.sh
./mercury agents                     # el compose de despliegue de los agentes incluye la red nueva
```

Las apps desplegadas antes de este paso entran a `net-db-<env>` al redesplegarlas.

```bash
cp stacks/data/db-dev/.env.example stacks/data/db-dev/.env
cp stacks/data/db-prod/.env.example stacks/data/db-prod/.env
nano stacks/data/db-dev/.env         # claves de administrador; distintas en prod
nano stacks/data/db-prod/.env
./mercury config db-dev              # ningún motor aparece si COMPOSE_PROFILES está vacío
./mercury db up dev postgres
./mercury db ps
```

**Verificación.**

- `./mercury db create dev postgres prueba` imprime la conexión y la añade a `/srv/mercury/apps/dev/prueba.env` (`APPS_DIR`).
- Desde Windows, DBeaver conecta a `db-dev.int.<dominio>:5432` con el usuario `prueba`.
- `Test-NetConnection <IP_DEL_SERVIDOR> -Port 5432` funciona con `pg-dev` encendida y falla tras `./mercury db down dev postgres`. Prod nunca responde desde la LAN.
- Limpieza: `./mercury db drop dev postgres prueba` y `sudo rm /srv/mercury/apps/dev/prueba.env`.

El uso diario (crear bases, elegir motores por defecto, conectarse) está en [03-despliegues.md](03-despliegues.md#base-de-datos-de-una-app).
