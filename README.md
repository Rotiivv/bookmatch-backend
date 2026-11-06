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

## Integração contínua e espelhamento

O workflow `.github/workflows/ci.yml` executa lint, build, testes unitários e
testes e2e em todo pull request e em todo push na `main`.

Quando um push na `main` passa no CI, a `main` é enviada para a branch
`backend` de `BookMatchTeam/bookmatch`. O envio usa uma deploy key com escrita
nesse repositório, cuja chave privada fica no secret
`BOOKMATCH_TEAM_DEPLOY_KEY` deste repositório. Sem o secret, o espelhamento é
ignorado com um aviso.

A branch `backend` é somente leitura: alterações devem ser feitas neste
repositório. O envio não usa `--force`, então commits feitos diretamente nela
interrompem o espelhamento.
