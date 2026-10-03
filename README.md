# Mercury Server

Infraestructura como código de un servidor doméstico de CI/CD sobre Docker: Jenkins con agentes efímeros, SonarQube, escáneres de seguridad, registry privado, un canal de despliegue manual, DNS interno y observabilidad. Pensado para una máquina modesta (i7 de 3ª generación, 12 GB de RAM, SSD + HDD) con Ubuntu Server.

## Mapa

```
                      tudominio.com
              ┌────────────┴────────────┐
           Público                   Interno
        Cloudflare DNS            AdGuard Home (DNS de la LAN)
              │                         │
      app.tudominio.com        *.int.tudominio.com → IP LAN
              │                         │
       Cloudflare Tunnel       Nginx Proxy Manager (:443)
              │                         │
              │            ┌── net-tools ──── jenkins, sonarqube, registry, grafana, adguard, portainer
              │            ├── net-apps-dev ─ apps dev
              └────────────┴── net-apps-prod  apps prod  ◄── único destino del túnel
```

- Las herramientas solo se ven en la LAN, con HTTPS real (`*.int.<dominio>`). AdGuard Home resuelve esos nombres; no existen en el DNS público.
- Lo público sale únicamente por el túnel de Cloudflare, que apunta directo a la app y solo alcanza la red de apps de producción.
- Solo Nginx Proxy Manager, AdGuard (DNS) y Samba publican puertos, ligados a la LAN. El resto se alcanza por nombre de contenedor dentro de las redes de Docker.

## Estructura

| Ruta | Contenido |
|---|---|
| `host/` | Scripts numerados que preparan Ubuntu: firewall, SSH, discos, Docker, redes, backups, DNS |
| `stacks/<grupo>/<stack>/` | Un directorio por stack, cada uno con su `compose.yaml` y su `.env.example` |
| `apps/_templates/` | Por runtime: `Dockerfile` de empaquetado, `Jenkinsfile` de ejemplo y compose de modo rápido |
| `pipelines/` | `mercury-ci` (pasos compartidos de los pipelines) y el job del canal manual |
| `mercury` | Script para operar los stacks: `./mercury help`, `./mercury list` |
| `docs/` | Guías paso a paso |

| Grupo | Stack | Servicios | RAM límite |
|---|---|---|---|
| `core` | `dns` | AdGuard Home | 0,3 GB |
| | `edge` | Nginx Proxy Manager, cloudflared | 0,5 GB |
| | `management` | Portainer (opcional) | 0,3 GB |
| `devops` | `registry` | Registry + interfaz web | 0,3 GB |
| | `jenkins` | Controller + socket-proxy (los agentes se crean por build) | 1,6 GB |
| | `sonarqube` | SonarQube Community + PostgreSQL | 3,5 GB |
| `monitoring` | `metrics` | Prometheus, node-exporter, cAdvisor | 0,8 GB |
| | `logs` | Loki, Alloy | 0,8 GB |
| | `grafana` | Grafana | 0,4 GB |
| `storage` | `files` | Samba (canal manual) | 0,1 GB |

Los límites suman unos 8,5 GB; el uso real en reposo es menor. Queda margen para dos agentes de build (hasta 2 GB cada uno) y las apps desplegadas.

Los comandos de `mercury` aceptan un stack, un grupo o `all`: `./mercury up jenkins`, `./mercury up monitoring`, `./mercury ps all`.

Los agentes de build tienen un catálogo de versiones (.NET 8/9/10, Java 8 a 25, Node 20/22/24, Python 3.11 a 3.13) y se publican bajo demanda: `./mercury agents list`, `./mercury agents dotnet:8.0`. En el Jenkinsfile se elige con `agent { label 'dotnet-8.0' }`.

## Puesta en marcha

1. [docs/01-host.md](docs/01-host.md): instalar Ubuntu Server y preparar el host.
2. [docs/02-puesta-en-marcha.md](docs/02-puesta-en-marcha.md): levantar los stacks uno a uno, verificando cada fase.
3. [docs/03-despliegues.md](docs/03-despliegues.md): publicar apps por el canal CI y por el canal manual.
4. [docs/04-operacion-y-futuro.md](docs/04-operacion-y-futuro.md): backups, actualizaciones, cómo añadir stacks (NAS, IoT) y el camino a Kubernetes.

## Convenciones

- **Un stack, un compose.** Cada stack se levanta y se detiene por separado. Las redes compartidas (`net-tools`, `net-apps-dev`, `net-apps-prod`, `net-obs`) se crean una vez y se declaran `external`.
- **Configuración en git, secretos y datos fuera.** Los `.env` no se versionan y los valores reales nunca van en un `.env.example`. Los datos viven en `/srv/mercury` (SSD) y `/mnt/hdd/mercury` (HDD).
- **Versiones fijadas.** Las imágenes de terceros llevan versión exacta en el `.env` de su stack; actualizar es cambiar ese número.
- **Toda app escucha en 8080** y su contenedor se llama `<app>-<ambiente>`. En Nginx Proxy Manager el destino siempre es `http://<app>-<dev|prod>:8080`.
- **Todo servicio tiene límite de memoria.** Con 12 GB, un contenedor sin límite puede tumbar el servidor.
