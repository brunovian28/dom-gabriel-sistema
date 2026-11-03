# F2 Caixa — Plano 1 (base comum + saldos + projeção do lançado + triagem) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a tela "Caixa" da diretoria com saldo por conta bancária, projeção de 13 semanas + 12 meses só com o que está lançado no Santri, atrasados a pagar com triagem, e a base comum (classificação do plano de contas + status único do título) que a F1 também vai usar.

**Architecture:** Tudo no Supabase como migrations numeradas (41–44) com funções `SECURITY DEFINER`. Uma função interna `interno.caixa_movimentos` gera a lista de movimentos (data, grupo, valor ±); a RPC `tela_caixa` só agrega essa lista em semanas e meses. Os planos seguintes (fixo recorrente, vendas futuras, dívidas, cobrança) acrescentam fontes dentro de `caixa_movimentos` sem mudar o formato. O front é o `index.html` único, com uma rota nova `#/caixa` no estilo das telas de setor (`indCmp`, `abasJ`, `listaJ`).

**Tech Stack:** PostgreSQL (Supabase, plpgsql), HTML+JS puro com supabase-js v2, Playwright (testes de tela, fora do repositório).

**Spec:** `docs/superpowers/specs/2026-11-02-fluxo-caixa-design.md` (ler §3.1, §3.2 abas 1/2/5, §4, §5.1–5.3, §6, §7). Base comum também descrita na F1: `docs/superpowers/specs/2026-11-01-dre-gerencial-design.md` §6–7.

**Fora deste plano (planos 2–4):** fixo recorrente, vendas futuras e chaves de vendas/% entrada (plano 2) · dívidas e KPI "Dívida total" (plano 3) · aba A receber, cobrança do vendedor, foto semanal, Compras lendo a projeção (plano 4).

## Global Constraints

- **Repositório público:** nunca commitar valores financeiros da empresa, nomes de clientes/fornecedores, tokens. Testes SQL usam **dados inventados** inseridos dentro de uma transação que termina em `raise exception 'OK-ROLLBACK'`.
- **Migrations em sequência:** antes de cada uma, rodar `list_migrations` (projeto `vmpxssoyqfdnnyhnvkyl`) e conferir `docs/ALTERACOES.md`; se o Luis já usou o número, usar o próximo livre e ajustar os nomes deste plano. Arquivo em `sql/migration_NN_nome.sql` com a versão final; aplicar com `apply_migration` (nome `NN_nome`).
- `apply_migration` volta "cancelled" se um texto entre aspas tiver `;` — use vírgula em mensagens e comentários dentro de strings.
- Funções: `language plpgsql|sql`, `security definer`, `set search_path to ''` (tudo qualificado: `public.`, `interno.`), `#variable_conflict use_column` quando variável e coluna tiverem o mesmo nome.
- **Toda função `public.*` nova termina com** `revoke execute on function public.X(args) from anon, public;` **seguido de** `grant execute on function public.X(args) to authenticated;`. O `alter default privileges` da migration 40 só acrescenta permissão e não tira o EXECUTE que PUBLIC recebe ao criar a função (descoberto na migration 45). Não mudar o default global de privilégios: quebraria as funções `interno.*` usadas nas policies de RLS. O conector pede aprovação para REVOKE: avisar o Bruno. Evitar `DROP` e `DELETE` nas migrations.
- RLS em toda tabela nova; policy de leitura com `(select interno.pode_ver_financeiro())` e loja via `(select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())`. Escrita só por RPC.
- Sem DELETE: desativar com `ativo=false`; mudanças de triagem guardam histórico.
- "Hoje" no banco = `(now() at time zone 'America/Cuiaba')::date`. No front, `hojeLocalJ()` (nunca `new Date().toISOString()`).
- Foto atual dos títulos = `ultima_importacao_id = interno.titulos_ultima_importacao(lado)` (uma importação cobre as duas lojas). `titulos_santri.id` é estável entre importações (unique `lado, codigo`).
- Baixa ↔ título: `baixas_santri_titulos.cod_financeiro = titulos_santri.codigo` e `baixas_santri.lado = titulos_santri.lado`, só `ativo`.
- Papéis: `admin`, `direcao`, `financeiro` veem e operam o caixa (`interno.pode_ver_financeiro()`); classificação do plano de contas só `admin`/`direcao` (`interno.ve_todas_lojas()`).
- Textos da tela em português simples (o Bruno e diretores comerciais leem); números com `brl0`/`milCmp`.
- Ao fim de cada task: linha no topo de `docs/ALTERACOES.md` (data · "Bruno (Claude)" · o que mudou · migration · commit) e, se criou tabela/RPC/tela, item em `docs/HANDOFF.md` (seção "O que existe"/telas). Atualizar "Última migration" no topo de `ALTERACOES.md`.
- Commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (ou o modelo que executar). Push no `main` ao fim de cada task.

## Review Focus

1. **Título pago depois da última foto de títulos** (baixa importada, título ainda "Aberto" na foto): não pode sair de novo no caixa — testado na Task 1 (status) e Task 4 (caso g).
2. **Triagem com data no passado** ("pagar em" uma data que já passou): o valor deve cair na semana atual, não sumir — teste na Task 4 (caso c2).
3. **Loja sem nenhum saldo informado:** a tela não pode mostrar saldo zero como se fosse real; KPI mostra "informe o saldo" e as semanas mostram "acumulado sem o saldo" — teste na Task 4 (`saldo.informado=false`) e Task 5 (Playwright).
4. **Usuário de uma loja só** (`financeiro` de RV) chamando `tela_caixa(0)`: deve ver só a própria loja (via `interno.lojas_tela`) — teste na Task 4.
5. **Plano de contas novo que apareceu numa importação** e ainda não foi classificado: entra pelo grupo padrão (heurística), nunca some do caixa — teste na Task 1 (`grupo_caixa` de código desconhecido).

