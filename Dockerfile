# Imagens de producao da API.
#
# As imagens sao montadas no GitHub Actions (workflow de CD) e publicadas no
# GHCR. A VPS so baixa as imagens prontas: nao recebe o codigo-fonte nem compila.
#
# Estagios:
# - deps:    sistema e todas as dependencias (base dos dois seguintes).
# - build:   gera o client do Prisma e compila o TypeScript para dist/.
# - migrate: imagem do servico "migrate": so a CLI do Prisma, o schema e as
#            migrations. Sem o src/.
# - runtime: imagem da API: dependencias de producao e o dist/ compilado.

FROM node:24-slim AS deps
# Liga as imagens publicadas no GHCR a este repositorio.
LABEL org.opencontainers.image.source=https://github.com/Rotiivv/bookmatch-backend
WORKDIR /app

# A CLI do Prisma (usada pelo servico migrate) precisa da biblioteca OpenSSL,
# que nao vem na imagem slim.
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci


FROM deps AS build
# Apenas o que o build usa. O .dockerignore continua como segunda protecao.
COPY tsconfig.json tsconfig.build.json nest-cli.json prisma7.config.ts ./
COPY prisma ./prisma
COPY src ./src

# O prisma7.config.ts exige DATABASE_URL para carregar, mas o generate nao se
# conecta ao banco. O valor real e informado em tempo de execucao.
RUN DATABASE_URL="mysql://build:build@localhost:3306/build" npm run prisma:generate \
  && npm run build


FROM deps AS migrate
COPY prisma7.config.ts ./
COPY prisma ./prisma
USER node
# DATABASE_URL vem do compose.prod.yaml.
CMD ["node_modules/.bin/prisma", "migrate", "deploy"]


FROM node:24-slim AS runtime
LABEL org.opencontainers.image.source=https://github.com/Rotiivv/bookmatch-backend
ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional && npm cache clean --force

COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
