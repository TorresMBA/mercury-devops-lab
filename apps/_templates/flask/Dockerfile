# Empaqueta una app Flask servida con gunicorn.
# Contexto de build: el código con su requirements.txt.
# APP_MODULE = <módulo>:<objeto Flask>, por ejemplo app:app o wsgi:application.
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_MODULE=app:app

WORKDIR /app
# Las dependencias van primero: la capa se reutiliza mientras no cambie requirements.txt
COPY requirements.txt .
# La caché de pip vive en la caché de build del host, no en la imagen
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt gunicorn
COPY . .

EXPOSE 8080
USER 10001

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:8080 --workers 2 \"$APP_MODULE\""]