---

### Task 1: Base comum — classificação do plano de contas e status único do título (migration 41)

**Files:**
- Create: `sql/migration_41_base_controller.sql`
- Create: `sql/testes/teste_41_base_controller.sql`
- Modify: `index.html` (menu da direção ~linha 169, `rota()` ~linha 179, nova função `telaPlanoContasJ` perto de `telaParametros`)

**Interfaces:**
- Produces:
  - Tabela `public.plano_contas_classe(plano_codigo text primary key, plano_nome text, grupo_caixa text not null, fixa boolean not null default false, linha_dre text, regra_mes text, linha_mercado text, revisado boolean not null default false, atualizado_por uuid, atualizado_em timestamptz default now())`. `grupo_caixa in ('fornecedor','pessoal','impostos','comissoes_rt','divida','fixo','outros','fora')`; `regra_mes in ('anterior_vencimento','emissao')` ou null. `linha_dre`, `regra_mes`, `linha_mercado` ficam nulos (a F1 preenche).
  - `interno.grupo_caixa_padrao(p_plano_nome text) returns text` (immutable) — heurística.
  - `interno.grupo_caixa(p_plano_codigo text, p_plano_nome text) returns text` (stable) — da tabela; se não houver linha, `grupo_caixa_padrao(p_plano_nome)`.
  - `interno.status_titulo(p_situacao text, p_vencimento date, p_pago_por_baixa boolean, p_hoje date) returns text` (immutable) — `'pago'|'aberto'|'vencido'`.
  - `interno.titulos_status(p_lado text, p_hoje date) returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso int)` — todos os títulos da foto atual do lado.
  - `public.salvar_classe_conta(p_codigo text, p_grupo text, p_fixa boolean) returns void`.
  - `public.lista_plano_contas() returns jsonb` — `[{plano_codigo, plano_nome, grupo_caixa, fixa, revisado, titulos_12m int}]` ordenado por `titulos_12m desc`.

- [ ] **Step 1: Escrever o teste SQL** em `sql/testes/teste_41_base_controller.sql`, um bloco `do $$ ... $$` que termina em `raise exception 'OK-ROLLBACK'` e falha com `raise exception 'FALHOU: <caso>'`. Casos:

```sql
-- status_titulo (hoje = 2026-11-04)
assert interno.status_titulo('Baixado','2026-10-01',false,'2026-11-04') = 'pago';
assert interno.status_titulo('Aberto','2026-11-04',false,'2026-11-04') = 'aberto';   -- vence hoje = aberto
assert interno.status_titulo('Aberto','2026-11-03',false,'2026-11-04') = 'vencido';
assert interno.status_titulo('Aberto','2026-11-03',true ,'2026-11-04') = 'pago';
-- heurística
assert interno.grupo_caixa_padrao('FORNECEDORES') = 'fornecedor';
assert interno.grupo_caixa_padrao('IMPOSTOS FEDERAIS - PARCELAMENTO') = 'divida';   -- parcelamento antes de imposto
assert interno.grupo_caixa_padrao('SIMPLES') = 'divida';
assert interno.grupo_caixa_padrao('ICMS SOBRE VENDAS') = 'impostos';
assert interno.grupo_caixa_padrao('COMISSOES PAGAS A VENDEDORES') = 'comissoes_rt';
assert interno.grupo_caixa_padrao('SALARIOS') = 'pessoal';
assert interno.grupo_caixa_padrao('DESPESAS COM CARTORIO') = 'fixo';                -- não confundir "RT"
-- código desconhecido cai na heurística (Review Focus 5)
assert interno.grupo_caixa('9.999.999','FRETE SOBRE COMPRAS') = 'fornecedor';
-- titulos_status com dados inventados: criar importação 'pagar' aplicada (vira a última), 3 títulos loja 1:
--   A Aberto venc 2026-11-10 saldo 10 · B Aberto venc 2026-10-20 saldo 20 · C Aberto venc 2026-10-25 saldo 30 com baixa ativa valor_baixado 30
-- esperar: A aberto/0, B vencido/15, C pago/0
```

Usar `assert` do plpgsql (falha com mensagem própria) ou `if ... then raise exception 'FALHOU: ...'`. Para a parte com tabelas: `insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id`; inserir títulos com `codigo` iniciando por `'TESTE-'`; inserir `baixas_santri` (lado 'pagar', loja 1, ativo, `baixa`='TESTE-B1') + `baixas_santri_titulos` (cod_financeiro do C, valor_baixado 30, ativo).

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `execute_sql` com o conteúdo do arquivo.
Expected: erro `function interno.status_titulo(...) does not exist`.

