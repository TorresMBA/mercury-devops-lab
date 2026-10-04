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

| Ruta                      | Contenido                                                                                   |
| ------------------------- | ------------------------------------------------------------------------------------------- |
| `host/`                   | Scripts numerados que preparan Ubuntu: firewall, SSH, discos, Docker, redes, backups, DNS   |
| `stacks/<grupo>/<stack>/` | Un directorio por stack, cada uno con su `compose.yaml` y su `.env.example`                 |
| `apps/_templates/`        | Por runtime: `Dockerfile` de empaquetado, `Jenkinsfile` de ejemplo y compose de modo rápido |
| `pipelines/`              | `mercury-ci` (pasos compartidos de los pipelines) y el job del canal manual                 |
| `mercury`                 | Script para operar los stacks: `./mercury help`, `./mercury list`                           |
| `docs/`                   | `instalacion/` (guías), `arquitectura/` (cómo está construido) y `scripts/` (interior de los bash) |

| Grupo        | Stack        | Servicios                                                  | RAM límite |
| ------------ | ------------ | ---------------------------------------------------------- | ---------- |
| `core`       | `dns`        | AdGuard Home                                               | 0,3 GB     |
|              | `edge`       | Nginx Proxy Manager, cloudflared                           | 0,5 GB     |
|              | `management` | Portainer (opcional)                                       | 0,3 GB     |
| `devops`     | `registry`   | Registry + interfaz web                                    | 0,3 GB     |
|              | `jenkins`    | Controller + socket-proxy (los agentes se crean por build) | 1,6 GB     |
|              | `sonarqube`  | SonarQube Community + PostgreSQL                           | 3,5 GB     |
| `monitoring` | `metrics`    | Prometheus, node-exporter, cAdvisor                        | 0,8 GB     |
|              | `logs`       | Loki, Alloy                                                | 0,8 GB     |
|              | `grafana`    | Grafana                                                    | 0,4 GB     |
| `storage`    | `files`      | Samba (canal manual)                                       | 0,1 GB     |

Los límites suman unos 8,5 GB; el uso real en reposo es menor. Queda margen para dos agentes de build (hasta 2 GB cada uno) y las apps desplegadas.

Los comandos de `mercury` aceptan un stack, un grupo o `all`: `./mercury up jenkins`, `./mercury up monitoring`, `./mercury ps all`.

Los agentes de build tienen un catálogo de versiones (.NET 8/9/10, Java 8 a 25, Node 20/22/24, Python 3.11 a 3.13) y se publican bajo demanda: `./mercury agents list`, `./mercury agents dotnet:8.0`. En el Jenkinsfile se elige con `agent { label 'dotnet-8.0' }`.

## Documentación

Está en `docs/`, en tres carpetas. El índice completo, con rutas de lectura según la tarea, es [docs/README.md](docs/README.md). El listado de todos los comandos y de los servicios programados (backup y limpieza) está en [docs/comandos.md](docs/comandos.md).

### Puesta en marcha: `docs/instalacion/`

1. [01-host.md](docs/instalacion/01-host.md): instalar Ubuntu Server y preparar el host.
2. [02-puesta-en-marcha.md](docs/instalacion/02-puesta-en-marcha.md): levantar los stacks uno a uno, verificando cada fase.
3. [03-despliegues.md](docs/instalacion/03-despliegues.md): publicar apps por el canal CI y por el canal manual.
4. [04-operacion-y-futuro.md](docs/instalacion/04-operacion-y-futuro.md): backups, actualizaciones, cómo añadir stacks (NAS, IoT) y el camino a Kubernetes.

### Cómo está construido: `docs/arquitectura/`

| Documento | Contenido |
| --- | --- |
| [05-requisitos-y-conceptos](docs/arquitectura/05-requisitos-y-conceptos.md) | Conocimientos mínimos, herramientas y versiones, glosario |
| [06-arquitectura](docs/arquitectura/06-arquitectura.md) | Componentes, estructura del repo, configuración, datos, memoria y seguridad |
| [07-redes-y-dns](docs/arquitectura/07-redes-y-dns.md) | Redes de Docker, puertos, DNS interno, entrada de tráfico y certificado |
| [08-jenkins-y-agentes](docs/arquitectura/08-jenkins-y-agentes.md) | Controller, configuración como código, ciclo de vida y versionado de agentes |
| [09-pipelines-y-despliegue](docs/arquitectura/09-pipelines-y-despliegue.md) | `mercury-ci`, etapas, empaquetado, despliegue, canal manual y modo rápido |
| [10-registry-e-imagenes](docs/arquitectura/10-registry-e-imagenes.md) | Nombres y etiquetas de imagen, acceso, autenticación y limpieza |
| [11-observabilidad-y-backups](docs/arquitectura/11-observabilidad-y-backups.md) | Métricas, logs, paneles, alertas y copias de seguridad |
| [12-referencia](docs/arquitectura/12-referencia.md) | Comandos, variables y scripts |
| [13-mantenimiento-y-extension](docs/arquitectura/13-mantenimiento-y-extension.md) | Validar cambios, qué reconstruir, recetas para ampliar y diagnóstico |

### Modificar los scripts: `docs/scripts/`

| Documento | Contenido |
| --- | --- |
| [01-como-se-aplican-los-cambios](docs/scripts/01-como-se-aplican-los-cambios.md) | Dónde corre cada script y qué hay que reconstruir tras editarlo |
| [02-mercury](docs/scripts/02-mercury.md) | Interior de `mercury`: estructura, funciones y cómo añadir un comando |
| [03-mercury-ci](docs/scripts/03-mercury-ci.md) | Interior de `mercury-ci`: estructura, funciones y cómo añadir un paso o un escáner |

> `pipelines/lib/mercury-ci` y `apps/_templates/` se ejecutan desde una copia dentro de la imagen de los agentes. Tras editarlos, el cambio no llega a los pipelines hasta ejecutar `./mercury agents`.

## Convenciones

- **Un stack, un compose.** Cada stack se levanta y se detiene por separado. Las redes compartidas (`net-tools`, `net-apps-dev`, `net-apps-prod`, `net-obs`) se crean una vez y se declaran `external`.
- **Configuración en git, secretos y datos fuera.** Los `.env` no se versionan y los valores reales nunca van en un `.env.example`. Los datos viven en `/srv/mercury` (SSD) y `/mnt/hdd/mercury` (HDD).
- **Versiones fijadas.** Las imágenes de terceros llevan versión exacta en el `.env` de su stack; actualizar es cambiar ese número.
- **Toda app escucha en 8080** y su contenedor se llama `<app>-<ambiente>`. En Nginx Proxy Manager el destino siempre es `http://<app>-<dev|prod>:8080`.
- **Todo servicio tiene límite de memoria.** Con 12 GB, un contenedor sin límite puede tumbar el servidor.
