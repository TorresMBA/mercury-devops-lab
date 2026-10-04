# Agente base: cliente Docker + pasos de pipeline (mercury-ci) + plantillas de apps.
# Se construye con la raíz del repo como contexto: ./mercury agents base
# Los agentes de cada lenguaje parten de esta imagen (agents/base:current).
ARG AGENT_VERSION
FROM jenkins/agent:${AGENT_VERSION}

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq unzip \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

COPY pipelines/lib/mercury-ci /usr/local/bin/mercury-ci
COPY apps/_templates /opt/mercury/templates
RUN chmod 755 /usr/local/bin/mercury-ci

# Destinos de las cachés de dependencias (mounts en casc/jenkins.yaml). Un volumen nuevo
# hereda el dueño del directorio de la imagen: sin esto nacería como root y el build no
# podría escribir en él.
RUN install -d -o jenkins -g jenkins \
      /home/jenkins/.nuget /home/jenkins/.nuget/packages \
      /home/jenkins/.m2 /home/jenkins/.m2/repository \
      /home/jenkins/.npm \
      /home/jenkins/.cache /home/jenkins/.cache/pip

USER jenkins
