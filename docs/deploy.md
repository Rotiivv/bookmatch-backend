# Deploy na VPS

Este guia prepara a VPS para receber a API e liga o deploy automatico (CD).
Depois de pronto, todo merge na `main` que passar no CI e publicado sozinho.

## Como funciona

```text
merge na main
  -> GitHub Actions, job "Lint, build e testes" (CI)
  -> job "Deploy na VPS" (CD), apenas se o CI passar:
       entra na VPS por SSH como usuario deploy e executa
         git fetch + git checkout <commit aprovado>
         bash deploy/deploy.sh
           -> monta as imagens Docker na propria VPS
           -> sobe o MariaDB
           -> aplica as migrations do Prisma
           -> sobe a API e o Caddy e espera a API ficar saudavel
```

Na VPS rodam tres containers, descritos em `compose.prod.yaml`:

| Servico   | Funcao                                                        | Exposto na internet |
| --------- | ------------------------------------------------------------- | ------------------- |
| `caddy`   | Recebe as requisicoes, cuida do HTTPS e repassa para a API     | Sim (80 e 443)      |
| `api`     | A aplicacao NestJS                                             | Nao                 |
| `mariadb` | O banco de dados, com os dados num volume persistente          | Nao                 |

Valores usados neste guia:

| Item                  | Valor                        |
| --------------------- | ---------------------------- |
| IP da VPS             | `187.41.123.210`             |
| Dominio da API        | `api-bookmatch.galpao.tech`  |
| Usuario de deploy     | `deploy`                     |
| Pasta do projeto      | `/home/deploy/bookmatch-backend` |

---

## Fase 0: DNS

Um registro `A` faz `api-bookmatch.galpao.tech` apontar para o IP da VPS.
No hPanel: Dominios -> galpao.tech -> DNS / Nameservers -> Gerenciar registros DNS.

| Tipo | Nome            | Valor            | TTL   |
| ---- | --------------- | ---------------- | ----- |
| A    | `api-bookmatch` | `187.41.123.210` | 14400 |

Confira no seu computador:

```bash
nslookup api-bookmatch.galpao.tech 8.8.8.8
```

A resposta deve mostrar `187.41.123.210`. O Caddy so consegue o certificado
HTTPS depois que isso estiver valendo.

---

## Fase 1: acesso e seguranca

### 1.1 Entrar como root e atualizar o sistema

```bash
ssh root@187.41.123.210
cat /etc/os-release          # os comandos deste guia assumem Ubuntu
apt update && apt upgrade -y
```

`apt update` baixa a lista de versoes novas; `apt upgrade -y` instala as
correcoes de seguranca antes de expor a maquina.

### 1.2 Criar o usuario `deploy`

O `root` pode tudo, inclusive estragar o sistema num erro de digitacao. O dia a
dia (e o deploy automatico) usa um usuario comum, que pede `sudo` quando precisa.

```bash
adduser deploy
usermod -aG sudo deploy
```

### 1.3 Entrar com chave SSH

Senhas podem ser adivinhadas por robos que testam servidores o tempo todo.
Com chave, so entra quem tem o arquivo da chave privada. A publica vai para a
VPS; a privada fica no seu computador.

No seu computador, se ainda nao tiver uma chave:

```bash
ssh-keygen -t ed25519 -C "meu-computador"
```

Envie a chave publica para o usuario `deploy`:

```bash
# macOS / Linux
ssh-copy-id deploy@187.41.123.210

# Windows (PowerShell)
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@187.41.123.210 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Teste num terminal novo: `ssh deploy@187.41.123.210` deve entrar sem pedir a
senha do usuario.

### 1.4 Firewall

Abre apenas o necessario: 22 (SSH), 80 (HTTP, usado pelo Caddy para obter o
certificado e redirecionar) e 443 (HTTPS).

```bash
sudo ufw allow OpenSSH       # primeiro o SSH, para nao se trancar para fora
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Portas publicadas pelo Docker passam por fora do `ufw`. Por isso, no
`compose.prod.yaml`, so o Caddy publica portas; a API e o banco nao. Se o
firewall do painel da Hostinger estiver ativo, libere as mesmas portas la.

### 1.5 Desligar login por senha e login como root

Faca apenas depois de confirmar que o passo 1.3 funciona.

```bash
sudo tee /etc/ssh/sshd_config.d/99-seguranca.conf > /dev/null <<'EOF'
PasswordAuthentication no
PermitRootLogin no
EOF
sudo systemctl reload ssh
```

