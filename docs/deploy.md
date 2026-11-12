# Deploy na VPS

Este guia prepara a VPS para receber a API e liga o deploy automatico (CD).
Depois de pronto, todo merge na `main` que passar no CI e publicado sozinho.

## Como funciona

```text
pull request
  -> CI (.github/workflows/ci.yml), job "Lint, build e testes":
       lint, build, testes unitarios e e2e
       smoke test (deploy/smoke-test.sh): monta as imagens e liga banco,
       migrations e API como na VPS, chamando o /health
  -> o merge so e liberado com o CI verde

merge na main
  -> CI roda de novo na main
  -> CD (.github/workflows/cd.yml), apenas se o CI passou:
       job "Montar e publicar as imagens", na maquina do GitHub:
         confere que o commit pertence a main
         monta as imagens da API e do migrate e publica no GHCR
         (ghcr.io/rotiivv/bookmatch-backend[-migrate]:<hash do commit>)
       job "Deploy na VPS":
         envia compose.prod.yaml, deploy/Caddyfile e deploy/deploy.sh
         para ~/bookmatch, entra no GHCR com um token temporario e executa
         bash deploy/deploy.sh
           -> baixa as imagens prontas da versao
           -> sobe o MariaDB
           -> aplica as migrations do Prisma
           -> sobe a API e o Caddy e espera a API ficar saudavel
```

A VPS nao tem o codigo-fonte nem o Git e nao compila nada: recebe imagens
prontas, as mesmas para todo deploy da mesma versao. O CD tambem pode ser
disparado a mao (veja "Operacao do dia a dia").

Na VPS ficam so estes arquivos:

```text
/home/deploy/bookmatch/
|-- compose.prod.yaml     enviado pelo CD a cada deploy
|-- .env                  criado por voce (fase 3); fica so na VPS
`-- deploy/
    |-- Caddyfile         enviado pelo CD
    `-- deploy.sh         enviado pelo CD
```

Na VPS rodam tres containers, descritos em `compose.prod.yaml`:

| Servico   | Funcao                                                    | Exposto na internet |
| --------- | --------------------------------------------------------- | ------------------- |
| `caddy`   | Recebe as requisicoes, cuida do HTTPS e repassa para a API | Sim (80 e 443)      |
| `api`     | A aplicacao NestJS                                         | Nao                 |
| `mariadb` | O banco de dados, com os dados num volume persistente      | Nao                 |

O servico `migrate` nao fica rodando: o `deploy.sh` o executa uma vez por
deploy para aplicar as migrations.

Valores usados neste guia:

| Item              | Valor                            |
| ----------------- | -------------------------------- |
| IP da VPS         | `187.41.123.210`                 |
| Dominio da API    | `api-bookmatch.galpao.tech`      |
| Sistema           | Ubuntu 26.04 LTS                 |
| Usuario de deploy | `deploy`                         |
| Pasta na VPS      | `/home/deploy/bookmatch`         |

Os comandos podem ser executados pelo terminal do navegador do hPanel ou por
SSH. Quando um passo trocar de usuario com `su - deploy`, rode o `su` sozinho
e so cole os comandos seguintes depois que o prompt mudar para
`deploy@...$`: linhas coladas junto com o `su` se perdem na troca.

---

## Fase 0: DNS

Um registro `A` faz `api-bookmatch.galpao.tech` apontar para o IP da VPS. No
hPanel: Dominios -> galpao.tech -> DNS / Nameservers -> Gerenciar registros
DNS (nao use a aba "Child nameservers", que serve para outra coisa).

| Tipo | Nome            | Valor            | TTL   |
| ---- | --------------- | ---------------- | ----- |
| A    | `api-bookmatch` | `187.41.123.210` | 14400 |

Confira no seu computador. A primeira consulta vai direto ao servidor de DNS
da Hostinger; a segunda, a um servidor publico, que pode demorar mais para
receber a mudanca:

```bash
nslookup api-bookmatch.galpao.tech apollo.dns-parking.com
nslookup api-bookmatch.galpao.tech 8.8.8.8
```

