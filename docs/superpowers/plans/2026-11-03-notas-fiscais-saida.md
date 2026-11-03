# Notas fiscais de saída (entrega real) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Importadora passa a ler o relatório "Relação de Notas Fiscais" (sintético) do Santri, e a tela Pedidos passa a usar a **nota de remessa** como prova de que a mercadoria saiu (data real = emissão da nota).

**Architecture:** Tabela `notas_saida` (uma linha por nota, com histórico em `notas_saida_eventos`), alimentada pelo caminho padrão da Importadora: leitor no navegador → `notas_saida_staging` → `previa_importacao_notas_saida` → `aplicar_importacao_notas_saida`. Nota que estava no sistema e não veio no arquivo, **dentro do mesmo período de emissão**, vira `ativo=false` (nota cancelada/excluída). A `tela_pedidos` liga a nota de remessa à entrega (`entregas_santri.entrega`) e daí ao pedido.

**Tech Stack:** PostgreSQL (Supabase), `importadora.html` e `index.html` (HTML+JS puro), Playwright em `..\_testes\` (fora do repositório).

**Spec:** este documento + `docs/PROXIMOS_PASSOS.md` item 2.8 (relatório escolhido e como liga, conferido com out/2026) + `docs/HANDOFF.md` (Importadora, Decisões, Testes). Plano anterior: `docs/superpowers/plans/2026-11-03-pedidos-automaticos.md`. Arquivo de exemplo real (não commitar): `..\ERP Interno\aleatorios\Relação de Notas Fiscais - sintético - 03-11-2026.ods`.

**Fora deste plano:** app de entrega no celular, itens das notas (relatório analítico), frete por entregador.

## O relatório (conferido em 03/11/2026)

- Cabeçalho do Santri nas primeiras linhas; antes de cada bloco de loja, uma linha só com `"1 - 1 - PVA"` ou `"2 - 2 - RV"` (loja = código depois do segundo ` - `, usar `L_.loja`). As duas lojas vêm no mesmo arquivo.
- Linha de colunas começa com `Dt. emissão`. Colunas usadas: `Dt. emissão`, `Cód.nota`, `Nr.nota`, `Série`, `Tipo doc.`, `Cliente / fornecedor` (`"código - nome"`, usar `L_.codNome`), `Valor total`, `CFOP` (`"5.117 - VENDA ..."`: guardar só o código `5117`), `Tipo de movimento`, `Cód. movimento`, `Chave NFE`, `Total peso`, `Usuário inserção`, `Observação`. Ignorar as colunas de impostos.
- Nota = linha cuja primeira célula é data `dd/mm/aaaa`. Números vêm com ponto de milhar (`"14.907"`): códigos com `L_.so` (só dígitos), valores com `L_.num`.
- No fim pode vir "Filtros selecionados" (mesmo tratamento dos outros leitores: `mostrarFiltros`). Se o filtro de tipo de movimento não incluir **Entregas** ou **Pedido**, aviso.
- Tipos de movimento vistos: `Entregas` (remessa, CFOP 5117/6117), `Pedido` (faturamento, 5922/6922), `Entregas agrupadas`, `Devolução de vendas`, `Retorno parcial de entrega`, `Dev. por canc. de entrega`, `Baixa de perda`, `Outras notas`, `Transferência`. Guardar todos.

## Regras

| Item | Regra |
|---|---|
| Chave da nota | `(loja_id, cod_nota)` (`Cód.nota` é o código interno do Santri, único por loja). |
| Período do arquivo | menor e maior `emissao` do arquivo, por loja. Nota ativa do sistema nesse período e loja que não veio → `ativo=false` + evento `sumiu`. |
| Alterou | mesma chave com `assinatura` diferente (md5 dos campos guardados) → atualiza + evento `alterou`. Nova → insere + evento `novo`. |
| Remessa | `tipo_movimento in ('Entregas','Entregas agrupadas')` e ativa. `entrega` = `cod_movimento`. Liga a `entregas_santri` por `(loja_id, entrega)`. |
| Remessa cancelada | existe nota ativa `Dev. por canc. de entrega` com o mesmo `cod_movimento` e loja → a remessa não conta. |
| Faturamento | `tipo_movimento = 'Pedido'`: `cod_movimento` = nº do pedido (`vendas_santri.numero`). Só informativo nesta etapa. |
| Pedido entregue (novo, Task 3) | Pedido com remessa válida ligada e **fora das entregas pendentes** → `entrega = 'entregue'`, `entregue_em = max(emissão da remessa)`. Com remessa e ainda nas pendentes → `parcial`. As regras A/B/C atuais (entrega total, manifesto > 30 dias, presumido > 60 dias) continuam valendo para pedido **sem** remessa (anteriores à primeira carga). |
| Rotina | `relatorios_rotina`: tipo `notas_saida`, nome "Notas fiscais emitidas", setores `{logistica}`, prazo 7 dias, `tipos_importacao {notas_saida}`, `disponivel=true`. `menu_santri` e `filtros`: "Relação de Notas Fiscais, botão Planilha, versão sintética" · "Data de emissão: da última importação até hoje (primeira vez: desde 01/01/2026)" · "Empresa: as duas" · "Tipo de movimento: todos". |

## Global Constraints

- **Repositório público:** nunca commitar o arquivo do Santri, nomes de clientes, valores nem tokens. Testes com dados inventados (`'TESTE-…'`, códigos `'999990'`…), SQL em transação terminando em `raise exception 'OK-ROLLBACK'`.
- **Migrations:** a última é a **62**. Este plano usa **63** (Task 1) e **64** (Task 3). Antes de cada uma: `list_migrations` e `docs/ALTERACOES.md`; se o Luis usou, próximo livre. Arquivo `sql/migration_NN_nome.sql` com a versão final.
- `apply_migration` volta "cancelled" se um texto entre aspas tiver `;` (usar vírgula). Sem `DROP`/`DELETE` (o conector recusa): staging é limpa como nos outros tipos (ver `aplicar_importacao_entregas` na migration 32 e repetir o mesmo jeito).
- Toda função nova: `security definer`, `set search_path to ''`, `revoke ... from anon, public` e `grant ... to authenticated` (avisar o Bruno que o conector pede aprovação para o REVOKE). `get_advisors` (security) sem aviso de `anon`.
- RLS: leitura de `notas_saida`/`_eventos` = usuário ativo e loja visível; staging = dono da importação (igual `entregas_staging`). Permissão de importar = a mesma checagem das outras RPCs de importação (`relatorios_rotina.setores` + direção + "importa tudo").
- **Desempenho:** índice em `notas_saida (loja_id, tipo_movimento, cod_movimento) where ativo`. `tela_pedidos(0)` continua **abaixo de 2 s** (hoje 0,6 s), medido duas vezes.
- Ao fim de cada task: `docs/ALTERACOES.md` (+ "Última migration"), `docs/HANDOFF.md` (Importadora: relatório 12; tabela/RPC; regra de entregue), commit com `Co-Authored-By: <modelo> <noreply@anthropic.com>` e push no `main`.

## Review Focus

1. **Mesmo `cod_nota` nas duas lojas**: a chave é sempre `(loja_id, cod_nota)`. Teste na Task 1.
2. **Importar um período menor depois de um maior** (ex.: só a última semana) não pode desativar notas de fora desse período. Teste na Task 1.
3. **Remessa cancelada** (`Dev. por canc. de entrega` com o mesmo código) não marca o pedido como entregue. Teste na Task 3.
4. **Pedido entregue em duas remessas, uma ainda pendente** → `parcial`, não `entregue`. Teste na Task 3.
5. **Arquivo errado** (ex.: relatório de entregas ou o analítico) → o leitor avisa e não envia. Analítico (tem linhas "Produto") deve funcionar igual, ignorando os itens. Teste na Task 2.

---

### Task 1: Tabelas e importação no banco (migration 63)

**Files:** Create `sql/migration_63_notas_saida.sql`. Test `..\_testes\notas\teste_63.sql`.

**Interfaces — Produces:**
- `public.notas_saida(id bigint identity pk, loja_id smallint, cod_nota text, nr_nota text, serie text, emissao date, tipo_doc text, cliente_codigo text, cliente_nome text, valor_total numeric, cfop text, tipo_movimento text, cod_movimento text, chave_nfe text, peso numeric, usuario text, observacao text, ativo boolean default true, assinatura text, importacao_id bigint, primeira_importacao_id bigint, criado_em, atualizado_em, unique (loja_id, cod_nota))`.
- `public.notas_saida_eventos(id, nota_id, importacao_id, evento text check in ('novo','alterou','sumiu','voltou'), antes jsonb, em timestamptz)`.
- `public.notas_saida_staging(id, importacao_id, dados jsonb)`; `dados` = um registro do leitor (Task 2) com as chaves das colunas acima (sem `id`/datas de controle).
- `public.previa_importacao_notas_saida(p_importacao bigint) returns jsonb`: `{no_arquivo, pva, rv, de, ate, por_tipo:{tipo:n}, novos, alterados, iguais, sumiram, remessas, remessas_ligadas, pedidos_faturados, pedidos_no_sistema}` (`remessas_ligadas` = remessas cujo `cod_movimento` existe em `entregas_santri.entrega` da mesma loja).
- `public.aplicar_importacao_notas_saida(p_importacao bigint) returns jsonb` (mesmo retorno da prévia; grava; `importacoes.status = 'aplicada'`).
- Linha nova em `relatorios_rotina` (regras acima).

- [ ] **Step 1: Teste** (inventado, OK-ROLLBACK): importação A com 3 notas (loja 1 `'999991'` remessa, loja 2 `'999991'` faturamento, loja 1 `'999992'` devolução) entre 2030-01-01 e 2030-01-31 → 3 `novo`; importação B só com a nota loja 1 `'999991'` alterada no valor (emissão 2030-01-10, único registro do arquivo) → 1 `alterou`; a nota da loja 2 continua **ativa** (o período é por loja e a loja 2 não veio no arquivo); a loja 1 `'999992'` com emissão 2030-01-05 continua **ativa** (fora do período de B, que é só 2030-01-10); importação D com só a loja 1 `'999991'` e período que inclui 2030-01-05 (outra nota inventada da loja 1 com emissão 2030-01-01) → a `'999992'` vira `ativo=false` com evento `sumiu`; importação C igual à D → tudo `iguais`. Usuário sem permissão (papel `vendedor`) → erro.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Escrever e aplicar a migration 63** (seguir a estrutura da `migration_32_entregas_santri.sql`).
- [ ] **Step 4: Rodar o teste → só OK-ROLLBACK.** `get_advisors`.
- [ ] **Step 5: Docs e commit** `Importadora: notas fiscais de saída no banco (migration 63)`.

### Task 2: Leitor na Importadora

**Files:** Modify `importadora.html` (novo `lerRelatorioNotasSaida(rows)` perto de `lerRelatorioEntregas`; `conferirNotasSaida(rows,f)`; `if(TIPO()==='notas_saida') return conferirNotasSaida(rows,f);` em `lerArquivo`; bloco `DEST.rpc==='notas_saida'` em `previaNovos`). Test `..\_testes\notas\importadora_notas.spec.js` (Playwright, padrão HANDOFF › Testes, com um `.ods` **inventado** gerado no teste ou um `rows` inventado).

**Interfaces:** Consumes RPCs da Task 1. `DEST={imp:'notas_saida',stg:'notas_saida',rpc:'notas_saida'}`.

- Mensagem da conferência: "Notas no arquivo: N (PVA x · RV y) · remessas (entregas) r · faturamentos f · devoluções d · período dd/mm a dd/mm".
- Prévia: KPIs novos/alterados/iguais/sumiram + "r remessas, das quais k ligadas a entregas do sistema" + aviso `warn` se `remessas_ligadas < remessas` ("importe também o Gerenciamento de Entregas do mesmo período") + aviso se `sumiram > 0` ("canceladas/excluídas no Santri, ficam no histórico").

- [ ] **Step 1: Teste** com rows inventados de 2 lojas (incluindo uma linha "Produto" e itens do analítico, que devem ser ignorados, e uma linha de outro relatório → erro "É o relatório Relação de Notas Fiscais?"): confere contagem por loja e tipo, `cod_movimento` só dígitos, CFOP `'5117'`, envio chama a staging com `importacao_id`.
- [ ] **Step 2: Ver falhar.** **Step 3: Implementar.** **Step 4: Teste + `node --check` passam.** Rodar localmente com o arquivo real de exemplo **sem aplicar** (só até a prévia) e conferir: 322 notas, 85 PVA, 237 RV, 168 Entregas, 90 Pedido, 23 Entregas agrupadas.
- [ ] **Step 5: Commit** `Importadora: leitor da Relação de Notas Fiscais` + HANDOFF (relatório 12, como exportar).

### Task 3: Tela Pedidos usa a remessa (migration 64)

**Files:** Create `sql/migration_64_pedidos_remessa.sql` (nova versão de `tela_pedidos` com `create or replace`, mesma assinatura). Modify `index.html` (`pdLinha`: quando houver remessa, a coluna Entrega mostra "Saiu dd/mm · NF n"). Test `..\_testes\notas\teste_64.sql` + ajuste em `..\_testes\pedidos\tela_pedidos.spec.js`.

**Interfaces — Produces:** cada pedido do JSON ganha `remessa_em date` (maior emissão de remessa válida) e `remessa_nf text` (número da última). `entrega` e `entregue_em` seguem a regra "Pedido entregue (novo)".

- [ ] **Step 1: Teste** (inventado, OK-ROLLBACK): pedido com remessa válida e fora das pendentes → `entregue`, `entregue_em` = emissão; com remessa + pendente → `parcial`; remessa + `Dev. por canc. de entrega` do mesmo código → segue a regra antiga (sem remessa); pedido sem nota → resultado igual ao de hoje (comparar com a versão 62).
- [ ] **Step 2: Ver falhar.** **Step 3: Implementar** (CTE `rem` filtrada por loja e por `entrega` das entregas dos pedidos da janela, nunca a tabela inteira). **Step 4: Testes passam; `tela_pedidos(0)` < 2 s.**
- [ ] **Step 5: Commit** `Pedidos: nota de remessa marca a entrega real (migration 64)` + HANDOFF › Decisões (regra de entregue atualizada).

### Task 4: Primeira carga (com o Bruno)

- [ ] Pedir ao Bruno (ou à Andresa/Fran) o relatório sintético **desde 01/01/2026**, importar pela Importadora e aplicar.
- [ ] Conferir e mostrar ao Bruno: quantas remessas ligaram a entregas, quantos pedidos passaram a "entregue" pela nota, e quantos dos 374 de "Fechar manifesto" têm remessa (confirma que foram entregues).
- [ ] Investigar `Entregas agrupadas` que não ligam (em out/2026, 8 de 23): ver no banco se o código bate com outra coluna (`entregas_santri.pedido`?) e propor a regra ao Bruno antes de mudar.
