# Laboratório: Nginx no lugar do Caddy

Exercício para aprender a fazer com o Nginx o que o Caddy faz sozinho em
produção. Roda **no seu computador**. A VPS continua com o Caddy e nada aqui
mexe nela.

## Em vez de… / você vai ver

| Caddy em produção (`deploy/Caddyfile`) | Nginx neste laboratório |
|---|---|
| `reverse_proxy api:3000` | Etapa 1: `proxy_pass` e os cabeçalhos do proxy |
| Descobre o novo IP da API sozinho | Etapa 2: o 502 depois de um deploy e a correção |
| HTTPS automático | Etapa 3: certificado, porta 443 e redirecionamento |
| (não tem pronto) | Etapa 4: limite de requisições por IP |
| Renovação automática | Etapa 5 (em preparação): Certbot e Let's Encrypt simulado |

## Como funciona

```
seu navegador / curl
   │  http://localhost:8080   https://localhost:8443
   ▼
[ nginx ]  ← lê conf.d/default.conf
   │  http://api:3000   (rede interna do Docker)
   ▼
[ api ]    ← a mesma imagem da produção, sem banco
```

- `etapas/`: uma configuração pronta e comentada por etapa. **Leia o arquivo
  antes de usar.**
- `conf.d/default.conf`: a configuração **em uso**. Em cada etapa você copia
  o arquivo da etapa para cá e manda o Nginx recarregar.
- `certs/`: certificados da etapa 3. Não vão para o Git.

Os comandos abaixo funcionam no PowerShell e no Linux. No PowerShell, use
`curl.exe` (com `.exe`): só `curl` chama outro comando do Windows.

## Preparação

Precisa do Docker Desktop ligado e das portas 8080 e 8443 livres.

```powershell
cd labs/nginx
docker compose up -d --build
docker compose ps
```

O primeiro `--build` monta a imagem da API e demora alguns minutos.

---

## Etapa 1: proxy reverso

**Objetivo:** o Nginx recebe o pedido e repassa para a API.

Leia `etapas/1-proxy.conf`; ela já está em uso. Teste:

```powershell
curl.exe -i http://localhost:8080/health
docker compose logs nginx --tail 5
```

**O que observar**

- A resposta tem `Server: nginx/1.28.3`: quem respondeu foi o Nginx, que
  buscou o conteúdo na API.
- No log, uma linha por pedido: IP, data, caminho e status (`200`).
- A API não tem porta publicada. Tente `curl.exe http://localhost:3000/health`:
  falha (ou responde outra coisa, se o `npm run start:dev` estiver ligado).
  Só o Nginx chega nela, como na VPS.

**Dois comandos que você vai usar sempre**

```powershell
docker compose exec nginx nginx -t          # confere a configuração
docker compose exec nginx nginx -s reload   # aplica sem derrubar ninguém
```

Sempre `-t` antes do `reload`. Se a configuração tiver erro, o `-t` avisa e o
Nginx continua com a anterior.

---

## Etapa 2: o 502 depois de um deploy

**Objetivo:** ver o problema clássico do Nginx com Docker e corrigir.

### 2a. Provocar o problema (ainda com a etapa 1)

Um deploy recria o container da API. Para ele ganhar **outro IP**, um
container "ocupa" o IP antigo:

```powershell
docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" lab-nginx-api-1
docker compose rm -sf api
docker run -d --rm --name ocupa-ip --network lab-nginx_default nginx:1.28.3-alpine sleep 600
docker compose up -d api
docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" lab-nginx-api-1
curl.exe -i http://localhost:8080/health
docker compose logs nginx --tail 3
```

**O que observar:** `502 Bad Gateway`. No log, o `upstream:` mostra o IP
**antigo**. O Nginx descobriu o IP de `api` uma vez, quando ligou, e nunca
mais perguntou.

### 2b. Corrigir

Leia `etapas/2-resolver.conf` e aplique:

```powershell
cp etapas/2-resolver.conf conf.d/default.conf
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
curl.exe -i http://localhost:8080/health
```

