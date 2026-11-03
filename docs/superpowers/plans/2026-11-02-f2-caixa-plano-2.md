# F2 Caixa — Plano 2 (custo fixo recorrente + vendas futuras + chaves de simulação) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A projeção do Caixa passa a incluir, marcados como *estimado*: o custo fixo que ainda não foi lançado, as vendas futuras (com o recebimento e o custo delas) e a comissão e os impostos das vendas, com as chaves "vendas futuras" e "% à vista" no topo da tela.

**Architecture:** Uma função nova `interno.caixa_fluxo` devolve todos os movimentos (o lançado de hoje + as fontes estimadas) com `origem` e `descricao`. `interno.caixa_movimentos` vira um atalho para a parte lançada (mesma assinatura). Os números que vêm do histórico (venda média, percentuais, perfil de recebimento) saem de `interno.caixa_perfil`, uma por loja. `tela_caixa` e `caixa_detalhe` ganham os parâmetros das chaves. A tela mostra ◐ nos valores com parte estimada.

**Tech Stack:** PostgreSQL (Supabase, plpgsql/sql), HTML+JS puro (`index.html`), Playwright em `..\_testes\caixa\` (fora do repositório).

**Spec:** `docs/superpowers/specs/2026-11-02-fluxo-caixa-design.md`: ler §5.2 (vendas futuras), §5.3 (fixo recorrente, custo das vendas futuras, comissão e imposto de vendas fechadas), §5.4 (chaves) e §11 ("nada em dobro"). Plano anterior: `docs/superpowers/plans/2026-11-02-f2-caixa-plano-1.md`. O que já existe está em `docs/HANDOFF.md` (Caixa) e nas migrations 41–46.

**Fora deste plano:** dívidas e KPI "Dívida total" (plano 3) · aba A receber, cobrança, foto semanal, Compras lendo a projeção (plano 4).

## Global Constraints

- **Repositório público:** nunca commitar valores financeiros da empresa (nem os percentuais calculados), nomes de clientes ou fornecedores, nem tokens. Os testes SQL usam **dados inventados** dentro de uma transação que termina em `raise exception 'OK-ROLLBACK'`.
- **Migrations em sequência:** a última é a **46**. Este plano usa **47, 48, 49 e 50**. Antes de cada uma, rodar `list_migrations` (projeto `vmpxssoyqfdnnyhnvkyl`) e conferir `docs/ALTERACOES.md`. Se o Luis já tiver usado o número, usar o próximo livre. Arquivo em `sql/migration_NN_nome.sql` com a versão final; aplicar com `apply_migration` (nome `NN_nome`).
- `apply_migration` volta "cancelled" se um texto entre aspas tiver `;`. Usar vírgula em mensagens e comentários dentro de strings.
- **Funções:** `security definer`, `set search_path to ''` (tudo qualificado), `#variable_conflict use_column` quando variável e coluna tiverem o mesmo nome.
- **Toda função nova** (public e interno) termina com `revoke execute on function X(args) from anon, public;` e `grant execute on function X(args) to authenticated;`. O conector pede aprovação para REVOKE e DROP: **avisar o Bruno antes** ("o conector vai pedir aprovação, pode aprovar, não apaga dado").
- Mudar a lista de parâmetros de uma função `public.*` exige `drop function` da assinatura antiga (senão o PostgREST acha duas e dá erro de ambiguidade). Só a Task 4 faz isso, e só em funções (nunca em tabelas). Evitar `DELETE`.
- "Hoje" no banco = `(now() at time zone 'America/Cuiaba')::date`. No front, `r.hoje` (vem do banco).
- Foto atual dos títulos = `ultima_importacao_id = interno.titulos_ultima_importacao(lado)`. Status e saldo em aberto = `interno.titulos_aberto(lado, hoje)` (migration 46).
- Tipos fora do a pagar: `Pre`, `Cre`, `Adi`. Fora do a receber: regex `^(cart|cr.dito|adiant|previs)` (sem diferenciar maiúsculas).
- **Valor positivo = entra, negativo = sai.** `origem` ∈ `lancado`, `fixo`, `vendas`, `custo_vendas`, `comissao_vendas`, `imposto_vendas`. Todo valor com origem ≠ `lancado` é *estimado*.
- Textos da tela em português simples; números com `brl0`/`milCmp`.
- Ao fim de cada task: linha no topo de `docs/ALTERACOES.md` e "Última migration" atualizada. Se criou tabela, coluna, RPC ou regra, atualizar `docs/HANDOFF.md` (seção Caixa). Commit com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (ou o modelo que executar) e push no `main`.
- Medir `tela_caixa(0)` com dados reais ao fim das Tasks 3 e 4: precisa ficar **abaixo de 5 s** (o limite do papel `authenticated` é 8 s; `set statement_timeout` dentro da função não aumenta esse limite).

