# Pedidos automáticos pelo Santri — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tela Pedidos (`#/pedidos`) passa a se montar sozinha com as vendas do Santri e os relatórios já importados (pagamento, compra, nota, entrega), sem depender de o vendedor lançar o pedido. Os pedidos em aberto mostram o que precisa ser atualizado (datas). O vendedor pode corrigir as datas no sistema, com alerta para corrigir também no Santri. O "Lançar" já vem preenchido com tudo o que o sistema sabe.

**Architecture:** Tabela nova `pedido_datas` (datas que o vendedor informa, por loja + número do Santri) com histórico em `pedido_datas_eventos`, gravada só pela RPC `salvar_datas_pedido`. A função `interno.pedidos_mercadoria` resume, por pedido, em que pé estão os itens (falta comprar / na fábrica / faturado / chegou), com a mesma ligação venda → compra da `tela_compras` (migration 57d). A RPC `tela_pedidos` junta isso com pagamento (`interno.pagamento_pedidos`), entregas (`entregas_santri`, `entregas_pendentes`) e `pedido_datas`, e devolve etapa, previsão e alertas de cada pedido. O front reescreve `telaPedidos()` e completa o pré-preenchimento do `lancarDoSantri()`.

**Tech Stack:** PostgreSQL (Supabase, plpgsql/sql), HTML+JS puro (`index.html`), Playwright em `..\_testes\` (fora do repositório).

**Spec:** a seção "Desenho" abaixo, combinada com o Bruno em 03/11/2026. Ler também `docs/HANDOFF.md` (Decisões, Testes) e a `tela_compras` atual no banco (`pg_get_functiondef('public.tela_compras(smallint)'::regprocedure)`): CTEs `vd`, `vi`, `ci`, `lig_cand`, `lig_pick`, `lig`, `st`.

**Fora deste plano:** prazo e cobrança de guarda (regra em definição), tela Entregas, mudar a `tela_compras` para usar a função nova.

## Desenho (Bruno, 03/11/2026)

| # | Decisão |
|---|---|
| 1 | A tela não depende de lançamento: toda venda `PED` do Santri (sem venda direta) dos **últimos 365 dias** aparece, com a etapa calculada pelos relatórios. Entregues aparecem só se a última entrega foi nos últimos 30 dias (filtro "mostrar entregues"). |
| 2 | **Data de entrega nos dois lugares.** O vendedor pode atualizar no sistema ou no Santri. Se a data do sistema existe e é diferente da do Santri (ou o Santri não tem data), o pedido mostra o alerta **"Atualize no Santri"**. Sem data no sistema, vale a do Santri. Previsão usada = `coalesce(sistema, Santri)`. |
| 3 | "Data que o cliente precisa" só existe no sistema. |
| 4 | **"Lançar" pré-preenchido**: além do que já vem hoje (número, cliente, vendedor, itens, valores), vêm a previsão de entrega (sistema, senão Santri), a data que o cliente precisa e, como dica ao lado da condição, as formas de pagamento já recebidas no Santri. O vendedor só confere e completa (condição, arquiteto, Goyases). |
| 5 | Quem altera datas: `gerente`, `logistica`, `direcao`, `admin` em qualquer pedido das lojas que vê; `vendedor` só nos dele (`usuarios.nome_santri` = `vendas_santri.vendedor_santri`, comparando `upper(trim())`). Vendedor sem `nome_santri` (hoje são todos) altera os pedidos da própria loja e vê a loja toda, como a lista de pendências atual. |

Registrar as decisões 1, 2, 3 e 5 em `docs/HANDOFF.md` › Decisões na Task 1 (a 2 já foi registrada em 03/11/2026: conferir e completar).

### Etapa do pedido (primeira regra que casar)

| Etapa (`etapa`) | Regra |
|---|---|
| `entregue` | `entrega = 'entregue'` |
| `saindo` | `entrega = 'gerada'` (entrega gerada, aguardando carregamento) |
| `aguardando_pagamento` | algum item `falta` e `pago = 0` (compra só é liberada com pagamento — HANDOFF › Decisões) |
| `falta_comprar` | algum item `falta` |
| `na_fabrica` | algum item comprado sem nota |
| `faturado` | algum item com nota de entrada `Aberta` (fábrica faturou, a caminho) |
| `pronto` | tudo chegou (nota `Baixada`) ou é estoque: falta só entregar |

### Situação da entrega (`entrega`), por loja + pedido

`eg` = `entregas_santri` ativas do pedido; `ep` = `entregas_pendentes` da **última importação** (`importacao_id = max(importacao_id)` da tabela inteira: o relatório traz as duas lojas juntas).

| `entrega` | Regra |
|---|---|
| `parcial` | tem linha em `ep` e alguma `eg` com `status_entrega ilike 'Entrega total'` |
| `agendada` | tem `ep` com `secao = 'pendente'` |
| `sem_agendamento` | tem `ep` só com `secao = 'sem_agendamento'` |
| `gerada` | sem `ep`, alguma `eg` com `status_manifesto ilike 'Aguardando%'` |
| `entregue` | sem `ep`, alguma `eg` com entrega total |
| `sem_info` | nenhuma das anteriores |

`prev_santri` = `max(ep.prev_maior)`. `entregue_em` = `max(coalesce(eg.concluida_em::date, eg.data_entrega))`.

### Situação de cada item (mercadoria)

Mesma ligação venda → compra da `tela_compras` (57d): compra da mesma loja, `data_cadastro` entre fechamento − 3 e fechamento + 150, mesmo código (prioridade 0) ou mesma família e marca (prioridade 1), a mais antiga, desempate pelo menor número. Compras com `status <> 'Cancelado'`, itens ativos. Depois:

- `fila_compra_marcas` com situação `venda_direta`/`nao_comprar` → item ignorado (não conta).
- Sem compra ligada e (`fila_compra_marcas.situacao = 'estoque'` ou `interno.e_marca_estoque(marca)`) → `chegou`.
- Sem compra ligada e não estoque (e sem marca `comprado`) → `falta`.
- Com compra ligada (ou marca `comprado`): nota pela `entradas_santri_compras` (`ativo`, `compra_numero` = número da compra, mesma loja da `entradas_santri`): alguma `Baixada` → `chegou`; senão alguma `Aberta` → `faturado`; senão → `fabrica`. Marca `comprado` sem compra ligada → `fabrica`.

### Alertas (`alertas`, só em pedido não entregue)

| Código | Regra | Texto na tela |
|---|---|---|
| `sem_previsao` | previsão usada é nula | Sem previsão de entrega |
| `previsao_vencida` | previsão usada < hoje | Previsão vencida |
| `atualizar_santri` | `prev_sistema` não nula e diferente de `prev_santri` (ou `prev_santri` nula) | Atualize no Santri |
| `precisa_antes` | `precisa` não nula e (previsão nula ou `precisa` < previsão) | Cliente precisa antes |
| `parado_60` | fechamento < hoje − 60 | Mais de 60 dias |
| `nao_lancado` | `vendas_santri.pedido_id` nulo | Não lançado |

## Global Constraints

- **Repositório público:** nunca commitar valores, nomes de clientes, vendedores ou fornecedores, nem tokens. Testes SQL usam **dados inventados** (`'TESTE-…'`, números `'999990'`…) numa transação que termina em `raise exception 'OK-ROLLBACK'`.
- **Migrations:** a última é a **58**. Este plano usa **59** (Task 1) e **60** (Task 2). Antes de cada uma: `list_migrations` (projeto `vmpxssoyqfdnnyhnvkyl`) e `docs/ALTERACOES.md`; se o Luis usou o número, usar o próximo livre. Arquivo `sql/migration_NN_nome.sql` com a versão final, aplicado com `apply_migration`.
- `apply_migration` volta "cancelled" se um texto entre aspas tiver `;`: usar vírgula. O conector recusa `DROP`/`DELETE`: nenhuma task usa.
- **Toda função nova** termina com `revoke execute on function X(args) from anon, public;` e `grant execute on function X(args) to authenticated;` (avisar o Bruno que o conector pede aprovação para o REVOKE). Depois, `get_advisors` (security) sem aviso de `anon`.
- Funções: `security definer`, `set search_path to ''`, tudo qualificado, `#variable_conflict use_column` em plpgsql com nome repetido.
- **Desempenho (memória do projeto, migrations 57–57d):** filtrar cedo, nunca chamar `interno.titulos_ultima_importacao(...)` ou "última importação" linha a linha, nunca varrer venda × compra (usar junção por código/família como `lig_cand`). `tela_pedidos(0)` com dados reais **abaixo de 2 s** (rodar duas vezes: a primeira pode vir com cache frio).
- "Hoje" = `(now() at time zone 'America/Cuiaba')::date`. No front, usar `hojeLocalJ()` (não `hoje()`, que usa UTC).
- Número do pedido = texto só com dígitos, igual a `vendas_santri.numero` e `entregas_pendentes.pedido` (ex.: `'15830'`). `pedidos.numero_santri` tem pontos (`fmtNum`): converter com `replace(numero_santri, '.', '')` quando precisar.
- Ao fim de cada task: linha no topo de `docs/ALTERACOES.md` (+ "Última migration"), `docs/HANDOFF.md` (tabela/RPC/tela nova), commit com `Co-Authored-By: <modelo que executar> <noreply@anthropic.com>` e push no `main`.