Volta o `200`. Repita o 2a (troque o nome `ocupa-ip` por `ocupa-ip2`): agora
continua `200`, sem reload. Depois, limpe: `docker stop ocupa-ip ocupa-ip2`.

### 2c. Outro efeito da mesma correção

Com a etapa 1, o Nginx **nem liga** se a API não existir. Com a etapa 2, ele
liga e responde 502 até a API voltar:

```powershell
docker compose rm -sf api
docker compose restart nginx
docker compose ps -a
curl.exe -i http://localhost:8080/health
docker compose up -d api
curl.exe -i http://localhost:8080/health
```

(Para ver o lado ruim, copie a etapa 1 de volta e repita: o `nginx` fica
`exited` e o log diz `host not found in upstream "api"`.)

**Por que importa:** o Caddy faz isso sozinho. No Nginx, esquecer o
`resolver` é a causa mais comum de "fiz deploy e a API caiu".

---

## Etapa 3: HTTPS

**Objetivo:** servir HTTPS e mandar quem chega por HTTP para o HTTPS.

Gere um certificado autoassinado (vale 30 dias, só para `localhost`):

```powershell
docker compose run --rm certificado
ls certs
```

São dois arquivos: `localhost.crt` (o certificado, público, vai para quem
acessa) e `localhost.key` (a chave privada, nunca sai do servidor).

Leia `etapas/3-https.conf` e aplique:

```powershell
cp etapas/3-https.conf conf.d/default.conf
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

Teste:

```powershell
curl.exe -i http://localhost:8080/health
curl.exe -i https://localhost:8443/health
curl.exe -ik https://localhost:8443/health
```

**O que observar**

1. HTTP → `301` com `Location: https://localhost:8443/health`.
2. HTTPS sem `-k` → erro de certificado: ninguém confia nele.
3. HTTPS com `-k` ("confie mesmo assim") → `200`, e a conexão é cifrada.
4. No navegador, `https://localhost:8443/health` mostra "Sua conexão não é
   particular". Clique no cadeado e veja o certificado: emitido por
   `localhost` para `localhost`.

**A lição:** cifrar é fácil. Difícil é ter um certificado em que os
navegadores confiem. Para isso, uma autoridade (o Let's Encrypt) precisa
confirmar que o domínio é seu. Isso, mais a renovação a cada 90 dias, é o que
o Caddy faz sozinho, e o tema da etapa 5.

---

## Etapa 4: limite de requisições

**Objetivo:** bloquear quem faz pedidos demais, por exemplo alguém testando
senhas na rota de login.

Leia `etapas/4-limite.conf` e aplique (precisa do certificado da etapa 3):

```powershell
cp etapas/4-limite.conf conf.d/default.conf
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

Mande 30 pedidos seguidos:

```powershell
# PowerShell
1..30 | % { curl.exe -sk -o NUL -w "%{http_code} " https://localhost:8443/health }
# Linux
for i in $(seq 30); do curl -sk -o /dev/null -w "%{http_code} " https://localhost:8443/health; done
```

**O que observar:** uns 11 `200` (5 por segundo mais a folga de 10) e depois
`429`. Espere 2 segundos e tente de novo: volta o `200`. O log mostra
`limiting requests`.

---

## Etapa 5: Let's Encrypt e renovação (em preparação)

Certbot pedindo o certificado a um Let's Encrypt simulado (Pebble), o
desafio pela porta 80, o problema do "ovo e a galinha" na primeira subida e
a renovação com `reload`.

---

## Encerrar

```powershell
docker compose down
```

Para começar do zero: `docker compose down --rmi local` e
`git checkout -- conf.d/default.conf`.

## O que daria para levar para a produção

| Etapa | Na VPS com Nginx seria preciso |
|---|---|
| 1 e 2 | A configuração da etapa 2, com `server_name api-bookmatch.galpao.tech` |
| 3 | Certificado do Let's Encrypt (Certbot) em vez do autoassinado; portas 80 e 443 |
| 4 | Pode ser usada como está, de preferência só nas rotas sensíveis |
| 5 | Um container do Certbot renovando, e o `reload` do Nginx depois de cada renovação |

Compare com o `deploy/Caddyfile`, que faz 1, 2, 3 e 5 em 4 linhas.
