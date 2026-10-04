# Empaqueta una app Node.js. Contexto de build: el código con su package.json.
# La app debe escuchar en process.env.PORT y tener un script "start".
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app
# Las dependencias van primero: la capa se reutiliza mientras no cambien los package*.json
COPY package*.json ./
# La caché de npm vive en la caché de build del host, no en la imagen
RUN --mount=type=cache,target=/root/.npm if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi
COPY . .

EXPOSE 8080
USER node

CMD ["npm", "start"]