## Regras de cálculo (decididas — vêm da spec e dos dados de 16/10)

| Item | Regra |
|---|---|
| Janela das vendas | 6 meses completos **antes do mês da última venda importada**: `fim = date_trunc('month', max(data_fechamento)) - 1 dia`, `ini = date_trunc('month', fim) - 5 meses`. Importação atrasada não puxa a média para baixo. |
| Venda média do mês | `(Σ vlr_liquido PED − Σ vlr_liquido DEV) / 6` da loja na janela (DEV vem positivo em `vendas_santri`). |
| Percentuais (sobre `Σ vlr_liquido` PED da janela) | `custo_compra` = Σ `custo_compra_santri` · `frete` = Σ `resultado->>'frete'` · `impostos` = Σ `resultado->>'impostos'` · `comissao` = Σ (`resultado->>'comissao'` + `resultado->>'rt'`) · `financeiro` = Σ `resultado->>'custo_financeiro'` (taxa do cartão antecipado). Campo nulo conta 0. |
| Perfil de recebimento | Para cada PED da janela, títulos a receber da foto atual com `loja_id` igual e `pedido_numero = numero`, tipo fora de `^(cr.dito|previs)`. Data em que o dinheiro entra: cartão → `emissao` (antecipado), `Baixado` → `pagamento`, senão `vencimento`. `k = least(greatest(data − data_fechamento::date, 0) / 7, 52)`. `receb[k] = Σ valor_documento em k / Σ vlr_liquido PED`. O que sobra (`1 − Σ receb`, se positivo) soma em `receb[0]` (venda sem título = à vista). Se `Σ receb > 1`, normaliza para 1. |
| Chave `% à vista` (`p_entrada_pct`, 0–100, null = perfil) | `receb[0] = pct/100`; os demais são multiplicados por `(1 − pct/100) / Σ demais` (se `Σ demais = 0`, `receb[0] = 1`). |
| Venda do mês M | `p_vendas = 'media'` (padrão) → venda média · `'meta'` → `Σ metas.faturamento` da loja em M com `usuario_id is null`, e se não houver, a média (marca `fonte='media'` no mês) · `'zero'` → 0. |
| Vendas futuras por semana | Venda do dia = venda do mês ÷ dias do mês. Semana w (segunda a domingo, a partir de `date_trunc('week', hoje)`) soma os dias de `hoje` até `fim_horizonte = date_trunc('month', hoje) + 12 meses − 1 dia`. Data da venda da semana: `d_w = greatest(ini_w, hoje)`. |
| Entrada das vendas futuras | `d_w + 7k` com `venda_w × receb[k]`, grupo `vendas_futuras`, origem `vendas`. Só datas ≤ `fim_horizonte`. |
| Custo das vendas futuras | Na data `d_w`: `−venda_w × (custo_compra + frete)` grupo `fornecedor` · `−venda_w × financeiro` grupo `outros`. Origem `custo_vendas`. |
| Comissão e impostos das vendas (fechadas + futuras) | Base do mês M = vendas reais de M (PED − DEV em `vendas_santri`) + vendas futuras estimadas de M. Para cada M de `mês(hoje) − 1` até o penúltimo mês do horizonte: comissão em M+1 = `base × comissao − lançado(comissoes_rt, M+1)`, no dia `caixa_parametros.dia_comissao`, grupo `comissoes_rt`, origem `comissao_vendas` · impostos em M+1 = `base × impostos − lançado(impostos, M+1)`, no dia `dia_impostos`, grupo `impostos`, origem `imposto_vendas`. Só entra se > 0,005. Data = `greatest(dia no mês, hoje)`. Com `p_vendas='zero'`, as vendas reais continuam gerando comissão e imposto. |
| Lançado de um grupo no mês | `lançado(g, M)` = Σ `valor_documento` dos títulos a pagar da foto atual da loja, qualquer situação, tipo fora de Pre/Cre/Adi, `interno.grupo_caixa(...) = g`, vencimento em M. |
| Custo fixo recorrente | Contas com `fixa` = `coalesce(plano_contas_classe.fixa, grupo_caixa_padrao(nome) in ('pessoal','fixo'))` e grupo fora de `fornecedor`, `impostos`, `comissoes_rt`, `divida`, `fora` (esses vêm das vendas ou das dívidas). Média = Σ `valor_documento` dos títulos a pagar da foto atual, tipo fora de Pre/Cre/Adi, vencimento nos 6 meses completos antes do mês de `hoje`, ÷ 6, por loja e `plano_codigo`. Dia = `least(round(avg(dia do vencimento)), 28)`. Para cada mês M do horizonte (0–11): `média − Σ valor_documento` da mesma conta e loja com vencimento em M (qualquer situação). Se > 0,005, sai em `greatest(make_date(M, dia), hoje)`, grupo da conta, origem `fixo`, `descricao` = nome da conta. |