- [ ] **Step 3: Escrever `sql/migration_41_base_controller.sql`**

  - Criar a tabela, RLS ligado, policy de leitura `pode_ver_financeiro()`.
  - `grupo_caixa_padrao` — `case` com regex `~*` sobre `upper(p_plano_nome)`, **nesta ordem**:
    1. `PARCELAMENTO|^SIMPLES$|EMPRESTIMO|FINANCIAMENTO|CONSORCIO` → `divida`
    2. `FORNECEDOR|FRETE|DESPESAS EXTRAS DE COMPRAS` → `fornecedor`
    3. `COMISS|REFLEXOS? DE COMISS` → `comissoes_rt`
    4. `SALARIO|FERIAS|13|RESCIS|INSS|FGTS|VALE TRANSPORTE|PRO.?LABORE|ENCARGO|PLANO DE SAUDE|ALIMENTA` → `pessoal`
    5. `ICMS|COFINS|^PIS$|IMPOSTO|ISSQN|IRRF|DIFAL|TAXAS MUNICIPAIS` → `impostos`
    6. senão `fixo`
  - Carga inicial (rascunho para o Bruno revisar): `insert into plano_contas_classe (plano_codigo, plano_nome, grupo_caixa, fixa) select distinct on (plano_codigo) plano_codigo, plano_nome, interno.grupo_caixa_padrao(plano_nome), interno.grupo_caixa_padrao(plano_nome) in ('pessoal','fixo') from public.titulos_santri where lado='pagar' and plano_codigo is not null order by plano_codigo, atualizado_em desc on conflict do nothing;` (os nomes vêm do banco, não ficam no arquivo).
  - `titulos_status`: da foto atual do lado; `pago_por_baixa` = soma de `valor_baixado` das baixas ativas do mesmo lado e `cod_financeiro = codigo` ≥ `saldo` (e saldo > 0); `dias_atraso = greatest(p_hoje - vencimento, 0)` só quando `vencido`, senão 0.
  - `salvar_classe_conta`: exige `interno.ve_todas_lojas()`; valida `p_grupo` na lista; `update` grava `revisado=true, atualizado_por=auth.uid(), atualizado_em=now()`; se o código não existir, `insert` (nome do título mais recente desse código).
  - `lista_plano_contas`: exige `pode_ver_financeiro()`; `titulos_12m` = títulos a pagar (qualquer foto) com `emissao >= hoje - 365` por código; inclui códigos que aparecem nos títulos e ainda não estão na tabela (com `grupo_caixa_padrao`, `revisado=false`).
  - Grants para `salvar_classe_conta(text,text,boolean)` e `lista_plano_contas()`.

- [ ] **Step 4: Aplicar e rodar o teste**

Run: `apply_migration` (nome `41_base_controller`), depois `execute_sql` com o teste.
Expected: erro com a mensagem exata `OK-ROLLBACK` (nenhum `FALHOU`). Conferir também `select count(*), count(*) filter (where grupo_caixa='divida') from plano_contas_classe;` > 0.

- [ ] **Step 5: Tela "Plano de contas"** em `index.html`
  - Menu da direção (linha com `['#/parametros','Parâmetros']`): acrescentar `['#/plano-contas','Plano de contas']`.
  - `rota()`: `if(h==='#/plano-contas') return telaPlanoContasJ();`
  - `async function telaPlanoContasJ()`: se `!ehDirecao()` → `telaLista()`. Carrega `rpcJ('lista_plano_contas')`. Topo: `kpiJ` com "contas a revisar" (`revisado=false`). Lista via `listaJ('planoContas', cols, rows)` com colunas Código · Conta · Títulos 12m · Grupo do caixa (`<select class="pcGrupo" data-c="…">` com os 8 grupos, rótulos: Fornecedor, Pessoal, Impostos, Comissões e RT, Dívida, Custo fixo, Outros, Fora do caixa) · Fixa recorrente (`<input type=checkbox class="pcFixa">`) · Revisado (✓). `onchange` chama `salvar_classe_conta` e `toast('Conta classificada')`. Nota no rodapé: "Rascunho feito pela Claude a partir do nome da conta. Revise as contas mais usadas primeiro."
  - Ligar os eventos com `document.addEventListener('change', …)` filtrando por classe, como `filaMarca` (~linha 1483).

- [ ] **Step 6: Checar sintaxe**

Run (PowerShell, na pasta do repo): extrair o maior `<script>` do `index.html` para um arquivo temporário e `node --check` nele.
Expected: sem saída (sem erro).

- [ ] **Step 7: Docs + commit + push**

`docs/ALTERACOES.md` (linha nova, "Última migration: 41"), `docs/HANDOFF.md` (tabela `plano_contas_classe`, funções `interno.status_titulo/titulos_status/grupo_caixa`, rota `#/plano-contas`).

```bash
git add sql/migration_41_base_controller.sql sql/testes/teste_41_base_controller.sql index.html docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Controller base comum: classificação do plano de contas (grupo do caixa) e status único do título (migration 41)"
git push
```

---

### Task 2: Contas bancárias, saldo por conta e caixa mínimo (migration 42)

**Files:**
- Create: `sql/migration_42_contas_bancarias.sql`
- Create: `sql/testes/teste_42_contas_bancarias.sql`

