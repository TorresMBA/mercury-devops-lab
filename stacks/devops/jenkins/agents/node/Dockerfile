# Agente para Node.js: binarios tomados de la imagen oficial de Node.
# VERSION es la mayor de Node (20, 22, 24). Se construye con: ./mercury agents node:<versión>
ARG BASE
ARG VERSION=22
FROM node:${VERSION}-trixie-slim AS node

FROM ${BASE}
ARG VERSION
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# RUNTIME_VERSION: mercury-ci package empaqueta la app sobre la misma versión
ENV RUNTIME_VERSION=${VERSION}
USER jenkins