## Review Focus

1. **Importação de vendas atrasada** (última venda em 16/10, hoje em novembro): a janela é Abr–Set, nunca um mês pela metade. Teste na Task 1 (venda de outubro define a janela).
2. **Loja sem nenhuma venda na janela:** `caixa_perfil` volta `null` e `caixa_fluxo` não gera vendas futuras nem erro. A comissão e o imposto de vendas reais ainda entram. Teste na Task 3 (loja 2).
3. **`p_vendas='meta'` com mês sem meta:** usa a média naquele mês e devolve `fonte='media'`. Teste na Task 3.
4. **Conta fixa com lançamento acima da média no mês:** a estimativa é 0, nunca negativa (não "devolve" dinheiro). Teste na Task 2 (janeiro).
5. **`p_entrada_pct` fora de 0–100 ou `p_vendas` desconhecido:** erro com mensagem clara, sem projeção errada. Teste na Task 4.

---

### Task 1: Perfil das vendas e datas de pagamento (migration 47)

**Files:**
- Create: `sql/migration_47_caixa_perfil.sql`
- Create: `sql/testes/teste_47_caixa_perfil.sql`

**Interfaces:**
- Produces:
  - Colunas novas em `public.caixa_parametros`: `dia_comissao smallint not null default 10 check (dia_comissao between 1 and 28)`, `dia_impostos smallint not null default 20 check (dia_impostos between 1 and 28)`.
  - `interno.caixa_perfil(p_loja smallint) returns jsonb` (stable): `{ini, fim, venda_media_mes, pct:{custo_compra, frete, impostos, comissao, financeiro}, receb:[53 números, soma 1]}` ou `null` quando a loja não tem PED na janela. Regras na tabela acima.
  - `public.salvar_datas_caixa(p_loja smallint, p_dia_comissao smallint, p_dia_impostos smallint) returns void`: exige `pode_ver_financeiro()` e loja em `lojas_tela(p_loja)`, faz upsert em `caixa_parametros`, dia fora de 1–28 → erro `'Dia inválido'`.

- [ ] **Step 1: Teste SQL** (`teste_47…`, usuário admin nos claims, como no `teste_42`). Dentro da transação: neutralizar as vendas reais com `update public.vendas_santri set data_fechamento = data_fechamento - interval '5 years';`, criar uma importação `receber` nova (vira a foto atual) e, na loja 1, um PED por mês no dia 15 de abr a set/2026 (`numero` `'TESTE-V4'`…`'TESTE-V9'`, `vlr_liquido` 6000, `custo_compra_santri` 3000, `resultado` `{"impostos":600,"comissao":300,"rt":0,"frete":0,"custo_financeiro":0}`), um DEV em 20/09 de 600 e um PED em 30/10/2026 de 6000 (só define a janela). Para cada PED de abr–set, um título a receber `Duplic`, `Aberto`, `pedido_numero` = número do pedido, `valor_documento` 3000, `vencimento` = fechamento + 14.

