# 3. Desplegar aplicaciones

Hay dos canales y los dos terminan igual: una imagen versionada en el registry y un contenedor `<app>-<ambiente>` en la red `net-apps-<ambiente>`, escuchando en el puerto 8080.

```
Canal CI:     git push → agente efímero → build + test → SonarQube → Semgrep + Trivy ─┐
                                                                                      ├→ imagen en registry → deploy
Canal manual: copiar compilado a inbox/<app> → job manual-release → Trivy ────────────┘
```

Tras el primer despliegue de una app, crea una vez su *Proxy Host* en Nginx Proxy Manager (`<app>-dev.int.<dominio>` → `<app>-dev:8080`). Los despliegues siguientes reutilizan el mismo nombre de contenedor, así que no hay que tocar NPM de nuevo.

## Requisitos de una app

| Runtime | La app debe... |
|---|---|
| .NET | Nada especial: `ASPNETCORE_HTTP_PORTS=8080` la pone a escuchar en 8080 |
| Spring | Nada especial: `SERVER_PORT=8080` |
| Flask | Tener `requirements.txt` y exponer el objeto Flask como `app` en `app.py` (o definir `APP_MODULE`) |
| Node | Escuchar en `process.env.PORT` y tener un script `start` en `package.json` |
| Estático | Tener `index.html` en la raíz de la carpeta |
| SPA (Angular, React, Vue) | Compilar a una carpeta con `index.html`; las rutas internas las resuelve el navegador |

## Canal CI

Los jobs se organizan en carpetas por tecnología y framework. Las carpetas las crea Jenkins al arrancar (están en `stacks/devops/jenkins/casc/jenkins.yaml`); cada job lo creas tú dentro de la suya.

| Carpeta en Jenkins | Agente | Plantilla de Jenkinsfile (en `apps/_templates/`) | Runtime |
|---|---|---|---|
| `dotnet` | `dotnet` | `dotnet/Jenkinsfile` | `dotnet` |
| `java/spring` | `maven` | `spring/Jenkinsfile` | `spring` |
| `java/vanilla` | `maven` | `spring/Jenkinsfile` | `spring` |
| `javascript/node` | `node` | `node/Jenkinsfile` | `node` |
| `javascript/angular` | `node` | `spa/Jenkinsfile.angular` | `spa` |
| `javascript/react` | `node` | `spa/Jenkinsfile.react` | `spa` |
| `javascript/vue` | `node` | `spa/Jenkinsfile.vue` | `spa` |
| `javascript/vanilla` | `base` | `static/Jenkinsfile` | `static` |
| `python/flask` | `python` | `flask/Jenkinsfile` | `flask` |

- **Java sin framework** usa la plantilla de Spring: sirve para cualquier proyecto Maven que genere un único JAR ejecutable (`java -jar`) y escuche en el puerto 8080.
- **Angular, React y Vue** se compilan con el agente `node` y se sirven con nginx (runtime `spa`), que devuelve `index.html` en las rutas internas para que recargar `/clientes/5` no dé 404.
- **.NET Framework (4.x) no está soportado**: solo compila y se ejecuta en Windows, y aquí los agentes y los contenedores son Linux. El .NET moderno sí, en las versiones del catálogo.

### Versiones de los agentes

Cada lenguaje tiene un catálogo de versiones. La etiqueta sin versión (`dotnet`, `maven`...) es la de por defecto; para fijar otra, cambia una línea del Jenkinsfile:

```groovy
agent { label 'dotnet-8.0' }
```

| Agente | Etiquetas | Por defecto | Imagen de la app |
|---|---|---|---|
| `dotnet` | `dotnet-8.0`, `dotnet-9.0`, `dotnet-10.0` | 10.0 | `aspnet:<versión>` |
| `maven` | `maven-8`, `maven-11`, `maven-17`, `maven-21`, `maven-25` | 21 | `eclipse-temurin:<versión>-jre` |
| `node` | `node-20`, `node-22`, `node-24` | 22 | `node:<versión>-alpine` (no aplica a Angular, React y Vue, que se sirven con nginx) |
| `python` | `python-3.11`, `python-3.12`, `python-3.13` | 3.12 | `python:<versión>-slim` |

