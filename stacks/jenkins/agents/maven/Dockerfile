# Agente para Java: JDK completo y Maven tomados de la imagen oficial de Maven.
ARG BASE
ARG MAVEN_IMAGE=maven:3.10.0-eclipse-temurin-21
FROM ${MAVEN_IMAGE} AS maven

FROM ${BASE}
USER root
COPY --from=maven /opt/java/openjdk /opt/jdk
COPY --from=maven /usr/share/maven /usr/share/maven
RUN ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV JAVA_HOME=/opt/jdk \
    MAVEN_HOME=/usr/share/maven \
    PATH="/opt/jdk/bin:${PATH}"

USER jenkins