```sql
p := interno.caixa_perfil(1::smallint);
assert p->>'ini' = '2026-04-01' and p->>'fim' = '2026-09-30', 'FALHOU janela';
assert (p->>'venda_media_mes')::numeric = 5900, 'FALHOU venda media';
assert (p->'pct'->>'custo_compra')::numeric = 0.5 and (p->'pct'->>'impostos')::numeric = 0.1 and (p->'pct'->>'comissao')::numeric = 0.05, 'FALHOU pct';
assert jsonb_array_length(p->'receb') = 53, 'FALHOU tamanho receb';
assert round((p->'receb'->>0)::numeric, 4) = 0.5 and round((p->'receb'->>2)::numeric, 4) = 0.5, 'FALHOU perfil';
assert interno.caixa_perfil(2::smallint) is null, 'FALHOU loja sem venda';
perform public.salvar_datas_caixa(1::smallint, 5::smallint, 25::smallint);
assert (select dia_comissao from public.caixa_parametros where loja_id = 1) = 5, 'FALHOU dia comissao';
-- dia 31 → erro 'Dia inválido' (begin/exception)
```

- [ ] **Step 2: Rodar e ver falhar** com `execute_sql`. Esperado: `function interno.caixa_perfil(smallint) does not exist`.
- [ ] **Step 3: Escrever a migration** (colunas, `caixa_perfil`, `salvar_datas_caixa`, revoke/grant das duas funções).
- [ ] **Step 4: Aplicar e rodar o teste.** Esperado: `OK-ROLLBACK`. Rodar também `select interno.caixa_perfil(1::smallint), interno.caixa_perfil(2::smallint);` com dados reais e conferir **sem copiar os números para nenhum arquivo**: Σ `receb` = 1 e cada `pct` entre 0 e 1. Se algum `pct` passar de 0,5 (exceto `custo_compra`), parar e avisar o Bruno.
- [ ] **Step 5: Docs, commit e push.**

```bash
git add sql/migration_47_caixa_perfil.sql sql/testes/teste_47_caixa_perfil.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: perfil das vendas (média, percentuais, recebimento) e dias de comissão e impostos (migration 47)"
git push
```

---

### Task 2: Custo fixo recorrente e `caixa_fluxo` (migration 48)

**Files:**
- Create: `sql/migration_48_caixa_fluxo_fixo.sql`
- Create: `sql/testes/teste_48_caixa_fluxo_fixo.sql`
- Modify: `sql/testes/teste_44_tela_caixa.sql` e `sql/testes/teste_46_caixa_revisao.sql`, só se quebrarem (não devem: a saída de `caixa_movimentos` fica igual)

**Interfaces:**
- Consumes: `interno.titulos_aberto`, `interno.grupo_caixa`, `interno.grupo_caixa_padrao`, `public.plano_contas_classe`.
- Produces:
  - `interno.caixa_fluxo(p_lojas smallint[], p_hoje date, p_atrasados text, p_vendas text, p_entrada_pct numeric) returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean, descricao text)`. Nesta task: o corpo lançado atual de `caixa_movimentos` (migration 46), com `descricao = null`, mais o custo fixo recorrente (origem `fixo`, `titulo_id` null, `vencido` false). `p_vendas` e `p_entrada_pct` ainda não são usados.
  - `interno.caixa_movimentos(...)`: mesma assinatura, vira `select loja_id, data, grupo, valor, origem, titulo_id, vencido from interno.caixa_fluxo(p_lojas, p_hoje, p_atrasados, 'zero', null) where origem = 'lancado'`.

- [ ] **Step 1: Teste SQL** (`teste_48…`, hoje = `'2026-11-04'`). Importação `pagar` nova. Planos: `TESTE.ALUG` em `plano_contas_classe` com grupo `fixo` e `fixa=true`; `TESTE.ICMS` com grupo `impostos` e `fixa=true`. Títulos a pagar, loja 1, `Baixado`, `valor_documento` 1000, vencimento no dia 5 de mai a out/2026 para as duas contas. `TESTE.ALUG` também tem: `Aberto` de 400 em 05/11/2026 e `Aberto` de 1500 em 05/01/2027.