La imagen de la app sigue al agente: un build en `dotnet-8.0` se empaqueta sobre `aspnet:8.0` sin configurar nada más.

**Estar en el catálogo no significa estar construido.** Solo existen en el registry las versiones que hayas publicado:

```bash
./mercury agents list           # qué hay publicado
./mercury agents dotnet:8.0     # llega un proyecto en .NET 8: se construye y publica solo ese agente
```

Tarda unos minutos la primera vez. Si un Jenkinsfile pide una versión sin publicar, el build se queda esperando agente hasta que la publiques; no hay que reiniciar Jenkins. La espera no es indefinida: cuenta dentro del `timeout` de 45 minutos del stage *CI*.

Con `maven-8` y `maven-11`, el análisis de SonarQube no puede usar el plugin de Maven (exige Java 17 o superior): la plantilla `spring/Jenkinsfile` trae comentada la línea alternativa.

Pasos para una app:

1. Copia la plantilla de su fila a la raíz del repo de la app con el nombre `Jenkinsfile` y ajusta las variables del bloque `environment` (`APP`, y `SOLUTION` y `PROJECT` en .NET o `DIST_DIR` en Angular, React y Vue).
2. En Jenkins, entra en la carpeta de su tecnología y pulsa *Nueva tarea > Pipeline*. Definición *Pipeline script from SCM*, Git, URL del repo, la credencial de la cuenta dueña del repo (por ejemplo `github-mercury`), rama `*/main`.
3. Lanza el build.

La carpeta solo ordena: lo que decide el agente y el empaquetado es el Jenkinsfile. Para añadir una carpeta, agrega su línea al mapa `carpetas` de `casc/jenkins.yaml` y ejecuta `./mercury restart jenkins`; los jobs que ya existen dentro de las carpetas se conservan.

Etapas del pipeline:

| Etapa | Qué hace |
|---|---|
| Build y test | Compila y ejecuta los tests dentro del agente del lenguaje |
| SonarQube | Envía el análisis del código |
| Análisis: Quality gate | Espera el veredicto de SonarQube; si no pasa el *quality gate*, el pipeline se detiene |
| Análisis: Seguridad | A la vez que la anterior: Semgrep (fallos de seguridad en el código) y Trivy (dependencias vulnerables, secretos, configuración). El informe `semgrep.json` queda archivado en el build |
| Imagen | Empaqueta el compilado con el `Dockerfile` del proyecto si lo tiene, o con la plantilla; publica la imagen y la escanea con Trivy |
| Deploy dev | Despliega en dev automáticamente |
| Aprobar prod | Espera una confirmación manual (hasta 24 h), sin ocupar ningún agente. Un push nuevo cancela el build que estaba esperando |
| Deploy prod | Despliega **la misma imagen** que se probó en dev |

Las dependencias (NuGet, Maven, npm, pip) se guardan en una caché compartida entre builds: el primer build de un proyecto las descarga y los siguientes las reutilizan. El stage *CI* se aborta si supera los 45 minutos; para un proyecto que necesite más, cambia ese `timeout` en su Jenkinsfile.

Por defecto los escáneres de seguridad informan pero no rompen el build. Para que los hallazgos de severidad alta o crítica lo detengan, añade al `environment` del Jenkinsfile: `MERCURY_SCAN_STRICT = '1'`.

#### Leer los resultados de seguridad

Las tres herramientas no son redundantes: cada una mira una cosa distinta.

| Herramienta | Qué revisa | Dónde se ve | Se parece a |
|---|---|---|---|
| SonarQube | Calidad del código: errores, duplicación, cobertura y puntos de seguridad a revisar (*hotspots*). En la edición Community no sigue el recorrido de un dato por el código | `https://sonar.int.<dominio>` | — |
| Semgrep | Vulnerabilidades en el código propio (inyección SQL, XSS, rutas manipuladas...), clasificadas por CWE y OWASP | Consola del stage *Seguridad* y `semgrep.json` en los artefactos del build | Checkmarx, Snyk Code |
| Trivy | Dependencias con vulnerabilidades conocidas, secretos, mala configuración y la imagen final | Consola de los stages *Seguridad* e *Imagen* | Snyk Open Source |