**Interfaces:**
- Consumes: `interno.lojas_tela(smallint)`, `interno.pode_ver_financeiro()`.
- Produces:
  - `public.contas_bancarias(id bigint identity pk, loja_id smallint not null references lojas, banco text not null, nome text not null, ativo boolean not null default true, criado_em timestamptz default now())`.
  - `public.caixa_saldo.conta_id bigint references contas_bancarias` (nova coluna; linhas antigas apontam para a conta "Geral" da loja, criada aqui para cada loja).
  - `public.caixa_parametros(loja_id smallint primary key references lojas, caixa_minimo numeric not null default 0, atualizado_por uuid, atualizado_em timestamptz default now())`.
  - `interno.saldo_caixa(p_lojas smallint[]) returns table(loja_id smallint, conta_id bigint, banco text, nome text, saldo numeric, data date)` — último saldo de cada conta ativa (contas sem saldo voltam com `saldo` e `data` nulos).
  - `public.salvar_conta_bancaria(p_id bigint, p_loja smallint, p_banco text, p_nome text, p_ativo boolean) returns bigint` (p_id null = nova).
  - `public.informar_saldo_conta(p_conta bigint, p_saldo numeric, p_obs text default null) returns void`.
  - `public.salvar_parametros_caixa(p_loja smallint, p_caixa_minimo numeric) returns void`.
  - `public.informar_saldo_caixa(smallint,numeric,text)` (já existe) passa a gravar na conta "Geral" da loja.
  - `public.tela_compras`: o objeto `saldo` de cada loja passa a ser `{saldo: soma dos últimos saldos das contas, data: data mais antiga entre elas, em, obs}` (formato igual ao atual, o front de Compras não muda).

- [ ] **Step 1: Teste SQL** (`teste_42…`), com usuário admin no `request.jwt.claims` (pegar `select id from public.usuarios where papel='admin' and ativo limit 1`):

```sql
-- desativar contas reais da loja 1 dentro da transação: update contas_bancarias set ativo=false where loja_id=1;
c1 := public.salvar_conta_bancaria(null, 1::smallint, 'BANCO TESTE', 'Conta A', true);
c2 := public.salvar_conta_bancaria(null, 1::smallint, 'BANCO TESTE', 'Conta B', true);
perform public.informar_saldo_conta(c1, 1000, null);
perform public.informar_saldo_conta(c1, 1500, null);   -- vale o último
perform public.informar_saldo_conta(c2, 500, null);
assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 2000;
assert (select count(*) from interno.saldo_caixa(array[1]::smallint[])) = 2;
perform public.salvar_conta_bancaria(c2, 1::smallint, 'BANCO TESTE', 'Conta B', false);
assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 1500;
-- Compras continua funcionando: informar_saldo_caixa grava na conta Geral da loja (reativa/cria a Geral)
perform public.informar_saldo_caixa(1::smallint, 300, null);
assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 1800;   -- Conta A 1500 + Geral 300
perform public.salvar_parametros_caixa(1::smallint, 9900);
assert (select caixa_minimo from public.caixa_parametros where loja_id=1) = 9900;
-- usuário sem financeiro não informa saldo: trocar claims para um uuid aleatório e esperar exceção (bloco begin/exception)
```

- [ ] **Step 2: Rodar e ver falhar** — Expected: `function public.salvar_conta_bancaria ... does not exist`.

- [ ] **Step 3: Escrever a migration**
  - Tabelas + RLS (leitura `pode_ver_financeiro` + loja).
  - `alter table caixa_saldo add column if not exists conta_id bigint references contas_bancarias(id)`; criar a conta `('—','Geral')` por loja; `update caixa_saldo set conta_id = <Geral da loja> where conta_id is null`.
  - RPCs com `pode_ver_financeiro()` e loja checada com `p_loja = any(interno.lojas_tela(p_loja))` (para `informar_saldo_conta`, a loja vem da conta). `data` do saldo = hoje Cuiabá.
  - `informar_saldo_caixa`: mesma assinatura, insere com `conta_id` da conta "Geral" ativa da loja (cria se não existir).
  - `tela_compras`: trocar só a subconsulta `saldo` do CTE `caixa` (linhas 193–194 do `sql/migration_39_tela_compras.sql`) por um `jsonb_build_object('saldo', sum(saldo), 'data', min(data), 'em', max(criado_em), 'obs', null)` sobre `interno.saldo_caixa(array[l.id])` (null se nenhuma conta tiver saldo). Use o padrão de `replace()` sobre `pg_get_functiondef` num bloco `DO` **ou** recrie a função inteira copiando de `migration_39` — e deixe a versão final completa da função no `.sql`.
  - Grants das 3 RPCs novas.

- [ ] **Step 4: Aplicar e rodar o teste** — Expected: `OK-ROLLBACK`. Rodar também o bloco de teste do HANDOFF com `public.tela_compras(0::smallint)` e conferir que `caixa[0].saldo.saldo` existe (pode ser null).

- [ ] **Step 5: Docs + commit + push** (ALTERACOES "Última migration: 42", HANDOFF: tabelas e RPCs).

```bash
git add sql/migration_42_contas_bancarias.sql sql/testes/teste_42_contas_bancarias.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: contas bancárias com saldo por conta, caixa mínimo por loja, Compras soma as contas (migration 42)"
git push
```

---

### Task 3: Triagem dos títulos (migration 43)

**Files:**
- Create: `sql/migration_43_titulos_tratativa.sql`
- Create: `sql/testes/teste_43_titulos_tratativa.sql`

**Interfaces:**
- Produces:
  - `public.titulos_tratativa(titulo_id bigint primary key references titulos_santri, decisao text not null, nova_data date, responsavel text, nota text, por uuid, em timestamptz not null default now())`.
    Decisões — lado pagar: `pagar_em`, `renegociado`, `em_disputa`, `nao_e_divida`, `para_diretoria`; lado receber: `prometeu`, `negociando`, `perdido`.
  - `public.titulos_tratativa_eventos(id bigint identity pk, titulo_id bigint, decisao text, nova_data date, nota text, por uuid, em timestamptz default now())` — uma linha a cada gravação.
  - `public.tratar_titulos(p_ids bigint[], p_decisao text, p_nova_data date, p_nota text) returns int` — grava a mesma decisão em vários títulos (1 ou muitos), devolve quantos.