```sql
assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and descricao is not null and data = '2026-11-05') = -600, 'FALHOU nov = media - lancado';
assert (select valor from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and data = '2026-12-05') = -1000, 'FALHOU dez = media';
assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and data between '2027-01-01' and '2027-01-31'), 'FALHOU jan acima da media';
assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and grupo='impostos'), 'FALHOU fixa de imposto ignorada';
assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo') = 11, 'FALHOU 11 meses (nov..out, sem jan)';
-- nada em dobro: lançado aberto de nov (400) + fixo de nov (600) = média
assert (select -sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where data between '2026-11-01' and '2026-11-30' and (origem='fixo' or titulo_id in (select id from public.titulos_santri where plano_codigo='TESTE.ALUG'))) = 1000, 'FALHOU nao dobra';
-- caixa_movimentos continua só com o lançado
assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where origem <> 'lancado'), 'FALHOU movimentos so lancado';
```

- [ ] **Step 2: Rodar e ver falhar.** Esperado: `caixa_fluxo does not exist`.
- [ ] **Step 3: Escrever a migration** (`caixa_fluxo` com o lançado e o fixo, `caixa_movimentos` como atalho, revoke/grant de `caixa_fluxo`).
- [ ] **Step 4: Aplicar e rodar** `teste_48`, `teste_44` e `teste_46`. Esperado: os três `OK-ROLLBACK`.
- [ ] **Step 5: Docs, commit e push** (HANDOFF: a regra do fixo, em uma linha).

```bash
git add sql/migration_48_caixa_fluxo_fixo.sql sql/testes/ docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: custo fixo recorrente estimado (média 6 meses menos o lançado) em caixa_fluxo (migration 48)"
git push
```

---

### Task 3: Vendas futuras, custo, comissão e impostos das vendas (migration 49)

**Files:**
- Create: `sql/migration_49_caixa_vendas_futuras.sql`
- Create: `sql/testes/teste_49_caixa_vendas_futuras.sql`

**Interfaces:**
- Consumes: `interno.caixa_perfil` (Task 1), `interno.caixa_fluxo` (Task 2), `public.metas`, `public.vendas_santri`, `public.caixa_parametros.dia_comissao/dia_impostos` (padrão 10 e 20 quando a loja não tem linha).
- Produces: `interno.caixa_fluxo` com as origens `vendas`, `custo_vendas`, `comissao_vendas` e `imposto_vendas` (mesma assinatura da Task 2). `descricao`: `'Vendas futuras (média 6 meses)'`, `'Vendas futuras (meta)'`, `'Custo das vendas futuras'`, `'Taxa do cartão das vendas futuras'`, `'Comissão e RT das vendas de mm/aaaa'`, `'Impostos das vendas de mm/aaaa'`.
  - `interno.caixa_vendas_mes(p_loja smallint, p_hoje date, p_vendas text) returns table(mes date, venda numeric, fonte text)`: os 12 meses do horizonte (`fonte` ∈ `media`, `meta`, `zero`). A projeção usa para mostrar de onde veio a venda.

- [ ] **Step 1: Teste SQL** (`teste_49…`, hoje = `'2026-11-04'`): mesma preparação de vendas e títulos a receber do `teste_47` (vendas reais neutralizadas, importação `receber` nova). Importação `pagar` nova com um título `Aberto`, loja 1, plano `TESTE.COM` classificado `comissoes_rt`, `valor_documento` 100, vencimento 10/12/2026. Se a loja 1 tiver linha em `caixa_parametros`, fazer `update` para `dia_comissao=10, dia_impostos=20`. Esperado com `caixa_fluxo(array[1], h, 'triagem', 'media', null)`, sendo venda do dia de nov = 5900/30:

