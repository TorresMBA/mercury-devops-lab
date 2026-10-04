# Documentación de Mercury Server

La documentación está en tres carpetas, según lo que se quiera hacer:

| Carpeta | Para qué | Responde a |
|---|---|---|
| [`instalacion/`](instalacion/) | Levantar y operar el servidor | ¿Qué ejecuto y en qué orden? |
| [`arquitectura/`](arquitectura/) | Entender y mantener la plataforma | ¿Cómo está construido y por qué? |
| [`scripts/`](scripts/) | Modificar `mercury` y `mercury-ci` | ¿Cómo está escrito el script y cómo le añado algo? |

**¿Buscas un comando?** [comandos.md](comandos.md) lista todos los de `mercury`, `mercury-ci` y `host/`, y los servicios programados de backup y limpieza, con una línea por cada uno.

## `instalacion/`: levantar y operar

| Documento | Contenido |
|---|---|
| [01-host.md](instalacion/01-host.md) | Instalar Ubuntu Server, preparar discos, Docker, firewall y redes |
| [02-puesta-en-marcha.md](instalacion/02-puesta-en-marcha.md) | Levantar los stacks fase a fase, verificando cada una |
| [03-despliegues.md](instalacion/03-despliegues.md) | Publicar apps por el canal CI y por el canal manual |
| [04-operacion-y-futuro.md](instalacion/04-operacion-y-futuro.md) | Rutina, migraciones, backups, stacks futuros y camino a Kubernetes |

## `arquitectura/`: entender y mantener

| Documento | Responde a |
|---|---|
| [05-requisitos-y-conceptos.md](arquitectura/05-requisitos-y-conceptos.md) | ¿Qué necesito saber y tener? ¿Qué herramientas se usan y qué significa cada término? |
| [06-arquitectura.md](arquitectura/06-arquitectura.md) | ¿Qué piezas hay, cómo se organizan el repo, la configuración, los datos y la memoria? |
| [07-redes-y-dns.md](arquitectura/07-redes-y-dns.md) | ¿Quién puede hablar con quién? ¿Cómo se resuelve un nombre y por dónde entra el tráfico? |
| [08-jenkins-y-agentes.md](arquitectura/08-jenkins-y-agentes.md) | ¿Cómo arranca Jenkins, cómo nace y muere un agente, cómo se versionan sus imágenes? |
| [09-pipelines-y-despliegue.md](arquitectura/09-pipelines-y-despliegue.md) | ¿Qué hace cada etapa, cómo se empaqueta una app y cómo llega a dev y a prod? |
| [10-registry-e-imagenes.md](arquitectura/10-registry-e-imagenes.md) | ¿Qué imágenes existen, cómo se nombran, quién las publica y quién las descarga? |
| [11-observabilidad-y-backups.md](arquitectura/11-observabilidad-y-backups.md) | ¿De dónde salen métricas, logs y alertas? ¿Qué se copia y qué no? |
| [12-referencia.md](arquitectura/12-referencia.md) | Comandos de `mercury` y `mercury-ci`, todas las variables y todos los scripts de `host/` |
| [13-mantenimiento-y-extension.md](arquitectura/13-mantenimiento-y-extension.md) | ¿Cómo valido un cambio, qué reconstruyo después, cómo añado un stack, un agente o un runtime? |

## `scripts/`: modificar los scripts

| Documento | Responde a |
|---|---|
| [01-como-se-aplican-los-cambios.md](scripts/01-como-se-aplican-los-cambios.md) | ¿Por qué edité un script y el pipeline no cambió? ¿Dónde corre cada script y qué hay que reconstruir? |
| [02-mercury.md](scripts/02-mercury.md) | ¿Cómo está escrito `mercury`, qué hace cada función y cómo añado un comando? |
| [03-mercury-ci.md](scripts/03-mercury-ci.md) | ¿Cómo está escrito `mercury-ci`, cómo añado un paso o un escáner sin romper los pipelines existentes? |

**Antes de tocar `mercury-ci` o `apps/_templates/`, lee [scripts/01](scripts/01-como-se-aplican-los-cambios.md).** Esos archivos se ejecutan desde una copia dentro de la imagen de los agentes: un cambio no tiene efecto hasta ejecutar `./mercury agents`.

## Por dónde empezar

| Si vas a... | Lee, en este orden |
|---|---|
| Mantener el proyecto por primera vez | arquitectura 05 → 06 → 07 → 08 → 09 → 13 |
| Instalar el servidor desde cero | arquitectura 05 (requisitos) → instalacion 01 → 02 → 03 |
| Publicar una app sin tocar la infraestructura | instalacion 03, y arquitectura 09 si algo falla |
| Modificar `mercury` o `mercury-ci` | scripts 01 → 02 o 03 |
| Añadir una versión de lenguaje o un runtime nuevo | arquitectura 08 → 09 → 13, y scripts 03 |
| Añadir un servicio (stack) nuevo | arquitectura 06 → 07 → 13 |
| Diagnosticar un fallo | arquitectura 13 (tabla de síntomas) → el documento del área |

## Convenciones de esta documentación

- `<dominio>` es `BASE_DOMAIN` del `.env` raíz; los nombres internos cuelgan de `int.<dominio>` (`INT_DOMAIN`).
- `<app>` es el nombre de una aplicación desplegada; `<env>` es `dev` o `prod`.
- Las rutas son relativas a la raíz del repo, que en el servidor está en `/opt/mercury`.
- Los diagramas están escritos en [Mermaid](https://mermaid.js.org/): GitHub y la mayoría de editores con vista previa de Markdown los dibujan sin instalar nada.
- Las versiones de imagen citadas son las de los `.env.example` en el momento de escribir. La fuente de verdad es siempre el `.env.example` de cada stack.
