# Imagen con Wrangler para desplegar el relay sin instalar Node/Wrangler en la Mac.
# Debian slim (no alpine): los binarios de workerd que trae Wrangler necesitan glibc.
FROM node:22-slim

ARG WRANGLER_VERSION=4
RUN npm install -g "wrangler@${WRANGLER_VERSION}" \
 && npm cache clean --force

ENV WRANGLER_SEND_METRICS=false
WORKDIR /app

ENTRYPOINT ["wrangler"]
CMD ["--help"]
