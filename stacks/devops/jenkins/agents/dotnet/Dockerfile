# Agente para .NET. VERSION es la del SDK (8.0, 9.0, 10.0) y debe cubrir el
# TargetFramework de los proyectos. Se construye con: ./mercury agents dotnet:<versión>
ARG BASE
ARG VERSION=10.0
FROM mcr.microsoft.com/dotnet/sdk:${VERSION} AS sdk

FROM ${BASE}
ARG VERSION
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=sdk /usr/share/dotnet /usr/share/dotnet
RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

# RUNTIME_VERSION: mercury-ci package empaqueta la app sobre la misma versión
ENV RUNTIME_VERSION=${VERSION} \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PATH="${PATH}:/home/jenkins/.dotnet/tools"

USER jenkins
RUN dotnet tool install --global dotnet-sonarscanner