As duas devem mostrar `187.41.123.210`. O Caddy so consegue o certificado
HTTPS depois que o DNS estiver valendo para o mundo.

---

## Fase 1: sistema, usuario e firewall

Como `root`.

### 1.1 Atualizar o sistema

```bash
cat /etc/os-release            # confirme que e Ubuntu
apt update && apt upgrade -y
ls /var/run/reboot-required 2>/dev/null && echo "PRECISA REINICIAR" || echo "nao precisa reiniciar"
```

Se precisar reiniciar (atualizacao de kernel), rode `reboot`, espere um ou
dois minutos, entre de novo e confira a versao com `uname -r`.

### 1.2 Criar o usuario `deploy`

O dia a dia e o deploy automatico usam um usuario comum, que pede `sudo`
quando precisa, em vez do `root`.

```bash
adduser deploy                 # defina uma senha forte; os demais campos podem ficar vazios
usermod -aG sudo deploy
id deploy                      # deve listar o grupo sudo
```

### 1.3 Firewall

Bloqueia tudo que chega, exceto SSH (22), HTTP (80, usado pelo Caddy para o
certificado e o redirecionamento) e HTTPS (443). Libere a porta 22 antes de
ligar o firewall.

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable                     # responda y
ufw status verbose
```

Portas publicadas pelo Docker passam por fora do `ufw`. Por isso, no
`compose.prod.yaml`, so o Caddy publica portas. Se o firewall do painel da
Hostinger estiver ativo, libere as mesmas portas la.

### 1.4 Fechar o SSH (faca por ultimo)

Desliga o login por senha e o login do `root` pelo SSH; so entra quem tiver
uma chave autorizada. Faca depois que o deploy estiver funcionando e na ordem
abaixo, para nao perder o acesso.

1. No seu computador, crie uma chave pessoal (se ainda nao tiver uma) e
   autorize-a no usuario `deploy`:

   ```bash
   ssh-keygen -t ed25519 -C "meu-computador"

   # macOS / Linux
   ssh-copy-id deploy@187.41.123.210

   # Windows (PowerShell)
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@187.41.123.210 "cat >> ~/.ssh/authorized_keys"
   ```

2. Teste num terminal novo: `ssh deploy@187.41.123.210` deve entrar sem pedir
   a senha do usuario.

3. Na VPS, como `root`, feche o SSH:

   ```bash
   tee /etc/ssh/sshd_config.d/99-seguranca.conf > /dev/null <<'EOF'
   PasswordAuthentication no
   PermitRootLogin no
   EOF
   systemctl reload ssh
   ```

4. Sem fechar a sessao atual, teste num terminal novo: `ssh deploy@...` entra
   e `ssh root@...` e recusado. Se algo der errado, o hPanel tem um console de
   emergencia.

O terminal do navegador do hPanel pode deixar de funcionar como `root` depois
desse passo, dependendo de como a Hostinger o implementa. Garanta o passo 2
antes.

---

## Fase 2: Docker

Algumas imagens da Hostinger ja trazem o Docker. Confira antes de instalar:

```bash
docker --version
docker compose version
systemctl is-active docker
docker ps -a                                  # containers existentes
ss -tlnp | grep -E ':(80|443)\s'              # nada deve aparecer: portas livres
```

Se o Docker nao estiver instalado, use o repositorio oficial. Antes, confira se
ele ja publica pacotes para a sua versao do Ubuntu (deve responder `200`):

```bash
curl -fsSI "https://download.docker.com/linux/ubuntu/dists/$(. /etc/os-release && echo "$VERSION_CODENAME")/Release" | head -1
```

```bash
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Mesmo com o Docker ja instalado, cadastrar o repositorio garante as
atualizacoes de seguranca.

Permita que o `deploy` use o Docker sem `sudo` (necessario para o deploy
automatico). Quem esta no grupo `docker` tem poder equivalente ao root, entao
so adicione usuarios de confianca.