- [ ] **Step 1: Teste SQL**:

```sql
-- título inventado lado pagar (loja 1) e um lado receber
n := public.tratar_titulos(array[tp], 'pagar_em', '2026-11-20', 'combinado');
assert n = 1;
assert (select decisao from public.titulos_tratativa where titulo_id = tp) = 'pagar_em';
perform public.tratar_titulos(array[tp], 'em_disputa', null, null);         -- troca: guarda histórico
assert (select count(*) from public.titulos_tratativa_eventos where titulo_id = tp) = 2;
-- validações (cada uma num begin/exception esperando erro):
--   'pagar_em' sem data → erro 'Informe a data'
--   'prometeu' num título do lado pagar → erro 'Decisão não vale para contas a pagar'
--   'perdido' num título a receber → ok
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Migration:** tabelas + RLS (leitura: o título é visível, como `tie_ler` da migration 34); `tratar_titulos` exige `pode_ver_financeiro()` e que cada título seja de loja em `interno.lojas_tela(0)`; `pagar_em`, `renegociado` e `prometeu` exigem `p_nova_data`; upsert em `titulos_tratativa` (`por=auth.uid()`) + insert em eventos. Grant.
- [ ] **Step 4: Aplicar e rodar o teste** — Expected: `OK-ROLLBACK`.
- [ ] **Step 5: Docs + commit + push** ("Última migration: 43").

```bash
git add sql/migration_43_titulos_tratativa.sql sql/testes/teste_43_titulos_tratativa.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: triagem de títulos atrasados com histórico (migration 43)"
git push
```

---

### Task 4: Projeção do caixa — movimentos, semanas, meses e atrasados (migration 44)

**Files:**
- Create: `sql/migration_44_tela_caixa.sql`
- Create: `sql/testes/teste_44_tela_caixa.sql`

**Interfaces:**
- Consumes: `interno.titulos_status`, `interno.grupo_caixa`, `interno.saldo_caixa`, `public.caixa_parametros`, `public.titulos_tratativa`, `interno.lojas_tela`, `interno.categoria_receber`.
- Produces:
  - `interno.caixa_movimentos(p_lojas smallint[], p_hoje date, p_atrasados text) returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean)` — `valor` positivo = entra, negativo = sai; `origem='lancado'` neste plano; `p_atrasados in ('triagem','pagar_tudo')`.
  - `public.tela_caixa(p_loja smallint, p_atrasados text default 'triagem', p_hoje date default null) returns jsonb` (null → hoje Cuiabá).
  - `public.caixa_detalhe(p_loja smallint, p_grupo text, p_ini date, p_fim date, p_atrasados text default 'triagem', p_hoje date default null) returns jsonb` — `[{titulo_id, loja, nome, plano_nome, vencimento, data, valor, vencido, decisao}]` ordenado por `abs(valor) desc`.

**Regras de `caixa_movimentos`** (spec §5.2, §5.3, §6):

| Lado | Condição | Data | Grupo |
|---|---|---|---|
| pagar | status `aberto`, tipo ∉ (`Pre`,`Cre`,`Adi`) | vencimento | `grupo_caixa(plano)`; `fora` → não entra |
| pagar | status `vencido`, tipo ∉ (`Pre`,`Cre`,`Adi`), modo `triagem` | `pagar_em`/`renegociado` → `greatest(nova_data, p_hoje)` · `em_disputa`/`nao_e_divida` → não entra · `para_diretoria` ou sem triagem → `p_hoje` | idem |
| pagar | status `vencido`, modo `pagar_tudo` | `p_hoje` (exceto `nao_e_divida`, que não entra) | idem |
| receber | status `aberto`, tipo não casa `Cart%`, `Cr%dito`, `Adiant%`, `Previs%` e `categoria_receber ≠ 'credito_fornecedor'` | vencimento | `clientes` (ou `outros` quando `categoria_receber` ∉ `clientes`,`venda_direta`) |
| receber | `vencido`, mesmos filtros | `prometeu` → `greatest(nova_data, p_hoje)` · `perdido` → não entra · senão: `dias_atraso ≤ 60` → `p_hoje + 7`, `> 60` → não entra | idem |

Só `saldo > 0`; status `pago` nunca entra; só lojas de `p_lojas`.

**Formato de `tela_caixa`** (semanas: k=0..12, `ini = date_trunc('week', hoje)::date + 7k`, `fim = ini + 6`; meses: 12 a partir de `date_trunc('month', hoje)`; saldo acumulado parte do saldo hoje):

```text
{ hoje, lojas:[1,2], atrasados_modo,
  atualizado:{titulos, baixas},                        -- max(criado_em) das importações aplicadas
  saldo:{informado:bool, total, data_mais_antiga, contas:[{conta_id,loja,banco,nome,saldo,data}]},
  minimo: soma de caixa_minimo das lojas,
  semanas:[{k, ini, fim, entradas, saidas, saldo_fim, grupos:{<grupo>: valor}}],
  meses:[{mes, entradas, saidas, saldo_fim, grupos:{...}}],
  kpi:{ saldo_hoje, saldo_data, primeira_abaixo:{k, ini, negativo}|null,
        maior_buraco:{valor, ini}, atrasado_pagar, atrasado_nao_triado },
  por_loja:[{loja, saldo_hoje, saldo_informado, minimo, primeira_abaixo, maior_buraco, atrasado_pagar}],
  atrasados:[{titulo_id, loja, nome, plano_nome, grupo, tipo, vencimento, dias, saldo, decisao, nova_data, nota, por_nome, em}] }