## Review Focus

1. **Pedido com duas entregas** (uma entregue, outra pendente) deve aparecer como `parcial` e continuar em aberto, não como `entregue`. Teste na Task 2.
2. **Mesma numeração nas duas lojas** (o número do pedido não é único entre PVA e RV): toda junção usa `loja_id` + número. Teste na Task 2 com o mesmo número inventado nas lojas 1 e 2.
3. **Vendedor tentando mudar a data de pedido de outro vendedor** (quando tem `nome_santri`) deve receber erro, e o de outra loja também. Teste na Task 1.
4. **Data apagada no sistema** (salvar com `null`) volta a usar a do Santri e some o alerta `atualizar_santri`. Teste na Task 1 (gravação) e na Task 2 (alerta).
5. **Tela no celular (390 px)** com 300+ pedidos: sem rolagem horizontal da página, edição de data utilizável. Teste na Task 3.

---

### Task 1: Datas do pedido no sistema (migration 59)

**Files:**
- Create: `sql/migration_59_pedido_datas.sql`
- Modify: `docs/HANDOFF.md` (Decisões + seção da tela Pedidos), `docs/ALTERACOES.md`

**Interfaces:**
- Produces:
  - Tabela `public.pedido_datas(loja_id smallint references lojas, numero text, previsao_entrega date, data_cliente_precisa date, atualizado_por uuid references usuarios, atualizado_em timestamptz default now(), primary key (loja_id, numero))`.
  - Tabela `public.pedido_datas_eventos(id bigint identity pk, loja_id smallint, numero text, campo text check in ('previsao_entrega','data_cliente_precisa'), de date, para date, por uuid, em timestamptz default now())`.
  - RLS de leitura nas duas: usuário ativo e loja visível (`(select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())`). Sem policy de escrita (só pela RPC).
  - `public.salvar_datas_pedido(p_loja smallint, p_numero text, p_previsao date, p_precisa date) returns void`: grava os dois campos (null apaga), um evento por campo que mudou.
  - `public.dados_lancar_pedido(p_loja smallint, p_numero text) returns jsonb`: `{previsao_sistema, previsao_santri, precisa, formas}` (`formas` = `interno.pagamento_pedidos().formas` do número, texto ou null).