| Caso | Esperado |
|---|---|
| Entrada da semana 0 (04–08/11 = 5 dias) | 04/11, origem `vendas`, `round(valor,2) = 491.67` (5 × 5900/30 × 0,5) |
| Entrada k=2 da semana 0 | 18/11, `round(valor,2) = 491.67` |
| Custo da semana 0 | 04/11, origem `custo_vendas`, grupo `fornecedor`, `round(valor,2) = -491.67` |
| Comissão das vendas de out (6000 reais) | 10/11, `comissao_vendas`, −300 |
| Impostos das vendas de out | 20/11, `imposto_vendas`, −600 |
| Comissão das vendas de nov (27 dias estimados = 5310) menos o título de 100 | 10/12, `round(valor,2) = -165.50` |
| `'zero'` | nenhuma linha `vendas`/`custo_vendas`; comissão de 10/11 continua −300 |
| `'media'` com `p_entrada_pct = 100` | entrada de 04/11 = `983.33` e nada em 18/11 vindo da semana 0 |
| `'meta'` com meta só em dez/2026 (`metas` loja 1, `mes` 2026-12-01, `usuario_id` null, `faturamento` 31000) | venda de dez = 31000 (`fonte='meta'`) e nov com `fonte='media'` em `caixa_vendas_mes` |
| Loja 2 (sem vendas) | `caixa_fluxo(array[2], …, 'media', null)` sem linhas `vendas` e sem erro |
| Nada fora do horizonte | `max(data) <= '2027-10-31'` |

- [ ] **Step 2: Rodar e ver falhar** (as linhas de vendas não existem).
- [ ] **Step 3: Escrever a migration** (recriar `caixa_fluxo` com as quatro fontes novas, criar `caixa_vendas_mes`, revoke/grant). Gerar as semanas e os pares (w, k) com `generate_series`. `caixa_perfil` é chamada uma vez por loja (CTE `materialized` ou laço), nunca por linha.
- [ ] **Step 4: Aplicar e rodar** `teste_49`, `teste_48`, `teste_44` e `teste_46`. Esperado: todos `OK-ROLLBACK`. Medir `select count(*) from interno.caixa_fluxo(array[1,2]::smallint[], (now() at time zone 'America/Cuiaba')::date, 'triagem', 'media', null)` com dados reais: abaixo de 2 s.
- [ ] **Step 5: Docs, commit e push** (HANDOFF: as regras da tabela "Regras de cálculo", em resumo).

```bash
git add sql/migration_49_caixa_vendas_futuras.sql sql/testes/teste_49_caixa_vendas_futuras.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: vendas futuras com recebimento pelo perfil, custo, comissão e impostos das vendas (migration 49)"
git push
```

---

### Task 4: `tela_caixa` e `caixa_detalhe` com as chaves (migration 50)

**Files:**
- Create: `sql/migration_50_tela_caixa_chaves.sql`
- Create: `sql/testes/teste_50_tela_caixa_chaves.sql`
- Modify: `sql/testes/teste_44_tela_caixa.sql` (chamadas com os parâmetros novos, `p_vendas => 'zero'`, e vendas reais neutralizadas como no `teste_47`)

**Interfaces:**
- Consumes: `interno.caixa_fluxo`, `interno.caixa_perfil`, `interno.caixa_vendas_mes`.
- Produces (avisar o Bruno: **DROP FUNCTION** das três assinaturas antigas — `public.tela_caixa(smallint,text,date)`, `public.caixa_detalhe(smallint,text,date,date,text,date)`, `interno.caixa_projecao(smallint[],date,text)`):
  - `interno.caixa_projecao(p_lojas smallint[], p_hoje date, p_atrasados text, p_vendas text, p_entrada_pct numeric) returns jsonb`: igual à de hoje, lendo `caixa_fluxo`. Cada semana e cada mês ganha `grupos_est: {<grupo>: valor}` (só a parte com origem ≠ `lancado`). A semana 0 com vendas estimadas entra em `vendas_futuras`.
  - `public.tela_caixa(p_loja smallint, p_atrasados text default 'triagem', p_vendas text default 'media', p_entrada_pct numeric default null, p_hoje date default null) returns jsonb`: o formato atual mais `vendas_modo`, `entrada_pct`, `perfil: [{loja, ini, fim, venda_media_mes, receb0}]` (`receb0` = `receb[0]` depois da chave), `vendas_mes: [{loja, mes, venda, fonte}]`, e cada item de `por_loja` ganha `dia_comissao` e `dia_impostos` (padrão 10 e 20). `p_vendas` fora de `media/meta/zero` → `'Modo de vendas inválido'`. `p_entrada_pct` fora de 0–100 → `'Percentual à vista inválido'`.
  - `public.caixa_detalhe(p_loja smallint, p_grupo text, p_ini date, p_fim date, p_atrasados text default 'triagem', p_vendas text default 'media', p_entrada_pct numeric default null, p_hoje date default null) returns jsonb`: linhas atuais mais `origem` e `descricao`. As estimadas vêm com `titulo_id` null e `nome = descricao`. Ordenadas por `abs(valor) desc`.
  - Revoke/grant das três funções novas.

