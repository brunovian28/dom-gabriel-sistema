# F2 Caixa — Plano 3 (dívidas, entre lojas e renegociação) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O Caixa passa a ter o cadastro de contratos de dívida (com parcelas e ligação aos títulos do Santri), o número "Dívida total" no topo, a aba Dívidas com o gráfico da dívida caindo, os empréstimos entre lojas sumindo no Total, e a triagem "Renegociado" virando parcelas.

**Architecture:** Duas tabelas novas (`dividas`, `dividas_parcelas`) e uma função `interno.dividas_parcelas_todas` que junta as parcelas guardadas (contrato com parcelas fixas) com os títulos do Santri (contrato que já está todo lá). A parcela guardada só entra no `caixa_fluxo` (origem `divida`) quando o contrato não tem título no Santri naquele mês. Os títulos entre lojas são reconhecidos pelo código do cadastro da outra loja (`caixa_parametros.cadastros_santri`): ficam no grupo `entre_lojas`, a loja credora recebe o espelho da saída da devedora, e no Total tudo isso sai. `tela_dividas` alimenta a aba nova; `tela_caixa` ganha `kpi.divida`.

**Tech Stack:** PostgreSQL (Supabase, plpgsql/sql), HTML+JS puro (`index.html`), Playwright em `..\_testes\caixa\` (fora do repositório).

**Spec:** `docs/superpowers/specs/2026-11-02-fluxo-caixa-design.md`: ler §3.1 (número 5), §3.2 (aba 4), §5.3 (Dívidas, Entre lojas), §6 (renegociado), §7.2 (`dividas`), §11. Planos anteriores: `docs/superpowers/plans/2026-11-02-f2-caixa-plano-1.md` e `-plano-2.md`. O que existe: `docs/HANDOFF.md` (Caixa) e migrations 41–51 (a versão atual de `caixa_lancado` e `caixa_fluxo` está na `migration_49b`, a de `tela_caixa`/`caixa_projecao` na `migration_50`).

**Fora deste plano:** aba A receber, cobrança do vendedor, foto semanal, Compras lendo a projeção (plano 4).

## Decisões deste plano (Bruno, 02/11/2026)

| # | Decisão |
|---|---|
| 1 | **Parcela de dívida vencida no Santri, sem triagem, continua na semana 0** (pior caso, igual a hoje). Para tirá-la de lá, a Ana tria: "Pagar em" ou "Renegociado". Sem regra por contrato. |
| 2 | **Entre lojas, visão de uma loja: a entrada da loja credora é o espelho da saída da devedora** (mesma data e valor, pela triagem da devedora). O título a receber entre lojas do Santri não entra (senão conta duas vezes). No Total, entre lojas sai inteiro (entradas, saídas, atrasado e dívida). |
| 3 | "Renegociado" deixa de ser uma data: cria um contrato com N parcelas a partir dos títulos marcados. Os títulos saem da projeção; as parcelas entram. |

Registrar as três em `docs/HANDOFF.md` › Decisões na Task 2.

## O que os dados mostram (consulta de 02/11/2026, sem valores)

- Quase toda dívida **já está no Santri** como parcela: consórcio e leasing, empréstimos a bancos, juros, parcelamento federal, Simples. O cadastro serve para dar nome, saldo e prazo a esses títulos e para as parcelas que não estão lá.
- Entre lojas existe **nos dois lados**: título a pagar numa loja e a receber na outra, com o cadastro da outra loja como credor/cliente (os códigos dos cadastros das lojas se repetem nas duas lojas, porque o Santri é um só). Boa parte do atrasado do grupo Dívida é entre lojas. Há um terceiro código com nome de Dom Gabriel que precisa ser identificado com o Bruno (Task 2, Step 4).
- `titulos_tratativa` está vazia: mudar o efeito de "Renegociado" não afeta nada gravado.

## Global Constraints

- **Repositório público:** nunca commitar valores da empresa, nomes de credores, clientes ou fornecedores, códigos de cadastro do Santri, nem tokens. Testes SQL usam **dados inventados** (`'TESTE-…'`) numa transação que termina em `raise exception 'OK-ROLLBACK'`. A carga real (Task 7) vai só para o banco.
- **Migrations:** a última é a **51**. Este plano usa **52, 53, 54 e 55**. Antes de cada uma: `list_migrations` (projeto `vmpxssoyqfdnnyhnvkyl`) e `docs/ALTERACOES.md`; se o Luis usou o número, usar o próximo livre. Arquivo `sql/migration_NN_nome.sql` com a versão final, aplicado com `apply_migration` (nome `NN_nome`).
- `apply_migration` volta "cancelled" se um texto entre aspas tiver `;`: usar vírgula.
- **O conector recusa `DROP` e `DELETE`, até com aprovação, e UPDATE em massa nas tabelas reais dentro de teste.** Nenhuma task usa DROP nem DELETE. Mudar parâmetros de RPC = função nova com o mesmo nome e os parâmetros novos **sem default**, e a antiga vira atalho (`create or replace` na mesma assinatura). Neste plano nenhuma assinatura existente muda: `tela_caixa`, `caixa_detalhe`, `caixa_lancado`, `caixa_fluxo` e `tratar_titulos` são recriadas com a mesma assinatura.
- **Toda função nova** (public e interno) termina com `revoke execute on function X(args) from anon, public;` e `grant execute on function X(args) to authenticated;`. Avisar o Bruno antes: "o conector vai pedir aprovação para o REVOKE, pode aprovar, não apaga dado". Depois de criar RPC, `get_advisors` (security) sem aviso de `anon`.
- Funções: `security definer`, `set search_path to ''`, tudo qualificado, `#variable_conflict use_column` quando variável e coluna têm o mesmo nome.
- RLS em toda tabela nova: leitura `(select interno.pode_ver_financeiro())` e loja `(select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())`. Escrita só por RPC (`pode_ver_financeiro()` + loja em `interno.lojas_tela(p_loja)`). Sem DELETE: desativar com `ativo=false`.
- "Hoje" = `(now() at time zone 'America/Cuiaba')::date`. Foto atual dos títulos = `ultima_importacao_id = interno.titulos_ultima_importacao(lado)`. Saldo em aberto = `interno.titulos_aberto(lado, hoje)`. Tipos fora do a pagar: `Pre`, `Cre`, `Adi`.
- **Valor positivo = entra, negativo = sai.** Origem nova: `divida` (conta como estimado em `grupos_est`, mostra ◐). Grupo novo: `entre_lojas` (nos dois lados).
- **Testes em 2030** (HANDOFF › Testes do Caixa): hoje = `'2030-09-04'` (quarta), horizonte até `'2031-08-31'`. O `teste_44` e o `teste_49`/`50` precisam continuar passando.
- Ao fim de cada task: linha no topo de `docs/ALTERACOES.md` + "Última migration", `docs/HANDOFF.md` (seção Caixa) se criou tabela/coluna/RPC/regra, commit com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (ou o modelo que executar) e push no `main`.
- Medir `tela_caixa(0)` com dados reais ao fim das Tasks 3 e 4: abaixo de **5 s** (limite real 8 s).