```

`atrasado_pagar` = soma do `saldo` dos títulos a pagar `vencido`, tipo ∉ (`Pre`,`Cre`,`Adi`), grupo ≠ `fora`, decisão ≠ `nao_e_divida`. `atrasado_nao_triado` = parte disso sem linha em `titulos_tratativa`. `atrasados` = essa mesma lista (com triados), por `saldo desc`. `primeira_abaixo` = primeira semana com `saldo_fim < minimo` (`negativo = saldo_fim < 0`); só calculada quando `saldo.informado`. `saidas` é positivo (soma de `-valor` das saídas).

- [ ] **Step 1: Teste SQL** (`teste_44…`), `p_hoje = '2026-11-04'` (quarta; semana 0 = 02/11–08/11). Preparar dentro da transação: importações novas `pagar` e `receber` (viram as últimas), contas reais da loja 1 desativadas, uma conta de teste com saldo 10000, `caixa_minimo` 9900 na loja 1, plano `TESTE.FORA` classificado `fora`. Títulos (loja 1 salvo indicação) e o que se espera de `interno.caixa_movimentos(array[1]::smallint[], '2026-11-04', 'triagem')`:

| Caso | Título | Esperado |
|---|---|---|
| a | pagar, aberto, venc 10/11, 100, plano fornecedor | data 10/11, −100, grupo `fornecedor` |
| b | pagar, venc 20/10, 200, sem triagem | data 04/11, −200 |
| c | pagar, venc 15/10, 300, `pagar_em` 20/11 | data 20/11, −300 |
| c2 | pagar, venc 15/10, 50, `pagar_em` 01/11 (passado) | data 04/11, −50 |
| d | pagar, venc 10/10, 400, `em_disputa` | ausente (presente em 04/11 no modo `pagar_tudo`) |
| e | pagar, venc 10/10, 500, `nao_e_divida` | ausente nos dois modos |
| f | pagar, tipo `Pre`, venc 12/11, 50 | ausente |
| g | pagar, venc 12/11, 60, com baixa ativa de 60 | ausente |
| h | pagar, venc 12/11, 70, plano `TESTE.FORA` | ausente |
| i | receber, venc 15/11, 1000 | data 15/11, +1000, `clientes` |
| j | receber, venc 05/10 (30 dias), 700 | data 11/11, +700 |
| k | receber, venc 06/08 (90 dias), 800 | ausente |
| l | receber, venc 06/08, 900, `prometeu` 25/11 | data 25/11, +900 |
| m | receber, tipo `Cartão`, venc 20/11, 400 | ausente |
| n | receber, venc 15/10, 150, `perdido` | ausente |
| o | pagar, **loja 2**, venc 10/11, 70 | ausente quando `p_lojas = {1}` |

Asserts de `public.tela_caixa(1::smallint, 'triagem', '2026-11-04')`:

```text
saldo.informado = true, saldo.total = 10000
semanas[0].saldo_fim = 9750        -- 10000 − 200 (b) − 50 (c2)
semanas[1].saldo_fim = 11350       -- − 100 (a) + 700 (j) + 1000 (i)
semanas[2].saldo_fim = 11050       -- − 300 (c)
semanas[3].saldo_fim = 11950       -- + 900 (l)
kpi.primeira_abaixo.k = 0, kpi.primeira_abaixo.negativo = false
kpi.maior_buraco.valor = 9750
kpi.atrasado_pagar = 950           -- b 200 + c 300 + c2 50 + d 400
kpi.atrasado_nao_triado = 200      -- só b
jsonb_array_length(semanas) = 13, jsonb_array_length(meses) = 12
meses[0].saldo_fim = 11950         -- tudo cai em novembro
```

Modo `pagar_tudo`: `semanas[0].saldo_fim = 9750 − 400 − 300` (c também vai para hoje) = **9050**.
Sem saldo (desativar a conta de teste): `saldo.informado = false` e `kpi.primeira_abaixo` null.
Acesso (Review Focus 4): se houver usuário ativo com `papel='financeiro'` e `loja_id=2`, com o claims dele `tela_caixa(0)` → `lojas = [2]`; se não houver, criar um em `public.usuarios` dentro da transação com `id = gen_random_uuid()`.

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Migration** — `caixa_movimentos` (stable, sql ou plpgsql) com a tabela de regras acima; `tela_caixa` (exige `pode_ver_financeiro()`, `lojas := interno.lojas_tela(p_loja)`, valida `p_atrasados`) agregando com `generate_series`; `caixa_detalhe` filtrando `caixa_movimentos` por grupo e data entre `p_ini` e `p_fim`. `statement_timeout = '60s'`. Grants de `tela_caixa(smallint,text,date)` e `caixa_detalhe(smallint,text,date,date,text,date)`.
- [ ] **Step 4: Aplicar e rodar o teste** — Expected: `OK-ROLLBACK`. Depois rodar com dados reais (bloco do HANDOFF, `public.tela_caixa(0::smallint)`) e conferir que volta em menos de 5 s (`explain analyze` se passar).
- [ ] **Step 5: Docs + commit + push** ("Última migration: 44"; HANDOFF: as regras da tabela acima em resumo, na seção de telas).

```bash
git add sql/migration_44_tela_caixa.sql sql/testes/teste_44_tela_caixa.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: projeção 13 semanas + 12 meses do lançado, atrasados pela triagem (migration 44)"
git push
```

---

### Task 5: Tela "Caixa" — topo e aba Projeção

**Files:**
- Modify: `index.html` (menu ~linha 168, `rota()` ~linha 179, bloco novo `// ---------- CAIXA ----------` depois das funções `*J` de Financeiro)
- Create (fora do repo): `..\_testes\caixa\` com `package.json`, `teste_caixa.mjs`, `mock_tela_caixa.json` (números inventados)

**Interfaces:**
- Consumes: `tela_caixa(p_loja, p_atrasados)`, `caixa_detalhe(...)`, helpers `rpcJ`, `cabJ`, `indCmp`, `abasJ`, `lojaJ`, `lojaSufixo`, `brl0`, `milCmp`, `dBR`, `fonteJ`, `erroTelaJ`, estado `J`.
- Produces: `async function telaCaixaJ()`, `function graficoSaldoCx(semanas, minimo, informado) -> string` (SVG), estado `CX = {cache:null, atrasados:'triagem', visao:'semanas'}`; as abas `atr` e `sal` ficam como `''` (Tasks 6 e 7 preenchem `abaAtrasadosCx(r)` e `abaSaldosCx(r)`).

- [ ] **Step 1: Montar o ambiente de teste** em `..\_testes\caixa\` (pasta do Bruno, fora do repo): `npm init -y`, `npm i playwright @supabase/supabase-js`, `npx playwright install chromium`. Mock de `tela_caixa` com 2 lojas, 13 semanas, 12 meses, valores inventados, semana 2 negativa.

- [ ] **Step 2: Escrever `teste_caixa.mjs`** seguindo HANDOFF "Testes" (rotear `cdn.jsdelivr.net` para `node_modules/@supabase/supabase-js/dist/umd/supabase.js`, `*.supabase.co` para mocks, sessão falsa no localStorage, usuário `direcao`). Abrir `file:///…/dom-gabriel-sistema/index.html#/caixa`. Asserts:
  - aparecem 4 indicadores com os títulos exatos: "Saldo hoje", "Primeira semana abaixo do mínimo", "Maior buraco · 13 semanas", "Atrasado a pagar";
  - o SVG `#cxGrafico` tem 13 barras (`rect.cxBar`) e uma linha do mínimo (`line.cxMin`);
  - barra da semana negativa tem a classe `neg`;
  - clicar em "Mês a mês" mostra 12 linhas na tabela `#cxTabela`;
  - clicar numa célula de grupo chama `caixa_detalhe` (interceptado) e abre a lista;
  - com mock `saldo.informado=false`, o 1º indicador mostra "Informe o saldo";
  - em 390 px: `document.documentElement.scrollWidth <= 390`.