```bash
usermod -aG docker deploy
su - deploy                    # rode sozinho
```

Ja como `deploy`:

```bash
groups                         # deve listar docker
docker run --rm hello-world    # deve imprimir "Hello from Docker!"
exit
```

---

## Fase 3: pasta e configuracao de producao

Como `deploy` (`su - deploy`, sozinho). A VPS nao recebe o repositorio: so
precisa da pasta e do `.env` (modelo em `deploy/env.production.example`). O
restante o CD envia a cada deploy.

Crie o `.env` de producao com senhas geradas automaticamente:

```bash
mkdir -p ~/bookmatch && cd ~/bookmatch
cat > .env <<EOF
API_DOMAIN=api-bookmatch.galpao.tech
MARIADB_DATABASE=bookmatch
MARIADB_USER=bookmatch
MARIADB_PASSWORD=$(openssl rand -hex 24)
MARIADB_ROOT_PASSWORD=$(openssl rand -hex 24)
EOF
chmod 600 .env
sed -E 's/(PASSWORD=).*/\1********/' .env
```

- `chmod 600`: so o `deploy` le o arquivo.
- `openssl rand -hex 24`: senhas so com letras e numeros; caracteres como `@`
  ou `/` quebrariam a URL de conexao do Prisma.
- O `.env` fica so na VPS e nunca vai para o Git. Guarde uma copia das senhas
  (`cat .env`) num gerenciador de senhas: se o arquivo se perder, o banco
  continua exigindo a senha antiga.

---

## Fase 4: chave do GitHub Actions

O CD entra na VPS por SSH como `deploy`, com um par de chaves proprio. Gere o
par na propria VPS, assim a chave privada vai direto para o GitHub, sem passar
por outro lugar. Como `deploy`:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions -N ""
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
ls -l ~/.ssh
cat ~/.ssh/github_actions        # chave privada: copie o bloco inteiro, de BEGIN a END
```

O `-N ""` deixa a chave sem senha, porque o GitHub nao tem como digita-la. Os
`chmod` sao obrigatorios: o SSH recusa a chave se outros usuarios puderem
alterar esses arquivos.

No GitHub, em `Rotiivv/bookmatch-backend` -> Settings -> Secrets and
variables -> Actions -> New repository secret, crie:

| Nome          | Valor                                             |
| ------------- | ------------------------------------------------- |
| `VPS_HOST`    | `187.41.123.210`                                  |
| `VPS_USER`    | `deploy`                                          |
| `VPS_SSH_KEY` | o conteudo da chave privada, de `BEGIN` ate `END` |

Sem esses secrets, o CD termina com um aviso e nao publica nada.

---

## Fase 5: primeiro deploy

Confira o DNS na VPS (`getent hosts api-bookmatch.galpao.tech` deve mostrar
`187.41.123.210`) e dispare o CD: Actions -> CD -> Run workflow (branch
`main`, campo vazio). Depois:

```bash
curl -sS https://api-bookmatch.galpao.tech/health
```

O primeiro deploy demora alguns minutos (a VPS baixa as imagens inteiras); os
seguintes so baixam as camadas que mudaram. A resposta esperada do `curl` e
`{"status":"ok","service":"bookmatch-backend",...}`. O Swagger fica em
`https://api-bookmatch.galpao.tech/api/docs`.

Se o HTTPS falhar, veja os logs do Caddy (em `~/bookmatch`:
`docker compose -f compose.prod.yaml logs caddy`). As causas mais comuns sao
o DNS ainda nao apontar para a VPS ou a porta 80 estar fechada.

Com o deploy funcionando, apague a chave privada da VPS. A publica, em
`authorized_keys`, continua la e e o que permite a entrada.

```bash
rm ~/.ssh/github_actions
```

### Imagens no GHCR

As imagens aparecem em github.com/Rotiivv -> Packages
(`bookmatch-backend` e `bookmatch-backend-migrate`), uma versao por commit
publicado. Pacotes privados contam no limite de armazenamento do plano do
GitHub; como o repositorio e publico e as imagens so tem o codigo compilado,
podem ficar publicos (Package settings -> Change visibility). O deploy
funciona do mesmo jeito nos dois casos.