## Regras de cálculo

| Item | Regra |
|---|---|
| Contrato | `dividas`: credor, tipo (`banco`, `imposto`, `socio`, `entre_lojas`, `chapadao`, `outro`), loja devedora, `outra_loja` (só `entre_lojas`, credora), saldo informado + data, taxa ao mês (%), parcela, modo das parcelas, filtro do Santri, `origem` (`cadastro` ou `renegociacao`), ativo. |
| Modo `santri` | O contrato já está todo no Santri. Parcelas = títulos a pagar da foto atual que casam o filtro, com saldo em aberto > 0 (inclui vencidos). Nada guardado, nada novo no caixa. |
| Modo `fixas` | Parcelas guardadas em `dividas_parcelas` (`n` parcelas de `parcela`, mês a mês a partir de `primeiro_venc`, mesmo dia, dia 29–31 vira o último dia do mês). Salvar de novo com parcelas diferentes desativa as antigas (`ativo=false`) e insere as novas. |
| Filtro do Santri | `santri_cadastro` (obrigatório para ligar) + `santri_plano` e `santri_doc_prefixo` opcionais (`documento` começa com o prefixo). Mesma loja do contrato, lado pagar, tipo fora de Pre/Cre/Adi, título sem tratativa `renegociado`. |
| Parcela ligada | Parcela `fixas` está "no Santri" quando o contrato tem **algum** título que casa o filtro com vencimento no mesmo mês (qualquer situação). `titulo_id` = o menor id desse mês. |
| Parcela no caixa | Parcela `fixas`, ativa, não ligada, vencimento ≥ hoje e ≤ fim do horizonte → `caixa_fluxo` com origem `divida`, grupo `divida` (ou `entre_lojas`), `descricao` = `'Parcela n/N · ' || credor`. Parcela não ligada com vencimento < hoje não entra (o contrato foi cadastrado com o saldo de hoje). |
| Título entre lojas | Título cujo `cadastro_codigo` está em `caixa_parametros.cadastros_santri` de **outra** loja (`interno.loja_do_cadastro`). A pagar: grupo `entre_lojas`, segue a triagem como qualquer título. A receber: não entra. |
| Espelho | Para cada movimento de saída `entre_lojas` da loja devedora (título ou parcela de contrato `entre_lojas`), um movimento `+valor` na loja credora, mesma data, grupo `entre_lojas`, mesma origem, `titulo_id` igual. |
| Total | Quando `p_lojas` tem mais de uma loja, nenhuma linha `entre_lojas` sai de `caixa_fluxo`. `atrasado_pagar` e a dívida total também ignoram entre lojas. |
| Renegociado | `renegociar_titulos` cria um contrato `fixas`, `origem='renegociacao'`, com `santri_cadastro` = o cadastro dos títulos (se todos iguais, senão null), e grava tratativa `renegociado` com `divida_id` em cada título. `caixa_lancado` não mostra título com tratativa `renegociado` e `divida_id` de contrato ativo. Desativar o contrato devolve os títulos para `para_diretoria` (nota "contrato de renegociação desativado"). `tratar_titulos(..., 'renegociado', ...)` passa a dar erro `'Use Renegociar, que cria as parcelas'`. Trocar a decisão de um título renegociado dá erro `'Título renegociado: desative o contrato na aba Dívidas'`. |
| Saldo do contrato | `saldo_informado` se houver; senão Σ das parcelas que faltam (modo `fixas`: ativas com vencimento ≥ hoje; modo `santri`: saldo em aberto dos títulos), marcado `saldo_estimado=true`. |
| Curva da dívida | Por contrato, mês a mês de `date_trunc('month', hoje)` até o mês da última parcela: `s(0) = saldo`, `s(m+1) = s(m) × (1 + taxa/100) − Σ parcelas do mês m` (taxa null → 0), nunca abaixo de 0. Total = soma dos contratos (sem entre lojas quando for o Total). |
| Sem contrato | Títulos a pagar abertos (incluindo vencidos) do grupo `divida` que não casam o filtro de nenhum contrato ativo, agrupados por loja, cadastro e plano. Entram na dívida total pelo saldo em aberto e na curva pelos vencimentos. |
| Dívida total (KPI) | Σ saldo dos contratos ativos + Σ sem contrato. Sub: parcela média = (Σ parcelas dos contratos + Σ títulos sem contrato) com vencimento de hoje até hoje + 12 meses − 1 dia, ÷ 12. |

