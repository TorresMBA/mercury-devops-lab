# Agente para Node.js: binarios tomados de la imagen oficial de Node.
ARG BASE
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-trixie-slim AS node

FROM ${BASE}
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
USER jenkins
