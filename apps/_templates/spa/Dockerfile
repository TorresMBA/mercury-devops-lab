# Aplicación de una sola página (Angular, React, Vue) ya compilada, servida por nginx
# sin privilegios en el puerto 8080.
# Contexto de build: la carpeta con index.html (dist/<proyecto>/browser en Angular, dist en Vite).
# A diferencia de `static`, lo que no es un archivo devuelve index.html: el enrutador
# del SPA resuelve la ruta en el navegador y recargar una ruta interna no da 404.
ARG NGINX_VERSION=1.30
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine

COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 8080;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

COPY . /usr/share/nginx/html
EXPOSE 8080