- [ ] **Step 3: Rodar e ver falhar** — `node teste_caixa.mjs` → falha em "indicadores".

- [ ] **Step 4: Implementar no `index.html`**
  - Menu: depois de Financeiro, `...(veFinanceiroJ()?[['#/caixa','Caixa']]:[])` nas duas listas (setores e direção). `rota()`: `if(h==='#/caixa') return telaCaixaJ();`
  - `telaCaixaJ()`: `cabJ('Caixa'+lojaSufixo(), fonteJ(r.atualizado.titulos,'Contas a pagar/receber') + chave "Atrasados: seguir a triagem | pagar tudo agora")`; aviso amarelo se `atualizado.titulos` tiver mais de 7 dias ("Contas importadas há N dias — a projeção pode estar errada") e se `saldo.data_mais_antiga` tiver mais de 7 dias.
  - Topo (`.topoSetor` com `indCmp`):
    1. "Saldo hoje" — `milCmp(kpi.saldo_hoje)`, sub "saldo de dd/mm"; se `!saldo.informado`, valor "Informe o saldo" e `aba:'sal'`.
    2. "Primeira semana abaixo do mínimo" — `dd/mm` da semana ou "Nenhuma em 13 semanas" (`ok`); `alerta` se houver; sub "fica negativo" quando `negativo`, senão "abaixo de " + `milCmp(minimo)`.
    3. "Maior buraco · 13 semanas" — `milCmp(maior_buraco.valor)`, sub "semana de dd/mm"; `alerta` se < 0.
    4. "Atrasado a pagar" — `milCmp(atrasado_pagar)`, sub `milCmp(atrasado_nao_triado) + ' sem decisão'`; `aba:'atr'`.
  - Embaixo do topo, quando é "Ambas", uma linha por loja (`por_loja`) com os mesmos 4 números em texto curto.
  - Abas `abasJ('caixa', [['proj','Projeção'],['atr','Atrasados a pagar'],['sal','Saldos']], telaCaixaJ)`; `data-irc` dos indicadores troca a aba (mesmo mecanismo de Compras).
  - Aba Projeção: chave "Semana a semana | Mês a mês" (`CX.visao`); `graficoSaldoCx` — barras do `saldo_fim` (verde ≥ mínimo, amarelo entre 0 e mínimo, vermelho `neg` < 0), linha tracejada do mínimo, rótulo dd/mm embaixo, `viewBox` responsivo (`width:100%`). Tabela `#cxTabela`: linhas = Saldo inicial, Entradas (clientes, outros), Saídas (fornecedor, pessoal, impostos, comissões e RT, dívida, custo fixo, outros), Saldo no fim; colunas = semanas (ou meses), rolagem horizontal só dentro de `.tbl`. Célula de grupo clicável → `caixa_detalhe` → `listaJ('cxDet', …)` num `#modal` (colunas Loja · Nome · Conta · Vencimento · Cai em · Valor · Triagem).
  - Nota no rodapé (texto fixo): "Projeção com o que está lançado no Santri. Ainda não entram: custo fixo que não foi lançado, vendas futuras e parcelas de dívidas fora do Santri. Cartão não entra porque já foi antecipado. A receber vencido há mais de 60 dias só entra com promessa de pagamento."
  - A chave "Atrasados" grava `CX.atrasados` e recarrega `tela_caixa` com `p_atrasados`.

