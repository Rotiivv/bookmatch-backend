# BookMatch Backend

API REST modular do BookMatch, construída com NestJS 12, ESM, Vitest,
NodeAdapter, Prisma ORM 7 e MariaDB.

## Pré-requisitos

- Node.js 22.22.3+ na linha 22, ou Node.js 24.15+
- npm
- Docker com Docker Compose para o banco local

## Preparação

```bash
cp .env.example .env
npm install
npm run db:up
npm run prisma:generate
```

Os modelos de domínio ainda não foram definidos. Por isso, a migration inicial
deve ser criada somente depois da inclusão dos primeiros modelos em
`prisma/schema.prisma`:

```bash
npm run prisma:migrate -- --name init
```

## Execução

```bash
npm run start:dev
```

- Saúde: `GET http://localhost:3000/health`
- Swagger UI: `http://localhost:3000/api/docs`

## Verificações

```bash
npm run build
npm test
npm run test:e2e
npm run lint
```