- [ ] **Step 1: Teste SQL** (`teste_50…`): preparação do `teste_49` mais uma conta bancária com saldo 10000 na loja 1.

```sql
r := public.tela_caixa(1::smallint, 'triagem', 'media', null, h);
assert r->>'vendas_modo' = 'media' and (r->'perfil'->0->>'venda_media_mes')::numeric = 5900, 'FALHOU perfil';
assert round((r->'semanas'->0->'grupos'->>'vendas_futuras')::numeric, 2) = 491.67, 'FALHOU vendas semana 0';
assert round((r->'semanas'->0->'grupos_est'->>'fornecedor')::numeric, 2) = -491.67, 'FALHOU grupos_est';
assert (r->'semanas'->0->'grupos_est'->>'clientes') is null, 'FALHOU lançado fora do grupos_est';
r2 := public.tela_caixa(1::smallint, 'triagem', 'zero', null, h);
assert (r2->'semanas'->0->'grupos'->>'vendas_futuras') is null, 'FALHOU zero';
assert jsonb_array_length(public.caixa_detalhe(1::smallint, 'comissoes_rt', '2026-11-09', '2026-11-15', 'triagem', 'media', null, h)) = 1, 'FALHOU detalhe estimado';
-- erros (begin/exception): p_vendas 'xpto' → 'Modo de vendas inválido'; p_entrada_pct 150 e -5 → 'Percentual à vista inválido'
-- anon sem EXECUTE: has_function_privilege('anon', 'public.tela_caixa(smallint,text,text,numeric,date)', 'execute') = false
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Escrever a migration** (drops das três assinaturas, recriar as três, revoke/grant).
- [ ] **Step 4: Aplicar e rodar** `teste_50`, `teste_49`, `teste_48`, `teste_46` e `teste_44` (já ajustado). Esperado: todos `OK-ROLLBACK`. Com dados reais, admin nos claims: `tela_caixa(0::smallint)` abaixo de 5 s. Conferir pela API, com a chave publicável, que anon recebe `permission denied` em `tela_caixa`.
- [ ] **Step 5: Docs, commit e push.** HANDOFF: as assinaturas novas. A tela atual continua funcionando, porque chama por nome (`{p_loja, p_atrasados}`) e os parâmetros novos têm padrão. Conferir abrindo o Playwright atual antes do push.

```bash
git add sql/migration_50_tela_caixa_chaves.sql sql/testes/ docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: tela_caixa e caixa_detalhe com as chaves de vendas futuras e % à vista (migration 50)"
git push
```

---

### Task 5: Tela Caixa — chaves, ◐ estimado, detalhe e dias de pagamento

**Files:**
- Modify: `index.html` (bloco `// ---------- CAIXA ----------`: `CX`, `CX_ENTRADAS`, `abaProjecaoCx`, `detalheCx`, `abaSaldosCx`, `telaCaixaJ`)
- Modify (fora do repo): `..\_testes\caixa\teste_caixa.mjs`, `gerar_mock.mjs`, `mock_tela_caixa.json`

**Interfaces:**
- Consumes: `tela_caixa(p_loja, p_atrasados, p_vendas, p_entrada_pct)`, `caixa_detalhe(... p_vendas, p_entrada_pct)`, `salvar_datas_caixa(p_loja, p_dia_comissao, p_dia_impostos)`. `tela_caixa` devolve `por_loja[].dia_comissao/dia_impostos` (Task 4).
- Produces: estado `CX.vendas` (`'media'` padrão) e `CX.entrada` (`null` ou número). O cache é invalidado quando qualquer chave muda.