- [ ] **Step 5: Rodar o Playwright e o `node --check`** — Expected: todos os asserts passam; `node --check` sem saída.
- [ ] **Step 6: Docs + commit + push** (ALTERACOES "—" na coluna migration; HANDOFF: rota `#/caixa`).

```bash
git add index.html docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Tela Caixa: números do topo e projeção semana a semana / mês a mês"
git push
```

---

### Task 6: Aba "Atrasados a pagar" (triagem)

**Files:**
- Modify: `index.html` (bloco CAIXA)
- Modify (fora do repo): `..\_testes\caixa\teste_caixa.mjs`

**Interfaces:**
- Consumes: `r.atrasados` de `tela_caixa`; RPC `tratar_titulos(p_ids, p_decisao, p_nova_data, p_nota)`.
- Produces: `function abaAtrasadosCx(r) -> string`.

- [ ] **Step 1: Acrescentar ao teste Playwright:** mock com 5 atrasados (2 triados); filtro "Sem decisão" mostra 3; marcar 2 caixas + escolher "Não é dívida" + "Aplicar" chama `tratar_titulos` com `p_ids` de 2 itens e `p_decisao='nao_e_divida'`; escolher "Pagar em" sem data mostra `toast` "Informe a data" e não chama a RPC.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar `abaAtrasadosCx(r)`** — filtros (chips): Todos · Sem decisão · Para a diretoria · Em disputa; lista `listaJ('cxAtr', …)` com colunas ☐ · Loja · Nome · Conta (plano) · Vencimento · Dias · Valor · Decisão (pill com cor: sem decisão vermelho, para a diretoria laranja, pagar em/renegociado verde, em disputa cinza) · Nota. Barra de ação acima: select (Pagar em · Renegociado (1ª parcela em) · Em disputa · Não é dívida (corrigir no Santri) · Para a diretoria), `<input type=date>` (aparece para pagar em/renegociado), nota, botão "Aplicar aos marcados". Clique numa linha marca/desmarca. Depois de gravar: `toast('Decisão gravada')`, `CX.cache=null`, recarrega. Nota no rodapé: "Sem decisão, o atrasado entra no caixa desta semana (pior caso)."
- [ ] **Step 4: Rodar Playwright + `node --check`** — Expected: passa.
- [ ] **Step 5: Docs + commit + push.**

```bash
git add index.html docs/ALTERACOES.md
git commit -m "Tela Caixa: triagem dos atrasados a pagar (em lote)"
git push
```

---

### Task 7: Aba "Saldos" (contas bancárias e caixa mínimo)

**Files:**
- Modify: `index.html` (bloco CAIXA)
- Modify (fora do repo): `..\_testes\caixa\teste_caixa.mjs`

**Interfaces:**
- Consumes: `r.saldo.contas`, `r.por_loja[].minimo`; RPCs `informar_saldo_conta`, `salvar_conta_bancaria`, `salvar_parametros_caixa`.
- Produces: `function abaSaldosCx(r) -> string`.

- [ ] **Step 1: Acrescentar ao teste:** a aba lista as contas agrupadas por loja com último saldo e data; conta com saldo de mais de 7 dias tem a classe `atras`; "Informar saldos" abre modal com um campo por conta e, ao salvar `125.000,00`, chama `informar_saldo_conta` com `p_saldo=125000`; "Nova conta" chama `salvar_conta_bancaria` com `p_id=null`; mudar o caixa mínimo chama `salvar_parametros_caixa`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar `abaSaldosCx(r)`** — por loja: tabela Banco · Conta · Último saldo · Data · [Desativar]; total da loja; campo "Caixa mínimo" (onchange → `salvar_parametros_caixa`). Botões "Informar saldos" (modal no estilo de `modalSaldoCmp`, reaproveitando o mesmo conversor de número `num`) e "Nova conta" (modal com loja, banco, nome). Texto: "Toda segunda, informe o saldo de cada conta (o que está disponível hoje). Caixa mínimo: o valor que a diretoria quer ter sempre (ex.: uma folha + impostos do mês)."
- [ ] **Step 4: Rodar Playwright + `node --check`** — Expected: passa.
- [ ] **Step 5: Docs + commit + push**, e marcar no `docs/PROXIMOS_PASSOS.md` §0: "F2 — plano 1 construído (base comum, saldos, projeção do lançado, triagem)".

```bash
git add index.html docs/ALTERACOES.md docs/PROXIMOS_PASSOS.md
git commit -m "Tela Caixa: saldos por conta bancária e caixa mínimo"
git push
```

---

## Ao terminar o plano

Avisar o Bruno em poucas linhas: o que já dá para usar, que precisa (1) importar a pagar/receber/baixas atualizados, (2) cadastrar as contas e informar os saldos, (3) definir o caixa mínimo, (4) revisar a classificação em "Plano de contas"; e pedir a revisão da Claude Opus no fim (as regras de dinheiro merecem um segundo olho).
