# Imagem de producao da API.
#
# Dois estagios:
# - build: instala todas as dependencias, gera o client do Prisma e compila
#   o TypeScript. Tambem e usado pelo servico "migrate" do compose.prod.yaml,
#   pois contem a CLI do Prisma (dependencia de desenvolvimento).
# - runtime: apenas dependencias de producao e o codigo compilado.

FROM node:24-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# O prisma7.config.ts exige DATABASE_URL para carregar, mas o generate nao se
# conecta ao banco. O valor real e informado em tempo de execucao.
RUN DATABASE_URL="mysql://build:build@localhost:3306/build" npm run prisma:generate \
  && npm run build


FROM node:24-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional && npm cache clean --force

COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