## Review Focus

1. **Título renegociado e parcela nova no mesmo mês:** quando a Ana lança no Santri as parcelas da renegociação, o título antigo (ainda aberto) não pode ligar à parcela nem voltar ao caixa. Teste na Task 3 (título antigo vencido no mês da 1ª parcela).
2. **Contrato `santri` e contrato `fixas` com o mesmo credor** (dois empréstimos no mesmo banco): sem `santri_doc_prefixo`, os dois ligam aos mesmos títulos. A tela mostra o aviso "filtro igual a outro contrato" e o teste da Task 1 cobre o prefixo separando os dois.
3. **Loja credora sem a devedora na tela:** `tela_caixa(2)` precisa do espelho mesmo calculando só a loja 2. Teste na Task 2 (`p_lojas={2}`).
4. **Contrato com última parcela além do horizonte (consórcio até 2041):** o caixa só leva até o fim do horizonte, mas a curva e "acaba em" vão até a última parcela. Teste na Task 4 (`tela_dividas`, curva até 2032).
5. **Contrato salvo duas vezes com parcelas diferentes:** as antigas ficam `ativo=false` e não somam no caixa nem no saldo. Teste na Task 1.

---

### Task 1: Cadastro de dívidas e parcelas (migration 52)

**Files:**
- Create: `sql/migration_52_dividas.sql`
- Create: `sql/testes/teste_52_dividas.sql`

**Interfaces:**
- Produces:
  - `public.dividas(id bigint identity pk, credor text not null, tipo text not null check (tipo in ('banco','imposto','socio','entre_lojas','chapadao','outro')), loja_id smallint not null references lojas, outra_loja smallint references lojas, valor_original numeric, saldo_informado numeric, saldo_data date, taxa_mes numeric, parcela numeric, primeiro_venc date, n_parcelas int, modo text not null check (modo in ('fixas','santri')), santri_cadastro text, santri_plano text, santri_doc_prefixo text, origem text not null default 'cadastro' check (origem in ('cadastro','renegociacao')), obs text, ativo boolean not null default true, atualizado_por uuid, atualizado_em timestamptz default now())`. Check: `tipo='entre_lojas'` ⇔ `outra_loja is not null and outra_loja <> loja_id`; `modo='santri'` exige `santri_cadastro`.
  - `public.dividas_parcelas(id bigint identity pk, divida_id bigint not null references dividas, numero int not null, vencimento date not null, valor numeric not null, ativo boolean not null default true, criado_em timestamptz default now())`.
  - `public.dividas_eventos(id bigint identity pk, divida_id bigint not null, acao text not null, dados jsonb, por uuid, em timestamptz default now())` — uma linha a cada `salvar_divida` (dados = o jsonb recebido).
  - `public.caixa_parametros.cadastros_santri text[] not null default '{}'` — códigos do cadastro desta loja no Santri (quando ela aparece como cliente/fornecedor da outra).
  - `interno.loja_do_cadastro(p_cadastro text) returns smallint` (stable): a loja cujo `cadastros_santri` contém o código, ou null.
  - `interno.divida_casa(d public.dividas, t public.titulos_santri) returns boolean` (stable): o filtro do Santri da tabela "Regras de cálculo".
  - `interno.dividas_parcelas_todas(p_lojas smallint[], p_hoje date) returns table(divida_id bigint, loja_id smallint, numero int, n_total int, vencimento date, valor numeric, titulo_id bigint, no_santri boolean)`: modo `fixas` = parcelas ativas com a ligação por mês; modo `santri` = títulos que casam (`valor` = saldo em aberto, `no_santri` = true, `numero` pela ordem do vencimento). Só contratos ativos de `p_lojas`.
  - `public.salvar_divida(p_id bigint, p_dados jsonb) returns bigint` (`p_id` null = novo). Chaves de `p_dados` = colunas de `dividas` (menos id, origem e auditoria). Gera as parcelas no modo `fixas` quando `parcela`, `primeiro_venc` ou `n_parcelas` mudam (ou no contrato novo). Erros: `'Informe o credor'`, `'Tipo inválido'`, `'Entre lojas precisa da outra loja'`, `'Informe parcela, 1º vencimento e número de parcelas'` (modo `fixas`), `'Informe o código do credor no Santri'` (modo `santri`), `'Loja sem permissão'`.
  - `public.salvar_cadastros_loja(p_loja smallint, p_cadastros text[]) returns void` (exige `interno.ve_todas_lojas()`).

- [ ] **Step 1: Teste SQL** (`teste_52…`, admin nos claims como no `teste_42`, hoje `'2030-09-04'`). Importação `pagar` nova com títulos loja 1, `cadastro_codigo` `'TESTE-BCO'`, `Aberto`: documento `'TESTE-A/1'` 15/10/2030 valor 500, `'TESTE-B/1'` 15/10/2030 valor 700.

