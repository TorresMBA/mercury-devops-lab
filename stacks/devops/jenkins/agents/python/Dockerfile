# Agente para Python: tests y análisis. La versión de ejecución real la fija el Dockerfile de la app.
ARG BASE
FROM ${BASE}
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv python3-pip \
 && rm -rf /var/lib/apt/lists/*
USER jenkins
