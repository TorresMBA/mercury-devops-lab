# Agente para Java: JDK completo y Maven tomados de la imagen oficial de Maven.
# VERSION es la del JDK (8, 11, 17, 21, 25). Se construye con: ./mercury agents maven:<versión>
ARG BASE
ARG VERSION=21
ARG MAVEN_VERSION=3.10.0
FROM maven:${MAVEN_VERSION}-eclipse-temurin-${VERSION} AS maven

FROM ${BASE}
ARG VERSION
USER root
COPY --from=maven /opt/java/openjdk /opt/jdk
COPY --from=maven /usr/share/maven /usr/share/maven
RUN ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

# El JDK del proyecto va primero en el PATH. El proceso del agente de Jenkins no lo usa:
# arranca con el Java de la imagen base (javaExe en casc/jenkins.yaml), que con
# Java 8 u 11 no podría ejecutarse.
# RUNTIME_VERSION: mercury-ci package empaqueta la app sobre la misma versión
ENV RUNTIME_VERSION=${VERSION} \
    JAVA_HOME=/opt/jdk \
    MAVEN_HOME=/usr/share/maven \
    PATH="/opt/jdk/bin:${PATH}"

USER jenkins