```sql
a := public.salvar_divida(null, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"fixas","parcela":500,"primeiro_venc":"2030-09-15","n_parcelas":3,"santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-A"}');
assert (select count(*) from public.dividas_parcelas where divida_id = a and ativo) = 3, 'FALHOU 3 parcelas';
assert (select vencimento from public.dividas_parcelas where divida_id = a and numero = 3 and ativo) = '2030-11-15', 'FALHOU datas';
assert (select bool_and(no_santri = (vencimento = '2030-10-15')) from interno.dividas_parcelas_todas(array[1]::smallint[], '2030-09-04') where divida_id = a), 'FALHOU ligacao por mes';
b := public.salvar_divida(null, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"santri","santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-B"}');
assert (select sum(valor) from interno.dividas_parcelas_todas(array[1]::smallint[], '2030-09-04') where divida_id = b) = 700, 'FALHOU modo santri com prefixo';
perform public.salvar_divida(a, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"fixas","parcela":400,"primeiro_venc":"2030-09-15","n_parcelas":2,"santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-A"}');
assert (select count(*) from public.dividas_parcelas where divida_id = a and ativo) = 2 and (select count(*) from public.dividas_parcelas where divida_id = a) = 5, 'FALHOU regerar sem apagar';
assert (select count(*) from public.dividas_eventos where divida_id = a) = 2, 'FALHOU eventos';
-- 31/01 → 28/02 → 31/03 (último dia do mês)
c := public.salvar_divida(null, '{"credor":"X","tipo":"outro","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}');
assert (select array_agg(vencimento order by numero) from public.dividas_parcelas where divida_id = c) = array['2031-01-31','2031-02-28','2031-03-31']::date[], 'FALHOU fim de mes';
perform public.salvar_cadastros_loja(2::smallint, array['TESTE-L2']);
assert interno.loja_do_cadastro('TESTE-L2') = 2 and interno.loja_do_cadastro('TESTE-NADA') is null, 'FALHOU loja do cadastro';
-- erros (begin/exception): entre_lojas sem outra_loja → 'Entre lojas precisa da outra loja' · modo santri sem santri_cadastro → 'Informe o código do credor no Santri' · usuário sem financeiro → exceção
```

- [ ] **Step 2: Rodar e ver falhar** (`execute_sql`). Esperado: `function public.salvar_divida(bigint, jsonb) does not exist`.
- [ ] **Step 3: Escrever a migration** (tabelas + RLS + policies de leitura, coluna nova, as cinco funções, revoke/grant de todas).
- [ ] **Step 4: Aplicar e rodar o teste.** Esperado: `OK-ROLLBACK`. `get_advisors` (security) sem aviso novo.
- [ ] **Step 5: Docs, commit e push.**

```bash
git add sql/migration_52_dividas.sql sql/testes/teste_52_dividas.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: cadastro de dívidas com parcelas e ligação aos títulos do Santri (migration 52)"
git push
```

---

### Task 2: Parcelas no caixa e entre lojas (migration 53)

**Files:**
- Create: `sql/migration_53_caixa_dividas.sql`
- Create: `sql/testes/teste_53_caixa_dividas.sql`

**Interfaces:**
- Consumes: Task 1 (`dividas_parcelas_todas`, `loja_do_cadastro`, `cadastros_santri`).
- Produces (mesmas assinaturas, `create or replace`):
  - `interno.caixa_lancado(p_lojas, p_hoje, p_atrasados)`: título a pagar entre lojas sai com grupo `entre_lojas`; título a receber entre lojas não sai. (A regra do renegociado entra na Task 3.)
  - `interno.caixa_fluxo(p_lojas, p_hoje, p_atrasados, p_vendas, p_entrada_pct)`: chama `caixa_lancado` com `p_lojas ∪ {lojas devedoras de entre lojas das lojas de p_lojas}`, devolve as linhas das lojas de `p_lojas`, mais o espelho, mais as parcelas não ligadas (origem `divida`), e tira tudo que é `entre_lojas` quando `cardinality(p_lojas) > 1`. Regras na tabela "Regras de cálculo".

- [ ] **Step 1: Teste SQL** (`teste_53…`, hoje `'2030-09-04'`, `p_vendas='zero'`, preparação de vendas como no `teste_44` para o perfil ficar nulo). `cadastros_santri`: loja 1 = `{'TESTE-L1'}`, loja 2 = `{'TESTE-L2'}`. Importações `pagar` e `receber` novas.

| Caso | Dados | Esperado |
|---|---|---|
| a | contrato `fixas` loja 1, parcela 1000, 10/09/2030, 6 parcelas, sem filtro | 6 linhas `divida`, −1000, de 10/09/2030 a 10/02/2031, `descricao` começa com `'Parcela 1/6'` |
| b | contrato `fixas` loja 1, parcela 500, 15/09/2030, 3 parcelas, `santri_cadastro` `'TESTE-CRED'` + título `Aberto` desse cadastro em 15/10/2030 de 500 | parcelas de set e nov entram, out não; Σ de out (título + parcela) = −500 |
| c | contrato `santri` loja 1 | nenhuma linha `divida` |
| d | título a pagar loja 1, cadastro `'TESTE-L2'`, aberto, 20/09/2030, 300 | `{1}`: −300 em 20/09, grupo `entre_lojas` · `{2}`: +300 em 20/09, `entre_lojas` · `{1,2}`: ausente |
| e | título a pagar loja 1, cadastro `'TESTE-L2'`, vencido 01/07/2030, 200, sem triagem | `{1}`: −200 em 04/09 · `{2}`: +200 em 04/09 · `{1,2}`: ausente |
| f | título a receber loja 2, cadastro `'TESTE-L1'`, aberto, 20/09/2030, 300 | ausente em `{2}` e em `{1,2}` (o espelho de d já cobre) |
| g | contrato `entre_lojas` loja 1 → outra_loja 2, `fixas`, 100, 25/09/2030, 1 parcela | `{1}`: −100 · `{2}`: +100 · `{1,2}`: ausente |
| h | contrato `fixas` loja 1, 1 parcela de 40 em 01/08/2030 (antes de hoje, não ligada) | nenhuma linha de 40 |

