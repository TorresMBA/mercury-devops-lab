# Empaqueta un JAR ejecutable de Spring Boot.
# Contexto de build: una carpeta con un único .jar (si hay varios, el build falla a propósito).
ARG JAVA_VERSION=21
FROM eclipse-temurin:${JAVA_VERSION}-jre

WORKDIR /app
COPY *.jar /app/app.jar

# La JVM usa hasta el 75 % del límite de memoria del contenedor
ENV SERVER_PORT=8080 \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0"
EXPOSE 8080
USER 10001

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
