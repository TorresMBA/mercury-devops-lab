# Sitio estático (HTML, CSS, JS) servido por nginx sin privilegios en el puerto 8080.
# Contexto de build: la carpeta con index.html.
ARG NGINX_VERSION=1.30
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine

COPY . /usr/share/nginx/html
EXPOSE 8080