En la consola, Semgrep lista cada hallazgo con su archivo, línea y regla, y después aparece la tabla de Trivy. El archivo `semgrep.json` se descarga desde la página del build (*Artefactos*); los campos útiles de cada elemento de `results` son `check_id` (la regla), `path`, `start.line`, `extra.message` y `extra.metadata.cwe`.

**Reproducir en tu máquina un hallazgo de Checkmarx o Snyk.** Semgrep es lo más parecido que hay en la plataforma. Desde la raíz del proyecto, con Docker, el mismo análisis que lanza el pipeline (no probado fuera del pipeline):

```bash
docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep:1.178.0 \
  semgrep scan --config p/default --metrics off .
```

En PowerShell, la misma orden en una línea y con `${PWD}` en lugar de `$PWD`.

Para acercarte al informe de la empresa, cambia `--config p/default` por un conjunto de reglas más cercano a lo que te marcaron: `p/owasp-top-ten`, `p/cwe-top-25` o el del lenguaje (`p/java`, `p/csharp`, `p/javascript`, `p/python`). Se pueden repetir varios `--config`.

Dos límites que conviene tener presentes:

- Las reglas no son las de Checkmarx ni las de Snyk: se reproduce el tipo de fallo (el mismo CWE), no el mismo informe.
- La versión gratuita sigue un dato dentro de un archivo, no de un archivo a otro. Un hallazgo que cruza varias clases puede no aparecer.

**Disparo automático.** Jenkins no es visible desde internet, así que GitHub no puede enviarle webhooks. Lo más simple es que Jenkins consulte el repo: en el job, *Build Triggers > Poll SCM* con `H/5 * * * *` (cada 5 minutos).

### Dockerfile propio

La plantilla de `apps/_templates/<runtime>/Dockerfile` sirve para una app sin dependencias del sistema. Cuando no alcanza, el Dockerfile del proyecto tiene prioridad. `mercury-ci package` busca en este orden y escribe en el log cuál usó:

1. El indicado en `MERCURY_DOCKERFILE` (variable del `environment` del Jenkinsfile; ruta relativa a la raíz del repo).
2. `Dockerfile` dentro de la carpeta que se empaqueta.
3. `Dockerfile` en la raíz del repo de la app.
4. La plantilla del runtime.

Dos formas de usarlo:

**Empaquetado ampliado.** La app necesita paquetes del sistema, fuentes o certificados. Deja un `Dockerfile` en la raíz del repo que parta del compilado; el Jenkinsfile no cambia.

```dockerfile
ARG DOTNET_VERSION=10.0
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends libgdiplus fonts-liberation \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
ENV ASPNETCORE_HTTP_PORTS=8080
USER $APP_UID
ENTRYPOINT ["dotnet", "MiApi.dll"]
```

**Build completo.** En proyectos grandes, el Dockerfile compila dentro (multi-etapa). En la etapa *Imagen* del Jenkinsfile, empaqueta la raíz del repo en lugar del compilado:

```groovy
sh '''
  mercury-ci login
  mercury-ci package dotnet . "$APP" "$TAG"
'''
```

Reglas para un Dockerfile propio:

- Escuchar en el puerto **8080**: es lo que esperan el despliegue, Nginx Proxy Manager y el túnel.
- Terminar con un usuario sin privilegios (`USER`).
- Declarar el `ARG` de versión de su runtime (`DOTNET_VERSION`, `JAVA_VERSION`, `NODE_VERSION`, `PYTHON_VERSION`) si quieres que siga a la versión del agente.
- Un build completo compila en el Docker del servidor, fuera del límite de memoria del agente: vigila la RAM si lanzas dos a la vez.

