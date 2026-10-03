# Agente para Python: intérprete tomado de la imagen oficial de Python.
# VERSION es la menor de Python (3.11, 3.12, 3.13). Se construye con: ./mercury agents python:<versión>
ARG BASE
ARG VERSION=3.12
FROM python:${VERSION}-slim-trixie AS python

FROM ${BASE}
ARG VERSION
USER root
# El python3 de Debian no se usa: se instala porque trae las librerías del sistema
# (ssl, ffi, sqlite, zlib...) que necesita el intérprete copiado a /usr/local,
# que va antes en el PATH.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=python /usr/local /usr/local
RUN ldconfig && python3 --version && python3 -c "import ssl, sqlite3, ctypes, venv"

# RUNTIME_VERSION: mercury-ci package empaqueta la app sobre la misma versión
ENV RUNTIME_VERSION=${VERSION}
USER jenkins
