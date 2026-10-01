# 4. Operación y crecimiento

## Rutina

| Tarea | Cómo |
|---|---|
| Ver el estado general | Grafana > *Mercury - Resumen*, o `docker stats --no-stream` |
| Liberar RAM | `./mercury down sonarqube` cuando no vayas a analizar código (3,5 GB) |
| Actualizar una imagen | Cambia la versión en `stacks/<stack>/.env`, luego `./mercury pull <stack> && ./mercury up <stack>` |
| Actualizar Jenkins o sus plugins | Cambia `JENKINS_VERSION` o `plugins.txt`, luego `./mercury build jenkins && ./mercury up jenkins` |
| Cambiar pasos de pipeline o plantillas | Edita `pipelines/lib/mercury-ci` o `apps/_templates/`, luego `./mercury agents` |
| Limpiar imágenes viejas del host | `docker image prune -a --filter "until=168h"` |
| Liberar espacio en el registry | Borra etiquetas desde la interfaz web y ejecuta `./mercury registry-gc` |
| Backup manual | `./mercury backup` |

Actualiza de una en una y lee las notas de versión de SonarQube y Jenkins antes de saltar de versión mayor: SonarQube migra su base de datos y no permite volver atrás sin restaurar un backup.

## Backups

`host/backup.sh` copia cada noche a `/mnt/hdd/mercury/backups/restic`: los datos de `/srv/mercury`, un volcado de la base de datos de SonarQube y los archivos `.env`.

```bash
sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password snapshots
sudo restic -r /mnt/hdd/mercury/backups/restic --password-file /root/.mercury-restic-password restore latest --target /tmp/restore
```

El HDD está en la misma máquina: protege de un borrado accidental o de la muerte del SSD, no de un robo o una subida de tensión. Cuando puedas, añade un segundo destino remoto (restic admite Backblaze B2, S3 o un servidor SFTP) y guarda la contraseña del repositorio fuera del servidor.

No se copian las imágenes del registry, las métricas ni los logs: se pueden regenerar.

## Alertas

Las reglas de `stacks/observability/prometheus/rules/mercury.yml` ya se evalúan y se ven en Grafana (*Alerting > Alert rules*). Para recibir avisos, la vía con menos piezas es crear un *Contact point* en Grafana (Telegram, correo, Discord) y una política de notificación. Alertmanager como contenedor aparte solo compensa cuando quieras gestionar las rutas de aviso como código; es la pieza que usa el stack equivalente en Kubernetes.

## Acceso remoto por VPN

Cuando lo necesites, instala Tailscale o WireGuard **en el host**, no en un contenedor. Con Tailscale, anuncia la subred de la LAN (`--advertise-routes`) y los nombres `*.int.<dominio>` funcionarán igual desde fuera, porque resuelven a la IP privada del servidor. No hay que cambiar nada en los stacks.

## Añadir stacks nuevos

Cada servicio nuevo sigue la misma receta:

1. Carpeta `stacks/<nombre>/` con `compose.yaml` y `.env.example`.
2. `name:` explícito, versión de imagen en variable, `mem_limit`, `restart: unless-stopped`.
3. Sin `ports:` salvo que el protocolo no sea HTTP. Para interfaces web, conecta el servicio a `net-tools` y crea su *Proxy Host* en NPM.
4. Red privada `internal: true` para sus bases de datos.
5. Datos en `${DATA_DIR}/<nombre>` (SSD) o `${HDD_DIR}/<nombre>` (HDD); añade el directorio a `host/02-disks.sh`.
6. Añade el nombre a la lista `STACKS` del script `mercury`.

### Mini NAS

- **Compartir archivos**: un segundo servicio Samba en un stack `nas/` con una carpeta de `/mnt/hdd/mercury/nas`. El stack `files` muestra cómo.
- **Nube personal** (Nextcloud, Immich): cada uno en su stack, con su base de datos en red `internal`.
- Un único HDD no es almacenamiento seguro para datos irreemplazables. Antes de guardar fotos o documentos, añade un segundo disco o un backup remoto.

### IoT

Stack `iot/` con Mosquitto (MQTT), Home Assistant y, si quieres, Node-RED:

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

1. Detener `sonarqube` y `observability` mientras practicas con k3s en el mismo servidor.
2. Practicar primero en tu PC con `kind` o `k3d` (Kubernetes dentro de Docker) y migrar el servidor cuando te sientas cómodo, empezando por las apps y dejando Jenkins para el final.

El orden de aprendizaje que mejor aprovecha lo que ya sabes: Pods y Deployments → Services e Ingress → ConfigMaps y Secrets → volúmenes → Helm → despliegue continuo con Argo CD.
