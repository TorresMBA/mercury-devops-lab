# Agente para .NET. DOTNET_VERSION debe cubrir el TargetFramework de los proyectos.
ARG BASE
ARG DOTNET_VERSION=10.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS sdk

FROM ${BASE}
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=sdk /usr/share/dotnet /usr/share/dotnet
RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PATH="${PATH}:/home/jenkins/.dotnet/tools"

USER jenkins
RUN dotnet tool install --global dotnet-sonarscanner
