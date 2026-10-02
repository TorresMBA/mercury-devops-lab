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

## Canal CI

1. Copia `apps/_templates/<runtime>/Jenkinsfile` a la raíz del repo de tu app y ajusta `APP` (y `PROJECT` en .NET).
2. En Jenkins: *Nueva tarea > Pipeline*, definición *Pipeline script from SCM*, Git, URL del repo, la credencial de la cuenta dueña del repo (por ejemplo `github-mercury`), rama `main`.
3. Lanza el build.

Etapas del pipeline:

| Etapa | Qué hace |
|---|---|
| Build y test | Compila y ejecuta los tests dentro del agente del lenguaje |
| SonarQube + Quality gate | Analiza el código; si no pasa el *quality gate*, el pipeline se detiene |
| Seguridad | Semgrep (fallos de seguridad en el código) y Trivy (dependencias vulnerables, secretos, configuración) |
| Imagen | Empaqueta el compilado con el `Dockerfile` plantilla, publica la imagen y la escanea con Trivy |
| Deploy dev | Despliega en dev automáticamente |
| Aprobar prod | Espera una confirmación manual (hasta 24 h), sin ocupar ningún agente |
| Deploy prod | Despliega **la misma imagen** que se probó en dev |

Por defecto los escáneres de seguridad informan pero no rompen el build. Para que los hallazgos de severidad alta o crítica lo detengan, añade al `environment` del Jenkinsfile: `MERCURY_SCAN_STRICT = '1'`.

**Disparo automático.** Jenkins no es visible desde internet, así que GitHub no puede enviarle webhooks. Lo más simple es que Jenkins consulte el repo: en el job, *Build Triggers > Poll SCM* con `H/5 * * * *` (cada 5 minutos).

**Dockerfile propio.** Si el compilado incluye un `Dockerfile` en su raíz, se usa ese en lugar de la plantilla.

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
3. `./mercury up jenkins`.

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
2. Cópialo a `inbox/<app>/` por Samba (`\\IP\inbox`) o SFTP (usuario `deployer`). El nombre de la carpeta es el nombre de la app: minúsculas, números y guiones.
3. En Jenkins, job **manual-release** > *Build with Parameters*: `APP`, `RUNTIME` y `TARGET_ENV`.

La imagen queda en el registry como `apps/<app>:manual-<n>`, con lo que tienes historial y puedes volver a una versión anterior.

### Modo rápido (solo dev)

Para probar algo al momento, sin Jenkins ni imagen: el contenedor monta directamente la carpeta de inbox.

```bash
./mercury quick <app> <dotnet|spring|flask|node|static>
```

Repite el comando tras copiar una versión nueva (en sitios estáticos no hace falta). Usa el mismo nombre de contenedor que el canal normal (`<app>-dev`), así que comparte dominio en NPM; el último que despliegues es el que queda.

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