---

## Operacao do dia a dia

### Pelo GitHub

| Para                          | Como                                                                 |
| ----------------------------- | -------------------------------------------------------------------- |
| Publicar uma mudanca          | Merge do PR na `main`. O CI roda e, se passar, o CD publica sozinho  |
| Republicar a versao atual     | Actions -> CD -> Run workflow, campo vazio                           |
| Voltar para uma versao antiga | Actions -> CD -> Run workflow, informando o hash de um commit da `main` |

O CD so publica commits que pertencem a `main`. Se as imagens do commit ja
estao no GHCR, ele usa as mesmas, sem montar de novo. Commits anteriores a
publicacao pelo GHCR nao tem imagem e sao montados na hora, o que so funciona
se o `Dockerfile` daquele commit ja tiver o estagio `migrate`.

Ao voltar uma versao, as migrations ja aplicadas nao sao desfeitas: o banco
continua com a estrutura mais nova. Depois, corrija o problema num PR normal.

### Na VPS

Como `deploy`, em `~/bookmatch`:

| Para                        | Comando                                           |
| --------------------------- | ------------------------------------------------- |
| Ver o estado dos containers | `docker compose -f compose.prod.yaml ps`          |
| Acompanhar os logs da API   | `docker compose -f compose.prod.yaml logs -f api` |
| Reiniciar a API             | `docker compose -f compose.prod.yaml restart api` |

Para publicar, use o CD (pelo GitHub). Um `docker compose up` feito a mao, sem
o `IMAGE_TAG` que o CD informa, falha de proposito ao procurar a imagem
`defina-IMAGE_TAG`, em vez de publicar uma versao qualquer.

A cada deploy, o `deploy.sh` apaga da VPS as imagens de outras versoes e
mantem as da versao atual.

Os logs de cada container ficam limitados a 3 arquivos de 10 MB (configuracao
`x-logging` no `compose.prod.yaml`); os mais antigos sao apagados sozinhos.

Os dados do banco ficam no volume `bookmatch-prod_mariadb_data` e sobrevivem a
deploys e reinicios. Eles so sao apagados com `docker compose down -v`, que
nao deve ser usado em producao.

### Smoke test

O `deploy/smoke-test.sh` roda no CI, mas tambem pode ser executado em
qualquer maquina com Docker. Ele monta as imagens a partir do codigo
(juntando o `compose.build.yaml` ao `compose.prod.yaml`) em vez de baixa-las
do GHCR:

```bash
bash deploy/smoke-test.sh
```

Ele usa um projeto Compose separado (`bookmatch-smoke`) e um `.env`
temporario, sobe banco, migrations e API, chama o `/health` e apaga tudo no
fim. Nao toca nos containers nem no `.env` de producao.

---

## Migracao do formato antigo (uma vez)

Ate o PR #4, a VPS tinha um clone do repositorio em `~/bookmatch-backend` e
compilava a API. Para passar ao formato atual sem perder dados:

1. **Antes do merge**, como `deploy`, copie (nao mova) o `.env`:

   ```bash
   mkdir -p ~/bookmatch
   cp ~/bookmatch-backend/.env ~/bookmatch/.env
   chmod 600 ~/bookmatch/.env
   ```

2. Faca o merge. O CD publica a partir de `~/bookmatch`. Como o nome do
   projeto Compose continua `bookmatch-prod`, os containers e o volume do
   banco sao os mesmos: os dados sao preservados.

3. Confira o `/health` e o `docker compose -f compose.prod.yaml ps` em
   `~/bookmatch`.

4. So entao limpe o formato antigo: a pasta `~/bookmatch-backend`, as imagens
   montadas na VPS (`bookmatch-backend:latest` e
   `bookmatch-backend-build:latest`), o cache de build do Docker e, se quiser,
   o Git.