- [ ] **Step 1: Escrever o teste (bloco SQL, dados inventados, OK-ROLLBACK)** em `..\_testes\pedidos\teste_59.sql`, com estas checagens, cada uma com `raise exception` própria se falhar:
  - inserir `vendas_santri` inventadas: `('TESTE-A', loja 1, numero '999991', vendedor_santri 'TESTE VENDEDOR UM')` e `('TESTE-B', loja 1, numero '999992', vendedor_santri 'TESTE VENDEDOR DOIS')` (tipo `PED`, demais campos obrigatórios com valores mínimos);
  - como usuário `gerente` da loja 1 (`set_config('request.jwt.claims', …)` com um usuário inventado inserido em `usuarios`): `salvar_datas_pedido(1, '999991', '2030-09-10', '2030-09-05')` → `pedido_datas` tem a linha e `pedido_datas_eventos` tem **2** eventos;
  - salvar de novo só mudando a previsão → **1** evento novo (`campo = 'previsao_entrega'`, `de = '2030-09-10'`);
  - salvar com `p_previsao = null` → `previsao_entrega` nula na tabela;
  - como `vendedor` com `nome_santri = 'TESTE VENDEDOR UM'`: salvar em `'999992'` → erro `'Pedido de outro vendedor'`; em `'999991'` → ok;
  - como `vendedor` da loja 2: salvar em loja 1 → erro (`interno.lojas_tela` recusa);
  - número inexistente `'999999'` → erro `'Pedido não encontrado no Santri'`;
  - como `compras` → erro `'Sem permissão para alterar datas'`;
  - `dados_lancar_pedido(1, '999991')` devolve `precisa = '2030-09-05'`.