```sql
assert (select coalesce(sum(valor),0) from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where grupo = 'entre_lojas') = 0
   and not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where grupo = 'entre_lojas'), 'FALHOU total sem entre lojas';
assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and data > '2031-08-31'), 'FALHOU horizonte';
-- caixa_movimentos (só lançado) continua sem origem divida
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Escrever a migration** (recriar `caixa_lancado` e `caixa_fluxo` partindo da `migration_49b`, sem mudar o resto do corpo).
- [ ] **Step 4: Pedir ao Bruno os códigos das lojas.** Rodar a consulta abaixo e mostrar o resultado **só no chat** (nada em arquivo): "Pelo Santri, o código X aparece como credor nas contas da loja 1 e Y nas da loja 2. X = RV e Y = PVA? E o código Z, também com nome Dom Gabriel, é qual empresa?". Com a resposta, gravar com `salvar_cadastros_loja` (via `execute_sql` com os claims do admin). Se Z não for loja do caixa (ex.: Chapadão do Sul), não entra em `cadastros_santri`: os títulos dele seguem como dívida comum e o Bruno pode cadastrar o contrato tipo `chapadao`.

```sql
select t.lado, t.loja_id, t.cadastro_codigo, count(*) from public.titulos_santri t
where t.nome ~* 'dom gabriel' and t.ultima_importacao_id = interno.titulos_ultima_importacao(t.lado) group by 1,2,3 order by 1,2,4 desc;
```

- [ ] **Step 5: Aplicar e rodar** `teste_53`, `teste_44`, `teste_48`, `teste_49`, `teste_50`. Esperado: todos `OK-ROLLBACK`. Com dados reais: `tela_caixa(0)` abaixo de 5 s, e `atrasado_pagar` do Total menor que antes (sem entre lojas) — conferir só o sinal, sem copiar o número.
- [ ] **Step 6: Docs, commit e push.** HANDOFF › Decisões: as decisões 1 e 2 deste plano. HANDOFF › Caixa: grupo `entre_lojas`, espelho, origem `divida`.

```bash
git add sql/migration_53_caixa_dividas.sql sql/testes/teste_53_caixa_dividas.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: parcelas de dívida fora do Santri na projeção, entre lojas espelhado e fora do Total (migration 53)"
git push
```

---

### Task 3: Renegociado vira parcelas (migration 54)

**Files:**
- Create: `sql/migration_54_renegociacao.sql`
- Create: `sql/testes/teste_54_renegociacao.sql`
- Modify: `sql/testes/teste_43_titulos_tratativa.sql` (o caso `renegociado` passa a esperar o erro novo)

**Interfaces:**
- Consumes: Task 1 (`salvar_divida`), Task 2 (`caixa_lancado`).
- Produces:
  - `public.titulos_tratativa.divida_id bigint references dividas` (coluna nova; também em `titulos_tratativa_eventos`).
  - `public.renegociar_titulos(p_ids bigint[], p_dados jsonb) returns bigint`: `p_dados` = `{credor, tipo, parcela, primeiro_venc, n_parcelas, taxa_mes, nota}` (credor padrão = `nome` do maior título). Todos os títulos: lado pagar, mesma loja, status vencido ou aberto, sem tratativa `renegociado`. Cria o contrato (`origem='renegociacao'`, `modo='fixas'`, `saldo_informado` = Σ saldo em aberto, `saldo_data` = hoje) e grava tratativa `renegociado` com `nova_data = primeiro_venc` e `divida_id` + evento. Erros: `'Títulos de lojas diferentes'`, `'Só contas a pagar'`, `'Título já renegociado'`.
  - `public.tratar_titulos(p_ids, p_decisao, p_nova_data, p_nota)` (mesma assinatura): `renegociado` → erro `'Use Renegociar, que cria as parcelas'`; título com tratativa `renegociado` e contrato ativo → erro `'Título renegociado: desative o contrato na aba Dívidas'`.
  - `public.salvar_divida`: ao desativar contrato `origem='renegociacao'`, os títulos ligados voltam para `para_diretoria` com nota `'contrato de renegociação desativado'` (evento gravado).
  - `interno.caixa_lancado`: título com tratativa `renegociado` e contrato ativo não sai. `interno.divida_casa` ignora esses títulos (já previsto na Task 1: conferir).
  - `kpi.atrasado_pagar` e a lista `atrasados` de `tela_caixa` continuam mostrando o título renegociado (com a decisão), porque ainda está aberto no Santri.

- [ ] **Step 1: Teste SQL** (`teste_54…`, hoje `'2030-09-04'`). Dois títulos a pagar loja 1, cadastro `'TESTE-CRED3'`, vencidos: `t1` em 01/06/2030 de 900 e `t2` em **03/09/2030** de 100 (mesmo mês da 1ª parcela, Review Focus 1).

```sql
d := public.renegociar_titulos(array[t1, t2], '{"credor":"CREDOR TESTE","tipo":"outro","parcela":250,"primeiro_venc":"2030-09-10","n_parcelas":4}');
assert (select origem from public.dividas where id = d) = 'renegociacao' and (select saldo_informado from public.dividas where id = d) = 1000, 'FALHOU contrato';
assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id in (t1, t2)), 'FALHOU titulos fora';
assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -250) = 4, 'FALHOU 4 parcelas';
-- Ana lança a 1ª parcela no Santri: título novo do mesmo cadastro, aberto, 10/09/2030, 250 → a parcela de set sai do caixa, o título entra, t2 (set, renegociado) não liga
assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where data between '2030-09-01' and '2030-09-30' and (origem = 'divida' or titulo_id = t3)) = -250, 'FALHOU sem dobro no mes';
-- erros: tratar_titulos(array[t1], 'pagar_em', ...) → 'Título renegociado: desative o contrato na aba Dívidas'
--        tratar_titulos(array[t4], 'renegociado', ...) → 'Use Renegociar, que cria as parcelas'
perform public.salvar_divida(d, (select to_jsonb(x) - 'id' from public.dividas x where id = d) || '{"ativo":false}');
assert (select decisao from public.titulos_tratativa where titulo_id = t1) = 'para_diretoria', 'FALHOU volta para diretoria';
assert exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t1 and data = h), 'FALHOU titulo volta para semana 0';
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Escrever a migration** (coluna, `renegociar_titulos` + revoke/grant, recriar `tratar_titulos`, `salvar_divida` e `caixa_lancado` com a mesma assinatura).
- [ ] **Step 4: Aplicar e rodar** `teste_54`, `teste_53`, `teste_43` (ajustado), `teste_44`. Esperado: todos `OK-ROLLBACK`.
- [ ] **Step 5: Docs, commit e push.** HANDOFF › Decisões: a decisão 3. HANDOFF › Triagem: "renegociado só por `renegociar_titulos`".