Para ignorar un `Dockerfile` del repo que sea para otra cosa (desarrollo local), define `MERCURY_DOCKERFILE = 'template'`.

### Builds simultáneos

- Proyectos distintos se construyen en paralelo, hasta `JENKINS_MAX_AGENTS` agentes a la vez (2 por defecto, en `stacks/devops/jenkins/.env`). Cada agente reserva hasta 2 GB y sus escáneres otros 1,5 GB: con 12 GB y SonarQube en marcha, 2 es el máximo prudente. El tercero espera en cola.
- En un mismo job solo corre un build: el nuevo cancela al anterior, también si estaba esperando en *Aprobar prod*.
- `manual-release` admite varias ejecuciones a la vez; solo se serializan los despliegues de la misma app y ambiente.

### Primer pipeline paso a paso (.NET)

Antes de empezar, comprueba que:

- `./mercury agents list` muestra publicada la versión de .NET del proyecto y el job de prueba de la [fase 3](02-puesta-en-marcha.md#fase-3-jenkins) arranca un agente `dotnet`.
- SonarQube está en marcha, con `SONAR_TOKEN` en el `.env` de Jenkins y el webhook creado ([fase 4](02-puesta-en-marcha.md#fase-4-sonarqube)).
- La credencial de git de la cuenta dueña del repo tiene su token en `credentials.env`.
- El `TargetFramework` del proyecto coincide con el agente del Jenkinsfile: `net10.0` con `dotnet` (por defecto), `net8.0` con `dotnet-8.0`. Si no coinciden, la app compila pero falla en los tests y al arrancar porque no está su runtime.

1. **En el repo de la app**, copia `apps/_templates/dotnet/Jenkinsfile` a la raíz y ajusta tres líneas:
   ```groovy
   APP = 'mi-api'                       // será el nombre de la imagen, del contenedor y del proyecto en SonarQube
   SOLUTION = 'MiApi.slnx'              // solución que se compila y se prueba (.slnx o .sln), relativa a la raíz del repo
   PROJECT = 'src/MiApi/MiApi.csproj'   // ruta del proyecto web, relativa a la raíz del repo; debe estar incluido en SOLUTION
   ```
   Súbelo a la rama `main`.
2. **En Jenkins**, entra en la carpeta `dotnet` > *Nueva tarea*. Nombre: el de la app. Tipo: *Pipeline*.
   - *Pipeline > Definition*: *Pipeline script from SCM*. SCM: *Git*.
   - *Repository URL*: la URL HTTPS del repo. *Credentials*: la de su cuenta.
   - *Branch Specifier*: `*/main`. *Script Path*: `Jenkinsfile`.
   - *Build Triggers > Poll SCM*: `H/5 * * * *` para que cada push dispare un build.
3. **Construir ahora.** Con `watch docker ps` en el servidor verás aparecer el agente `dotnet`. El primer build tarda más: descarga los paquetes NuGet y las imágenes de los escáneres.
4. **Publica dev en la LAN.** Cuando termine *Deploy dev* existe el contenedor `mi-api-dev`. En Nginx Proxy Manager crea un *Proxy Host*: dominio `mi-api-dev.int.<dominio>`, destino `http://mi-api-dev:8080`, certificado wildcard. Abre `https://mi-api-dev.int.<dominio>`.
5. **Promueve a prod.** El pipeline queda esperando en *Aprobar prod* sin ocupar agente. Al aceptar, despliega la misma imagen como `mi-api-prod`. Para exponerla a internet, añade en el túnel de Cloudflare un *Public Hostname* que apunte a `http://mi-api-prod:8080`.

Si algo falla:

| Síntoma | Causa habitual |
|---|---|
| El build se queda en "Waiting for next available executor" | La versión del agente no está publicada (`./mercury agents list`, y `./mercury agents <agente>:<versión>` para publicarla); la etiqueta del Jenkinsfile no existe (`dotnet-7.0`); o ya hay `JENKINS_MAX_AGENTS` agentes en marcha |
| Falla el checkout con error de autenticación | Token caducado o sin permiso de lectura; o la credencial elegida no es de ese proveedor |
| `NETSDK1045` en la compilación | El proyecto pide una versión de .NET más nueva que la del agente: usa la etiqueta de su versión (`dotnet-10.0`) |
| "You must install or update .NET to run this application" en los tests o en `docker logs mi-api-dev` | El proyecto apunta a una versión distinta de la del agente: cambia la etiqueta del Jenkinsfile a la de su `TargetFramework` |
| `MSB1009` o "Project file does not exist" en *Build, test y SonarQube* | `SOLUTION` no coincide con la ruta del `.slnx` o `.sln` |
| `MSB1009` o "Project file does not exist" en *Imagen* | `PROJECT` no coincide con la ruta del `.csproj` |
| `dotnet publish` falla en *Imagen* porque no encuentra los binarios compilados | `PROJECT` no está incluido en `SOLUTION`: la plantilla publica con `--no-build` lo que compiló la solución |
| El build se aborta a los 45 minutos | Límite del stage *CI*: súbelo en el `timeout` del Jenkinsfile |
| `No plugin found for prefix 'sonar'` en *SonarQube*, seguido de `Unable to locate 'report-task.txt'` | El Jenkinsfile llama a `mvn sonar:sonar`: Maven ya no resuelve ese atajo. Usa las coordenadas completas de la plantilla (`org.sonarsource.scanner.maven:sonar-maven-plugin:<versión>:sonar`). El segundo aviso solo indica que el escáner no llegó a ejecutarse |
| *Seguridad* falla con `remote Maven repository returned 429 Too Many Requests` | Trivy pidió los POM a Maven Central en lugar de leerlos de la caché. Actualiza los agentes (`./mercury agents`) y espera a que pase el bloqueo de la IP, unos 30 minutos |
| *Quality gate* se agota a los 10 minutos | Falta el webhook de SonarQube hacia `http://jenkins:8080/sonarqube-webhook/` |
| *Deploy dev* falla tras 120 segundos | El contenedor no arranca: `docker logs mi-api-dev`. Suele faltar configuración en `/srv/mercury/apps/dev/mi-api.env` |

### Credenciales de git

Jenkins puede tener varias cuentas de GitHub, GitLab o Bitbucket a la vez. Se definen en `stacks/devops/jenkins/casc/credentials.yaml`, agrupadas en un dominio por proveedor, y sus tokens se guardan en `stacks/devops/jenkins/credentials.env` (no se versiona).

```
Credenciales de Jenkins
├── (global)   registry, sonar-token     las usa la plataforma: no cambiar sus ID
├── GitHub     github-mercury, ...
└── GitLab     gitlab-mercury, ...
```

**Añadir una cuenta.** El ID sigue la forma `<proveedor>-<dueño>`:

1. En `credentials.env`, dos líneas: `GITHUB_COMPANY_USER=...` y `GITHUB_COMPANY_TOKEN=...`.
2. En `credentials.yaml`, un bloque `usernamePassword` con `id: "github-company"` dentro del dominio de su proveedor (el archivo trae ejemplos comentados, también para Bitbucket).
3. `./mercury up jenkins` (recrea el contenedor porque cambió `credentials.env`).

Las credenciales creadas desde la interfaz de Jenkins se pierden al reiniciar: la fuente de verdad son esos dos archivos.

**Elegir la credencial en un pipeline.**

- Repo de la app: en el job, *Pipeline script from SCM > Credentials*. El desplegable solo muestra las cuentas del proveedor de la URL (con una URL de `github.com` no aparecen las de GitLab).
- Un repo adicional dentro del Jenkinsfile:
  ```groovy
  dir('libs') {
    git url: 'https://gitlab.com/grupo/libs.git', branch: 'main', credentialsId: 'gitlab-mercury'
  }
  ```
- Usuario y token como variables, para un comando propio:
  ```groovy
  withCredentials([usernamePassword(credentialsId: 'github-company', usernameVariable: 'GIT_USR', passwordVariable: 'GIT_PSW')]) {
    sh 'git ls-remote "https://$GIT_USR:$GIT_PSW@github.com/empresa/repo.git"'
  }
  ```

**Otras personas.** Para que alguien más use este Jenkins con sus repos, añade su cuenta como una credencial más (`github-<persona>`). No hay aislamiento entre personas: todos los usuarios de Jenkins son administradores, cualquier Jenkinsfile puede pedir cualquier credencial por su ID y un pipeline tiene acceso casi de root al servidor a través de Docker. Compartir el Jenkins es confiar el servidor entero; la separación por carpetas está descrita en [04-operacion-y-futuro.md](04-operacion-y-futuro.md#jenkins-compartido).

## Canal manual

1. Compila en tu PC:
   - .NET: `dotnet publish -c Release -o publish` → copia el contenido de `publish/`
   - Spring: `mvn package` → copia solo el `.jar`
   - Flask / Node: copia el código (sin `venv` ni `node_modules`)
   - Estático: copia la carpeta del sitio
   - Angular / React / Vue: `npm run build` → copia el contenido de la carpeta generada (la que tiene `index.html`) y elige el runtime `spa`
2. Cópialo a `inbox/<app>/` por Samba (`\\IP\inbox`) o SFTP (usuario `deployer`). El nombre de la carpeta es el nombre de la app: minúsculas, números y guiones.
3. En Jenkins, job **manual-release** > *Build with Parameters*: `APP`, `RUNTIME`, `RUNTIME_VERSION` y `TARGET_ENV`. `RUNTIME_VERSION` es la versión con la que compilaste (8.0 para `net8.0`, 17 para Java 17); `default` usa la de la plantilla. Si la carpeta incluye un `Dockerfile`, se usa ese.

La imagen queda en el registry como `apps/<app>:manual-<n>`, con lo que tienes historial y puedes volver a una versión anterior.

### Modo rápido (solo dev)

Para probar algo al momento, sin Jenkins ni imagen: el contenedor monta directamente la carpeta de inbox.

```bash
./mercury quick <app> <dotnet|spring|flask|node|static> [versión]
./mercury quick mi-api dotnet 8.0
```

Repite el comando tras copiar una versión nueva (en sitios estáticos no hace falta). El runtime `spa` no tiene modo rápido: un Angular o React compilado se prueba con `static`, sin el retorno a `index.html` en rutas internas. Usa el mismo nombre de contenedor que el canal normal (`<app>-dev`), así que comparte dominio en NPM; el último que despliegues es el que queda.

## Configuración y secretos de una app

Las variables de entorno de cada app y ambiente van en un archivo del servidor, fuera de git y de la imagen:

```bash
nano /srv/mercury/apps/prod/mi-api.env
# ConnectionStrings__Default=Server=...;Password=...
# SPRING_DATASOURCE_URL=jdbc:postgresql://...
chmod 640 /srv/mercury/apps/prod/mi-api.env
```

Se aplica en el siguiente despliegue. Para subir el límite de memoria de una app (512 MB por defecto), define `APP_MEM_LIMIT = '1g'` en el `environment` de su Jenkinsfile.

## Operaciones frecuentes

```bash
docker ps --filter network=net-apps-prod          # qué hay desplegado en prod
docker logs -f mi-api-prod                        # logs (también en Grafana: {container="mi-api-prod"})
./mercury deploy mi-api prod 41                   # volver a la imagen del build 41
./mercury undeploy mi-api dev                     # retirar una app
```

## Dos ambientes en un servidor

Dev y prod están separados por red, no por máquina: un contenedor de `net-apps-dev` no puede hablar con uno de `net-apps-prod`, y el túnel de Cloudflare solo ve prod. Comparten CPU y RAM, así que el límite de memoria por contenedor es lo que evita que una prueba en dev afecte a producción.

Si una app necesita base de datos, créala como un stack propio (por ejemplo en `stacks/apps/<nombre>-db`) con su red privada `internal` y conecta la app también a esa red, siguiendo el modelo de `stacks/devops/sonarqube`.