- [ ] **Step 2: Rodar o teste e ver falhar** (`execute_sql` com o bloco): esperado erro de função/tabela inexistente.

- [ ] **Step 3: Escrever `sql/migration_59_pedido_datas.sql`** com as tabelas, RLS, as duas RPCs (regras da decisão 5 e as mensagens acima), revoke/grant. Aplicar com `apply_migration` (`59_pedido_datas`).

- [ ] **Step 4: Rodar o teste**: esperado só `OK-ROLLBACK`. `get_advisors` security sem `anon` nas funções novas.

- [ ] **Step 5: Docs e commit.** HANDOFF › Decisões: decisões 1, 2, 3 e 5 do Desenho. HANDOFF › tela Pedidos: tabelas e RPCs. ALTERACOES (migration 59). Commit `Pedidos: datas de entrega no sistema com histórico (migration 59)` e push.

### Task 2: `tela_pedidos` (migration 60)

**Files:**
- Create: `sql/migration_60_tela_pedidos.sql`
- Modify: `docs/HANDOFF.md`, `docs/ALTERACOES.md`

**Interfaces:**
- Consumes: `pedido_datas` (Task 1).
- Produces:
  - `interno.pedidos_mercadoria(p_lojas smallint[], p_desde date) returns table(loja_id smallint, numero text, itens int, falta int, fabrica int, faturado int, chegou int)`, regras de "Situação de cada item".
  - `public.tela_pedidos(p_loja smallint) returns jsonb`:
    ```
    { hoje, lojas, atualizado: {vendas, entregas, compras, entradas, baixas},   -- max(criado_em) das importações aplicadas
      pedidos: [ { venda_id, loja_id, numero, fechamento, dias, cliente, vendedor, valor, pago_pct, lancado, capa_id,
                   itens, falta, fabrica, faturado, chegou, etapa, entrega, entregue_em,
                   prev_sistema, prev_santri, previsao, precisa, alertas: [text] } ] }
    ```
    `pago_pct` = `round(100 * least(pago, valor) / valor)`; `capa_id` = `pedidos.capa_id` via `vendas_santri.pedido_id`; `previsao` = `coalesce(prev_sistema, prev_santri)`. Ordem: `fechamento` crescente. Inclui pedidos com `etapa <> 'entregue'` e os entregues com `entregue_em >= hoje - 30`.
  - Acesso: `interno.lojas_tela(p_loja)`; papel `vendedor` com `nome_santri` → só as vendas dele.