Sem fechar o terminal atual, teste num novo: `ssh deploy@...` entra e
`ssh root@...` e recusado. Se algo der errado, o hPanel tem um console de
emergencia no navegador.

---

## Fase 2: Docker

O Docker roda os containers; o plugin Compose sobe os tres servicos juntos a
partir do `compose.prod.yaml`. Instalacao pelo repositorio oficial do Docker:

```bash
sudo apt install -y ca-certificates curl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Permita que o usuario `deploy` use o Docker sem `sudo` (necessario para o
deploy automatico). Quem esta no grupo `docker` tem poder equivalente ao root,
entao so adicione usuarios de confianca.

```bash
sudo usermod -aG docker deploy
exit                                  # saia e entre de novo para o grupo valer
ssh deploy@187.41.123.210
docker run --rm hello-world           # deve imprimir "Hello from Docker!"
docker compose version
```

---

## Fase 3: codigo e configuracao de producao

O repositorio e publico, entao a VPS clona sem precisar de chave.

```bash
git clone https://github.com/Rotiivv/bookmatch-backend.git ~/bookmatch-backend
cd ~/bookmatch-backend
cp deploy/env.production.example .env
chmod 600 .env                        # so o usuario deploy le o arquivo
```

Gere duas senhas e coloque-as no `.env` (`MARIADB_PASSWORD` e
`MARIADB_ROOT_PASSWORD`):

```bash
openssl rand -hex 24
openssl rand -hex 24
nano .env                             # Ctrl+O salva, Ctrl+X sai
```

Use apenas letras e numeros nas senhas: caracteres como `@` ou `/` quebram a
URL de conexao do Prisma. O `.env` fica so na VPS e nunca vai para o Git.

---

## Fase 4: primeiro deploy, manual

```bash
cd ~/bookmatch-backend
bash deploy/deploy.sh
```

A primeira execucao demora alguns minutos (baixa as imagens base e monta a da
API). Depois, teste do seu computador:

```bash
curl https://api-bookmatch.galpao.tech/health
```

A resposta esperada e `{"status":"ok","service":"bookmatch-backend",...}`. O
Swagger fica em `https://api-bookmatch.galpao.tech/api/docs`.

Se o HTTPS falhar, veja os logs do Caddy (`docker compose -f compose.prod.yaml
logs caddy`). As causas mais comuns sao o DNS ainda nao apontar para a VPS ou
a porta 80 estar fechada.

---

## Fase 5: chave do GitHub Actions e deploy automatico

O job "Deploy na VPS" entra na VPS por SSH como `deploy`. Ele precisa de um par
de chaves proprio, diferente da sua chave pessoal. Gere o par na propria VPS,
assim a chave privada nao passa por nenhum outro lugar alem do GitHub:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions -N ""
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys   # publica: autoriza a entrada
cat ~/.ssh/github_actions                                  # privada: copie tudo, de BEGIN a END
```

No GitHub, em `Rotiivv/bookmatch-backend` -> Settings -> Secrets and variables
-> Actions -> New repository secret, crie:

| Nome          | Valor                                             |
| ------------- | ------------------------------------------------- |
| `VPS_HOST`    | `187.41.123.210`                                  |
| `VPS_USER`    | `deploy`                                          |
| `VPS_SSH_KEY` | o conteudo da chave privada, de `BEGIN` ate `END` |

Depois de salvar o secret, apague a chave privada da VPS. A publica, em
`authorized_keys`, continua la e e o que permite a entrada.

```bash
rm ~/.ssh/github_actions
```

Sem esses secrets, o job de deploy termina com um aviso e nao publica nada.

---

## Operacao do dia a dia

Todos os comandos rodam em `~/bookmatch-backend`, como `deploy`:

| Para                         | Comando                                                         |
| ---------------------------- | --------------------------------------------------------------- |
| Ver o estado dos containers  | `docker compose -f compose.prod.yaml ps`                        |
| Acompanhar os logs da API    | `docker compose -f compose.prod.yaml logs -f api`               |
| Reiniciar a API              | `docker compose -f compose.prod.yaml restart api`               |
| Publicar de novo, manualmente| `bash deploy/deploy.sh`                                         |
| Voltar para uma versao antiga| `git checkout <commit> && bash deploy/deploy.sh`                |

Os dados do banco ficam no volume `bookmatch-prod_mariadb_data` e sobrevivem a
deploys e reinicios. Eles so sao apagados com `docker compose down -v`, que
nao deve ser usado em producao.
