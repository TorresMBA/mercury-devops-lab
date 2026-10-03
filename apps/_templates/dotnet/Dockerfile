# Empaqueta la salida de `dotnet publish -c Release -o publish`.
# Contexto de build: la carpeta publicada. DOTNET_VERSION debe coincidir con el TargetFramework:
# mercury-ci package la toma del agente (dotnet-8.0 -> 8.0) o del parámetro del canal manual.
ARG DOTNET_VERSION=10.0
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}

WORKDIR /app
COPY . .

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER $APP_UID

# APP_DLL permite fijar el ensamblado; si no, se deduce del único *.runtimeconfig.json
ENTRYPOINT ["sh", "-c", "exec dotnet \"${APP_DLL:-$(ls *.runtimeconfig.json | head -n 1 | sed 's/\\.runtimeconfig\\.json$/.dll/')}\""]