```bash
git add sql/migration_54_renegociacao.sql sql/testes/ docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: renegociado vira contrato com parcelas, títulos antigos saem da projeção (migration 54)"
git push
```

---

### Task 4: Dívida total e `tela_dividas` (migration 55)

**Files:**
- Create: `sql/migration_55_tela_dividas.sql`
- Create: `sql/testes/teste_55_tela_dividas.sql`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `interno.dividas_resumo(p_lojas smallint[], p_hoje date) returns jsonb`: `{total, parcela_media_mes, contratos:[{id, credor, tipo, loja, outra_loja, modo, origem, saldo, saldo_data, saldo_estimado, taxa_mes, parcela, faltam, proxima, acaba_em, parcelas_santri, parcelas_fora, filtro_repetido}], sem_contrato:[{loja, cadastro, nome, plano_nome, parcelas, saldo, ultima}], curva:[{mes, saldo}]}`. Regras na tabela. Com mais de uma loja em `p_lojas`, contratos `entre_lojas` e títulos entre lojas ficam fora de `total`, `parcela_media_mes` e `curva` (aparecem na lista com `entre_lojas=true`). `filtro_repetido` = outro contrato ativo com o mesmo `santri_cadastro`, `santri_plano` e `santri_doc_prefixo`.
  - `public.tela_dividas(p_loja smallint, p_hoje date default null) returns jsonb`: exige `pode_ver_financeiro()`, `lojas := interno.lojas_tela(p_loja)`, devolve `dividas_resumo` + `hoje` + `cadastros: [{loja, cadastros_santri}]`.
  - `public.tela_caixa(p_loja, p_atrasados, p_vendas, p_entrada_pct, p_hoje)` (mesma assinatura): `kpi.divida = {total, parcela_media_mes, sem_contrato}` (só os números, sem a lista) e `divida` em cada `por_loja`. `kpi.atrasado_pagar`/`atrasado_nao_triado` sem entre lojas quando for mais de uma loja.

- [ ] **Step 1: Teste SQL** (`teste_55…`, hoje `'2030-09-04'`). Contratos e títulos inventados:

| Caso | Dados | Esperado em `dividas_resumo(array[1,2], h)` |
|---|---|---|
| a | `fixas` loja 1, `saldo_informado` 1200, taxa null, parcela 100, 01/10/2030, 24 parcelas | `saldo` 1200, `acaba_em` 2032-09-01, `faltam` 24 |
| b | `fixas` loja 1, sem saldo informado, parcela 50, 10/09/2030, 4 | `saldo` 200, `saldo_estimado` true |
| c | `fixas` loja 1, `saldo_informado` 1000, taxa 1, parcela 510, 15/09/2030, 2 | curva desse contrato: set → 1000, out → 500 (1000 × 1,01 − 510) |
| d | `entre_lojas` 1 → 2, saldo 300 | fora do `total`; em `dividas_resumo(array[1], h)` entra |
| e | título a pagar loja 2, plano classificado `divida`, cadastro `'TESTE-SEM'`, aberto 20/09/2030, 80, sem contrato | `sem_contrato` com 1 linha, saldo 80 |
| f | os contratos a e b com o mesmo filtro (`santri_cadastro` `'TESTE-REP'`, sem títulos) | a e b com `filtro_repetido` true, c com false |

