# Proximo PR de pipelines

Pendencias identificadas no primeiro deploy manual na VPS (10/11/2026), a
serem feitas num PR a partir da branch `ci-cd/pipelines`. A ideia e que esse
PR seja o primeiro deploy automatico pela pipeline.

## 1. Dockerfile: instalar o OpenSSL no estagio de build

**Problema.** Na etapa de migrations do deploy apareceu:

```text
prisma:warn Prisma failed to detect the libssl/openssl version to use, and may
not work as expected. Defaulting to "openssl-1.1.x".
```

A imagem base `node:24-slim` nao inclui a biblioteca OpenSSL, e a CLI do
Prisma precisa dela. A CLI so roda no servico `migrate`, que usa o estagio
`build` do `Dockerfile`. A API (estagio `runtime`) nao usa a CLI e nao e
afetada.

Hoje nao houve erro porque ainda nao existe nenhuma migration. Quando a
primeira migration for criada, o `migrate` pode falhar.

**O que fazer.** No estagio `build` do `Dockerfile`, antes do `npm ci`:

```dockerfile
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl \
  && rm -rf /var/lib/apt/lists/*
```

**Como verificar.** Rodar o servico `migrate` e confirmar que o aviso
`prisma:warn ... libssl/openssl` nao aparece mais.

## 2. CI: smoke test do `compose.prod.yaml`

**Problema.** O CI testa o codigo e monta a imagem Docker, mas nao liga os
containers de producao. O aviso do OpenSSL so apareceu na VPS.

**O que fazer.** Adicionar ao CI um teste que execute o mesmo fluxo do
`deploy/deploy.sh`, numa maquina descartavel do GitHub Actions:

1. criar um `.env` de teste, com senhas descartaveis;
2. subir o MariaDB;
3. rodar o `migrate` (`prisma migrate deploy`);
4. subir a API e esperar ela ficar saudavel;
5. chamar `/health`;
6. desligar tudo.

**O que ele detecta.**

- falha de migration, incluindo a falta do OpenSSL, no PR que criar a
  primeira migration;
- erro no `compose.prod.yaml` (variavel faltando, nome de servico errado);
- migration com erro de SQL;
- API que compila, mas nao sobe com a configuracao de producao.

**Limitacao.** Sem nenhuma migration, o teste passa mesmo sem o OpenSSL. Ele
complementa a correcao do item 1; nao a substitui.

**Custo.** Cerca de 1 minuto a mais por execucao do CI.
