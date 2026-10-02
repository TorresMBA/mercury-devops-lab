ARG JENKINS_VERSION
FROM jenkins/jenkins:${JENKINS_VERSION}

# Plugins instalados en la imagen: el controller arranca igual en cualquier máquina
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
