# Arquitetura do BookMatch Backend

## Objetivo

O BookMatch Backend e uma API REST modular. Sua arquitetura prioriza:

- organizacao por dominios de negocio;
- casos de uso verticais;
- independencia entre regras de negocio e frameworks;
- testabilidade;
- evolucao incremental, evitando abstracoes prematuras.

Este documento descreve o estado arquitetural desejado para o projeto. Ele deve
ser atualizado quando uma decisao alterar a estrutura, as fronteiras ou a regra
de dependencia da aplicacao.

## Organizacao por dominios

Os modulos dentro de `src` representam dominios ou capacidades de negocio.

Exemplos esperados:

```text
src/
|-- auth/
|-- books/
`-- recommendations/
```

Cada dominio possui duas areas principais:

- `application`: nucleo independente de framework, contendo entidades, value
  objects, casos de uso, contratos e erros da aplicacao;
- `infra`: adaptadores e detalhes externos, como HTTP, NestJS, Prisma,
  criptografia e integracoes.

## Estrutura de um dominio

O dominio de autenticacao estabelece a estrutura inicial de referencia:

```text
src/auth/
|-- application/
|   |-- entities/
|   |   |-- vo/
|   |   `-- user.entity.ts
|   |-- exceptions/
|   `-- usecases/
|       `-- register-user/
|           |-- register-user.input.ts
|           |-- register-user.output.ts
|           |-- register-user.gateway.ts
|           |-- password-hasher.gateway.ts
|           |-- register-user.use-case.ts
|           `-- register-user.use-case.spec.ts
|-- infra/
|   |-- cryptography/
|   |-- http/
|   |   |-- dto/
|   |   `-- register-user.controller.ts
|   `-- persistence/
|       `-- prisma/
`-- auth.module.ts
```

A estrutura pode evoluir conforme novos casos de uso revelem necessidades
reais. Contratos compartilhados devem ser extraidos somente quando houver uso
por mais de um caso de uso ou uma responsabilidade comum claramente definida.

## Regra de dependencia

As dependencias apontam da infraestrutura para a aplicacao:

```text
infra -> application
```

A camada `application` nao pode importar elementos de `infra`, NestJS, Prisma,
HTTP ou qualquer outro mecanismo de entrega ou persistencia.

Consequentemente:

- entidades e value objects sao TypeScript puro;
- casos de uso recebem dependencias por contratos;
- gateways sao definidos pela aplicacao e implementados pela infraestrutura;
- controllers apenas traduzem o protocolo HTTP para entradas e saidas da
  aplicacao;
- o modulo NestJS compoe implementacoes concretas e casos de uso;
- detalhes externos podem ser substituidos sem alterar as regras da aplicacao.

## Casos de uso verticais

Cada caso de uso fica em uma pasta propria dentro de `application/usecases`.
Essa pasta concentra o comportamento e os contratos necessarios para executar
a operacao.

Um caso de uso pode conter:

- `input`: dados de entrada independentes do protocolo;
- `output`: resultado publico da operacao;
- `gateway`: contratos exigidos pelo caso de uso;
- implementacao do caso de uso;
- testes unitarios do comportamento.

O nome dos artefatos deve refletir a intencao de negocio. Para o registro de um
usuario, a nomenclatura adotada e `RegisterUser`, evitando alternar entre
`CreateUser` e `RegisterUser` para a mesma operacao.

## DTOs e entradas da aplicacao

DTOs representam contratos de mecanismos externos. Um DTO HTTP pertence a
`infra/http/dto` e pode utilizar decorators de validacao e documentacao do
NestJS.

Casos de uso nao recebem DTOs da infraestrutura. O controller converte o DTO
para um `Input` da aplicacao antes de executar o caso de uso.

Exemplo:

```text
RegisterUserRequestDto -> RegisterUserInput -> RegisterUserUseCase
```

O sufixo `Command` deve ser reservado para quando o projeto adotar
explicitamente esse vocabulario ou um mecanismo de CQRS. Ate la, `Input` torna
a responsabilidade do objeto mais direta.

## Entidades e value objects

Entidades possuem identidade e protegem invariantes que continuam verdadeiras
ao longo de seu ciclo de vida.

Value objects representam conceitos definidos por seus valores e concentram
validacoes e normalizacoes do dominio, como um endereco de e-mail. Eles devem
ser imutaveis sempre que possivel.

Decorators de persistencia, validacao HTTP ou injecao de dependencia nao devem
ser adicionados a entidades e value objects.

## Gateways e adaptadores

Gateways expressam capacidades externas exigidas pela aplicacao. Inicialmente,
eles podem ser especificos de um caso de uso, como `RegisterUserGateway`.

Adaptadores em `infra` implementam esses contratos. Exemplos:

```text
RegisterUserGateway <- PrismaRegisterUserGateway
PasswordHasherGateway <- PasswordHasherAdapter
```

Quando casos de uso diferentes precisarem do mesmo contrato, a interface pode
ser promovida para um contrato compartilhado do dominio. Essa promocao deve ser
resultado de repeticao real, nao de antecipacao.

## Tratamento de erros

Exceptions da aplicacao descrevem falhas do dominio ou do caso de uso, sem
conhecer codigos HTTP.

A infraestrutura e responsavel por traduzir essas falhas para o protocolo de
entrega. Por exemplo:

```text
EmailAlreadyRegisteredException -> HTTP 409
InvalidCredentialsException -> HTTP 401
```

## Estrategia de testes

O desenvolvimento segue TDD sempre que um comportamento puder ser expresso
antes de sua implementacao:

1. escrever um teste que descreva o comportamento e falhe;
2. implementar o minimo necessario para faze-lo passar;
3. refatorar preservando o comportamento coberto.

Os testes sao distribuidos por responsabilidade:

- entidades e value objects: testes unitarios;
- casos de uso: testes unitarios com gateways em memoria ou fakes;
- adaptadores Prisma e outras integracoes: testes de integracao;
- endpoints HTTP: testes end-to-end.

Testes devem verificar comportamento observavel, evitando acoplamento a
detalhes privados de implementacao.

## Composicao da aplicacao

Os modulos NestJS sao pontos de composicao. Eles conectam controllers, casos de
uso, gateways e adaptadores concretos.

Para preservar a independencia de `application`, casos de uso nao devem receber
decorators do NestJS. Quando necessario, o modulo pode instancia-los por meio
de providers com `useFactory`.

## Evolucao arquitetural

Esta arquitetura e um ponto de partida, nao uma estrutura imutavel. Mudancas
devem ser guiadas por casos de uso implementados e problemas observados.

Decisoes arquiteturais relevantes, suas alternativas e consequencias devem ser
registradas em ADRs dentro de `docs/adr`. O presente documento deve refletir a
arquitetura vigente, enquanto os ADRs preservam o historico das decisoes.