```sql
r := interno.dividas_resumo(array[1,2]::smallint[], h);
assert (r->>'total')::numeric = 1200 + 200 + 1000 + 80, 'FALHOU total';
assert (r->'curva'->-1->>'mes') = '2032-09-01', 'FALHOU curva ate a ultima parcela';
assert (r->'curva'->0->>'saldo')::numeric = (r->>'total')::numeric, 'FALHOU curva comeca no total';
assert round((r->>'parcela_media_mes')::numeric, 2) = round((12*100 + 200 + 1020 + 80) / 12.0, 2), 'FALHOU parcela media';
t := public.tela_caixa(0::smallint, 'triagem', 'zero', null, h);
assert (t->'kpi'->'divida'->>'total')::numeric = (r->>'total')::numeric, 'FALHOU kpi';
-- anon sem EXECUTE em tela_dividas(smallint,date)
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Escrever a migration** (`dividas_resumo`, `tela_dividas`, recriar `interno.caixa_projecao` e `public.tela_caixa` das assinaturas novas da `migration_50` com o `kpi.divida`, revoke/grant das funções novas).
- [ ] **Step 4: Aplicar e rodar** `teste_55` e todos os anteriores do Caixa (`44`, `46`, `48`, `49`, `50`, `52`, `53`, `54`). Esperado: todos `OK-ROLLBACK`. Com dados reais: `tela_caixa(0)` e `tela_dividas(0)` abaixo de 5 s; conferir pela API com a chave publicável que anon recebe `permission denied` em `tela_dividas`.
- [ ] **Step 5: Docs, commit e push.**

```bash
git add sql/migration_55_tela_dividas.sql sql/testes/teste_55_tela_dividas.sql docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Caixa: dívida total, curva da dívida e tela_dividas (migration 55)"
git push
```

---

### Task 5: Tela Caixa — número Dívida total, aba Dívidas e Entre lojas

**Files:**
- Modify: `index.html` (bloco `// ---------- CAIXA ----------`: `CX_SAIDAS`, `CX_ENTRADAS`, `GRUPOS_CX`, `telaCaixaJ`, nova `abaDividasCx`, nova `graficoDividaCx`)
- Modify (fora do repo): `..\_testes\caixa\teste_caixa.mjs`, `gerar_mock.mjs`, `mock_tela_caixa.json`, novo `mock_tela_dividas.json`

**Interfaces:**
- Consumes: `tela_caixa` (`kpi.divida`), `tela_dividas(p_loja)`, `salvar_divida(p_id, p_dados)`, `salvar_cadastros_loja(p_loja, p_cadastros)`.
- Produces: `async function abaDividasCx() -> string` (carrega `tela_dividas` uma vez por loja, guarda em `CX.div`, invalidado junto com `CX.cache`), `function graficoDividaCx(curva) -> string` (SVG), `function modalDividaCx(contrato|null)`.

- [ ] **Step 1: Mocks e asserts do Playwright** (números e nomes inventados):
  - o topo tem 5 indicadores, o 5º "Dívida total" com sub "parcela média R$ … por mês"; clicar abre a aba Dívidas;
  - as abas são, nesta ordem: Projeção · Atrasados a pagar · Dívidas · Saldos;
  - a tabela da Projeção tem a linha "Entre lojas" em Entra e em Sai;
  - aba Dívidas: `#cxDivGrafico` com um `path.cxDivLinha`; a lista tem uma linha por contrato com Credor · Tipo · Loja · Saldo · Taxa · Parcela · Faltam · Acaba em · No Santri; contrato com `saldo_estimado` mostra "≈"; com `filtro_repetido` mostra o aviso "mesmo filtro de outro contrato";
  - "Sem contrato no Santri" lista as linhas de `sem_contrato`, e "Criar contrato" abre o modal já com o código do credor e o modo "Já está no Santri";
  - "Novo contrato" + preencher + Salvar chama `salvar_divida` com `p_id=null` e `p_dados.modo='fixas'`, `p_dados.parcela=1500` (digitado `1.500,00`);
  - "Códigos das lojas no Santri": mudar o de RV chama `salvar_cadastros_loja`;
  - 390 px: `scrollWidth <= 390`.
- [ ] **Step 2: Rodar e ver falhar** (`node teste_caixa.mjs`).
- [ ] **Step 3: Implementar.**
  - `CX_SAIDAS` ganha `'entre_lojas'` depois de `'divida'`; `CX_ENTRADAS` ganha `['entre_lojas','Entre lojas']`; `GRUPOS_CX` ganha `['entre_lojas','Entre lojas']`.
  - 5º `indCmp('Dívida total', milCmp(k.divida.total), 'parcela média '+milCmp(k.divida.parcela_media_mes)+' por mês', {aba:'div'})`. Quando `k.divida.sem_contrato > 0`, o sub acrescenta "· " + milCmp(sem_contrato) + " sem contrato". Linha por loja (Ambas) ganha a dívida.
  - Abas: `[['proj','Projeção'],['atr','Atrasados a pagar'],['div','Dívidas'],['sal','Saldos']]`.
  - `graficoDividaCx`: linha/área do saldo da `curva` mês a mês, rótulo do ano embaixo em cada janeiro, valor inicial e "acaba em mm/aaaa" escritos; `viewBox` responsivo.
  - Lista de contratos (`listaJ('cxDiv', …)`), ordenada por saldo; tipo com rótulos Banco · Parcelamento de imposto · Sócio · Entre lojas · Chapadão do Sul · Outro; "No Santri": "todas" / "n de N" / "não"; clique na linha abre `modalDividaCx`.
  - `modalDividaCx`: credor, tipo, loja (e outra loja se entre lojas), saldo devedor hoje, taxa % ao mês, modo ("Parcelas fixas" ou "Já está no Santri"), parcela, 1º vencimento, nº de parcelas (só no modo fixas), código do credor no Santri, plano e início do documento (opcionais, em "Ligar ao Santri"), observação, botão Desativar. Usa o mesmo conversor `num` dos saldos.
  - Bloco "Sem contrato no Santri" e bloco "Códigos das lojas no Santri" (um campo por loja, códigos separados por vírgula).
  - Nota no rodapé da aba: "Saldo: o informado no contrato ou, sem ele, a soma das parcelas que faltam (≈). A curva desconta as parcelas e soma os juros da taxa. Parcela que já está no contas a pagar do Santri não entra duas vezes no caixa. Entre lojas: aparece em cada loja e some no Total."
  - Nota da Projeção: tirar "Parcelas de dívida fora do Santri ainda não entram." e acrescentar "Parcelas de dívida fora do Santri entram como estimado (◐). Entre lojas some no Total."