- [ ] **Step 1: Atualizar o mock e o teste Playwright.** Mock com `grupos_est`, `vendas_futuras`, `perfil` e `vendas_mes` (números inventados). Asserts:
  - a chave "Vendas futuras: Média 6 meses | Meta | Sem vendas novas" existe e clicar em "Meta" chama `tela_caixa` com `p_vendas='meta'`;
  - o campo "% à vista" com `80` chama `tela_caixa` com `p_entrada_pct=80`, e vazio manda `null`;
  - a linha "Vendas futuras" aparece em "Entra";
  - uma célula com `grupos_est` ≠ 0 mostra `◐` e tem `title` "inclui valor estimado";
  - no detalhe, uma linha com `titulo_id` null mostra "estimado" na coluna Triagem e a `descricao` como nome;
  - na aba Saldos, mudar "Dia de pagar comissão" para 5 chama `salvar_datas_caixa` com `p_dia_comissao=5`;
  - em 390 px: `scrollWidth <= 390`.
- [ ] **Step 2: Rodar e ver falhar** (`node teste_caixa.mjs`).
- [ ] **Step 3: Implementar.**
  - Cabeçalho: ao lado da chave "Atrasados", a chave "Vendas futuras" (`data-cxven`) e um `<input id="cxEntrada" inputmode="decimal" placeholder="% à vista">` (aplica no `change`; vazio = perfil).
  - `CX_ENTRADAS` passa a `[['clientes','Clientes'],['vendas_futuras','Vendas futuras'],['outros_entrada','Outras entradas']]`.
  - `cel()` acrescenta ` ◐` e `title="inclui valor estimado"` quando `c.grupos_est?.[g]` ≠ 0.
  - Detalhe: coluna Triagem = `'estimado'` quando `titulo_id` é null. `p_vendas` e `p_entrada_pct` vão junto na chamada.
  - Aba Saldos: em cada loja, ao lado do caixa mínimo, "Dia de pagar comissão" e "Dia dos impostos" (`input type=number min=1 max=28`), no `change` → `salvar_datas_caixa`.
  - Nota no rodapé da Projeção (texto fixo, trocar o atual): "◐ = inclui valor estimado. Lançado: o que está no Santri. Estimado: custo fixo ainda não lançado (média de 6 meses menos o que já foi lançado no mês), vendas futuras (média de 6 meses ou meta) com o recebimento no ritmo dos últimos 6 meses, o custo dessas vendas, e comissão e impostos das vendas pagos no mês seguinte. Cartão não entra no a receber porque já foi antecipado. Parcelas de dívida fora do Santri ainda não entram." Acrescentar uma linha por loja com `perfil`: "LOJA: venda média R$ X/mês (mm/aa a mm/aa), Y% recebido na semana da venda".
- [ ] **Step 4: Rodar Playwright e `node --check`** (extrair o maior `<script>` do `index.html` para um arquivo temporário). Esperado: `TUDO OK` e sem saída do `node --check`.
- [ ] **Step 5: Docs, commit e push.** Em `docs/PROXIMOS_PASSOS.md` §0, F2: "plano 2 construído". Em "Pendências" do plano 1, acrescentar: "Comissão: se a comissão (tarefa 2 do Bruno) for paga dentro da folha, o salário fixo recorrente já a inclui. Nesse caso, zerar `comissao` no perfil para não contar em dobro" e "Conferir se `frete` do resultado é frete de compra (vai para fornecedor) e se `custo_compra_santri` já inclui esse frete".

```bash
git add index.html docs/ALTERACOES.md docs/HANDOFF.md docs/PROXIMOS_PASSOS.md
git commit -m "Tela Caixa: chaves de vendas futuras e % à vista, valores estimados marcados, dias de comissão e impostos"
git push
```

## Ao terminar o plano

Avisar o Bruno em poucas linhas: a projeção agora mostra o ano inteiro com custo fixo e vendas. Para conferir:
1. Chave em "Sem vendas novas": mostra o pior caso.
2. Os percentuais do perfil, na nota da Projeção, devem ser parecidos com os que ele conhece.
3. Se a comissão for paga na folha, avisar.