- [ ] **Step 1: Escrever o teste** em `..\_testes\pedidos\teste_60.sql` (dados inventados, hoje real, OK-ROLLBACK). Cenários, cada um checado no JSON de `tela_pedidos(1)` / `tela_pedidos(0)`:
  - venda `'999991'` loja 1 sem pagamento, item sem compra, marca não estoque → `etapa = 'aguardando_pagamento'`, alertas contém `sem_previsao`, `nao_lancado`;
  - mesma venda com baixa inventada (pago > 0) → `falta_comprar`;
  - venda `'999992'` com compra ligada pelo código e nota `Aberta` → `faturado`; com nota `Baixada` e `entregas_pendentes` pendente com `prev_maior = hoje + 5` → `pronto`, `entrega = 'agendada'`, `previsao = hoje + 5`, sem `atualizar_santri`;
  - `pedido_datas` de `'999992'` com previsão `hoje + 8` → `previsao = hoje + 8` e alerta `atualizar_santri`; apagar → alerta some;
  - venda `'999993'` com uma `entregas_santri` "Entrega total" e outra linha em `entregas_pendentes` → `entrega = 'parcial'`, não entregue;
  - mesmo número `'999993'` na loja 2 sem nada → aparece separado, `etapa` própria (Review Focus 2);
  - `data_cliente_precisa = hoje + 2` com previsão `hoje + 8` → `precisa_antes`.

- [ ] **Step 2: Rodar e ver falhar** (função inexistente).

- [ ] **Step 3: Escrever a migration 60** (`interno.pedidos_mercadoria` com as CTEs de ligação no padrão de `lig_cand`/`lig_pick` da 57d; `public.tela_pedidos` com uma CTE por fonte, cada uma filtrada por loja e janela antes de juntar). Aplicar (`60_tela_pedidos`).

- [ ] **Step 4: Rodar o teste** → só `OK-ROLLBACK`. Medir com dados reais: `explain (analyze, timing off, summary on)` de `tela_pedidos(0)` no padrão do HANDOFF › Testes (simulando um usuário `direcao`), duas vezes: **< 2 s**. `get_advisors` security.

- [ ] **Step 5: Docs e commit.** HANDOFF (RPC e regras de etapa/entrega/alertas), ALTERACOES (60). Commit `Pedidos: tela_pedidos calcula etapa, entrega e alertas pelo Santri (migration 60)` e push.

### Task 3: Tela Pedidos nova (front)

**Files:**
- Modify: `index.html`: reescrever `telaPedidos()` (hoje perto da linha 1370) e o estado `PDF_`; remover o cartão de `pendenciasSantri()` desta tela (antes de apagar a função, `grep` por `pendenciasSantri` e `PEND_SANTRI`: se não houver outro uso, apagar; `abrirParaLancar` continua).
- Test: `..\_testes\pedidos\tela_pedidos.spec.js` (Playwright, padrão HANDOFF › Testes: supabase roteado, `tela_pedidos` e `salvar_datas_pedido` simulados com JSON inventado).

**Interfaces:**
- Consumes: `tela_pedidos(p_loja)` (Task 2), `salvar_datas_pedido` (Task 1), `abrirParaLancar(venda_id)` (existente).
- Produces: `async function telaPedidos()`, estado `PDF_ = {etapa:null, alerta:null, busca:'', entregues:false, editando:null}`. Loja vem de `lojaJ()` (o "Ver loja" da barra lateral), não mais de um seletor próprio.