- [ ] **Step 4: Rodar Playwright e `node --check`** (maior `<script>` do `index.html` num arquivo temporário). Esperado: `TUDO OK`, sem saída do `node --check`.
- [ ] **Step 5: Docs, commit e push** (HANDOFF › Tela Caixa: a aba Dívidas e o 5º número).

```bash
git add index.html docs/ALTERACOES.md docs/HANDOFF.md
git commit -m "Tela Caixa: Dívida total no topo, aba Dívidas com contratos e curva, linha Entre lojas"
git push
```

---

### Task 6: Triagem — "Renegociar" com parcelas

**Files:**
- Modify: `index.html` (`abaAtrasadosCx`)
- Modify (fora do repo): `..\_testes\caixa\teste_caixa.mjs`

**Interfaces:**
- Consumes: `renegociar_titulos(p_ids, p_dados)` (Task 3).

- [ ] **Step 1: Asserts do Playwright:** marcar 2 títulos + "Renegociado" + "Aplicar aos marcados" abre o modal "Renegociar" com o total marcado, credor = nome do maior; preencher 4 parcelas a partir de uma data mostra "4 × R$ …" (total ÷ 4, editável); Salvar chama `renegociar_titulos` com `p_ids` de 2 itens e `p_dados.n_parcelas=4`; título renegociado mostra a pill "renegociado · contrato" e não tem checkbox; títulos de lojas diferentes marcados → `toast` "Renegociar só títulos da mesma loja", sem chamar a RPC.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.** Na barra de ação, a opção passa a "Renegociado (vira parcelas)" e não mostra o campo de data; "Aplicar" abre o modal (credor, tipo, nº de parcelas, 1º vencimento, valor da parcela, taxa opcional, nota). Depois de gravar: `toast('Renegociação gravada: as parcelas estão na aba Dívidas')`, `CX.cache=null`, `CX.div=null`, recarrega.
- [ ] **Step 4: Rodar Playwright + `node --check`.** Esperado: passa.
- [ ] **Step 5: Docs, commit e push.** Em `docs/PROXIMOS_PASSOS.md` §0, F2: "plano 3 construído (dívidas, entre lojas, renegociação)"; tirar o item "Para o plano 3" das pendências.

```bash
git add index.html docs/ALTERACOES.md docs/HANDOFF.md docs/PROXIMOS_PASSOS.md
git commit -m "Tela Caixa: triagem Renegociado abre o contrato com parcelas"
git push
```

---

### Task 7: Primeira carga dos contratos (separada, só quando o Bruno avisar)

Roda **só quando o Bruno disser que ele e a Ana preencheram** a tabela "Dívidas — para o plano 3" do doc `https://claude.ai/artifact/SDzDcbosTwFowPbeAoExGw` (colunas: Credor · Tipo · Loja · Saldo devedor hoje · Taxa % ao mês · Parcela · Última parcela · Parcela no Santri?). Nada desta task vai para o repositório além de uma linha em `ALTERACOES.md` sem valores.

**Files:**
- Modify: `docs/ALTERACOES.md` (uma linha: "Primeira carga do cadastro de dívidas: N contratos", sem valores nem nomes)

- [ ] **Step 1: Ler a tabela** com o conector de docs (`read` do doc, tabela da seção "Dívidas — para o plano 3"). Linhas vazias ignoradas. Dúvida numa linha (tipo fora da lista, loja ilegível, valor sem número) → perguntar ao Bruno antes, uma pergunta por vez.
- [ ] **Step 2: Achar o credor no Santri** para cada linha: títulos a pagar da foto atual, mesma loja, `nome` parecido com o Credor. Montar no chat (não em arquivo) a proposta por linha: código do cadastro, plano, prefixo do documento quando o mesmo credor tem mais de um contrato, quantas parcelas abertas existem no Santri e a última data. Mostrar ao Bruno e esperar o "ok".
- [ ] **Step 3: Definir o modo de cada contrato.** "Parcela no Santri? Sim" e o Santri tem parcelas até a "Última parcela" → `santri`. Senão → `fixas`, com `primeiro_venc` = próximo vencimento a partir de hoje no dia da "Última parcela" (dia 29–31 → último dia do mês), `n_parcelas` = meses de `primeiro_venc` até a última, `parcela` = coluna Parcela, e o filtro do Santri preenchido quando houver título (para ligar as que já estão lá). Em todos: `saldo_informado` = Saldo devedor hoje, `saldo_data` = hoje, `taxa_mes` = Taxa.
- [ ] **Step 4: Gravar** com `salvar_divida` (via `execute_sql`, claims do admin do Bruno), um contrato por chamada, conferindo o id devolvido.
- [ ] **Step 5: Conferir com o Bruno** (no chat): `tela_dividas(0)` — Σ dos saldos = Σ da coluna Saldo do doc; lista "sem contrato" (o que o Santri tem no grupo Dívida e ficou sem contrato: cadastrar, ou reclassificar a conta no Plano de contas); `tela_caixa(0)` abaixo de 5 s e o novo número da Dívida total.
- [ ] **Step 6: Commit e push** da linha em `ALTERACOES.md`. No doc, marcar a tarefa "Preencher a tabela de dívidas" como feita.

```bash
git add docs/ALTERACOES.md
git commit -m "Caixa: primeira carga do cadastro de dívidas"
git push
```

## Ao terminar o plano (Tasks 1–6)

Avisar o Bruno em poucas linhas: o Total agora não conta entre lojas; o atrasado do grupo Dívida continua na semana 0 até a Ana triar ("Pagar em" ou "Renegociado"); a aba Dívidas já mostra o que está no Santri em "Sem contrato" e fica completa com a carga da Task 7. Pedir a revisão da Claude Opus nas regras de dinheiro (espelho entre lojas e renegociação).