Layout (padrão da tela de Compras: números que norteiam no topo, trabalho embaixo):
1. Título "Pedidos e mercadoria" + `fonteJ` com a data das importações (`atualizado`).
2. Indicadores clicáveis por etapa (quantidade e valor), na ordem: Aguardando pagamento, Falta comprar, Na fábrica, Faturado (a caminho), Pronto para entregar, Saindo. Clicar filtra; clicar de novo limpa.
3. Indicadores de alerta (quantidade): Sem previsão, Previsão vencida, Atualize no Santri, Cliente precisa antes, Não lançados. Clicar filtra.
4. Busca (pedido, cliente, vendedor) e caixa "Mostrar entregues (30 dias)".
5. Tabela: Pedido (+ código da loja) · Cliente · Vendedor (primeiro nome) · Fechamento · Dias (vermelho > 60) · Pagamento (`pillJ`: pago / pago N% / sem pagamento) · Mercadoria (nome da etapa + "N de M itens chegaram") · Entrega (situação + previsão `dd/mm` com "(sistema)" ou "(Santri)") · Cliente precisa · Alertas (pílulas com os textos da tabela de alertas) · Ações: **Datas** (abre uma linha logo abaixo com dois `input type=date`, previsão e cliente precisa, já preenchidos, e Salvar/Cancelar; ao salvar chama `salvar_datas_pedido`, `toast('Datas salvas')`, recarrega; se a previsão salva ficou diferente da do Santri, o toast é `'Datas salvas. Atualize a previsão também no Santri.'`) e **Lançar** (se `!lancado`, chama `abrirParaLancar(venda_id)`) ou **Capa** (se `capa_id`, abre `#/capa/<id>` na aba `ped`).
6. Nota de rodapé curta explicando etapa e "Atualize no Santri".

- [ ] **Step 1: Escrever o teste Playwright** com JSON simulado de 4 pedidos (um por etapa principal, um com `atualizar_santri`): checa os números dos indicadores, o filtro por clique, a pílula "Atualize no Santri", a edição de datas (chama `salvar_datas_pedido` com `p_loja`, `p_numero` e as datas escolhidas, e mostra o toast com o aviso do Santri) e, a 390 px, `document.documentElement.scrollWidth <= 390`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** `telaPedidos()` conforme o layout.
- [ ] **Step 4: Rodar o teste e `node --check`** no script extraído → passa. Abrir no navegador local com o JSON simulado e tirar print desktop e 390 px.
- [ ] **Step 5: Commit** `Tela Pedidos: monta sozinha pelo Santri, alertas e datas editáveis` + ALTERACOES + HANDOFF (tela) e push.

### Task 4: "Lançar" pré-preenchido e datas sincronizadas

**Files:**
- Modify: `index.html`: `lancarDoSantri()` / `revisarPedido()` (perto das linhas 1090–1178) e `salvarPedido()`; e qualquer outro ponto que grave `pedidos.previsao_entrega` ou `pedidos.data_cliente_precisa` (`grep -n "previsao_entrega\|data_cliente_precisa" index.html`).
- Test: `..\_testes\pedidos\lancar.spec.js`.

**Interfaces:**
- Consumes: `dados_lancar_pedido(p_loja, p_numero)` e `salvar_datas_pedido(...)` (Task 1).

- [ ] **Step 1: Escrever o teste Playwright**: com `dados_lancar_pedido` simulado devolvendo `{previsao_sistema:null, previsao_santri:'2030-09-20', precisa:'2030-09-15', formas:'PIX, Cartão de crédito'}`, abrir o lançamento de uma venda do Santri e conferir: `#pPrev` = `2030-09-20`, `#pPrecisa` = `2030-09-15`, o texto "Pagamentos já recebidos no Santri: PIX, Cartão de crédito" aparece junto da condição; ao confirmar, `salvar_datas_pedido` é chamada com as datas do formulário. Com `previsao_sistema:'2030-09-25'`, `#pPrev` = `2030-09-25`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar**: em `revisarPedido`, quando `santri` vier, buscar `dados_lancar_pedido` e preencher `#pPrev` (`previsao_sistema` senão `previsao_santri`), `#pPrecisa` e a dica de formas. Em `salvarPedido` (e nos outros pontos achados pelo grep), depois de gravar, chamar `salvar_datas_pedido` com a loja, o número sem pontos e as datas.
- [ ] **Step 4: Rodar os testes das Tasks 3 e 4 e `node --check`** → passam.
- [ ] **Step 5: Commit** `Lançar pedido: datas e formas de pagamento já preenchidas pelo Santri` + ALTERACOES e push. Avisar o Bruno: para cada vendedor ver só os próprios pedidos, a direção precisa preencher `nome_santri` no cadastro de usuários (hoje nenhum tem).
