# Handoff técnico — Sistema interno Dom Gabriel

Atualizado em 20/10/2026. Leia junto com `docs/ALTERACOES.md` (o que mudou) e `docs/PROXIMOS_PASSOS.md` (o que está em aberto). Valores e dados de clientes não ficam aqui (repositório público).

## Contexto
- Dom Gabriel: revestimento, louças e metais. Duas lojas: **PVA** (Primavera do Leste-MT, `loja_id = 1`) e **RV** (Rio Verde-GO, `loja_id = 2`; Quirinópolis roda dentro de RV). Vende primeiro e compra depois (cliente paga → loja compra da fábrica → fábrica fatura → transportadora → depósito → entrega).
- ERP: **Santri**. Sem acesso ao banco; relatórios só em .ods. O sistema guarda o que o Santri não guarda e lê os relatórios pela Importadora.
- Direção: Bruno e Fabio. Operação e financeiro: Ana Emilia. Gerente comercial: Gabriel. Cada loja tem a sua compradora.

## Peças
| Peça | Onde |
| --- | --- |
| Banco | Supabase, org "Dom Gabriel", projeto `dom-gabriel-sistema` (id `vmpxssoyqfdnnyhnvkyl`) |
| Sistema | `index.html` (um arquivo: HTML + CSS + JS, supabase-js v2 via jsdelivr) |
| Importadora | `importadora.html` (leitores dos relatórios do Santri) |
| Publicação | GitHub Pages deste repositório: https://brunovian28.github.io/dom-gabriel-sistema/ |
| SQL | `sql/` (migrations 26 → 39; as anteriores só existem no banco) |

Na pasta do PC do Bruno o sistema se chama `sistema_dom_gabriel.html` (= `index.html` aqui).

## Usuários, papéis e segurança
- Usuário novo entra inativo; direção libera em Usuários (papel, loja, "vê as duas lojas", "importa todos os relatórios", "Nome no Santri").
- Papéis: `vendedor`, `gerente`, `compras`, `financeiro`, `logistica`, `direcao`, `admin`.
- Funções no schema `interno`: `e_ativo`, `meu_papel`, `minha_loja`, `ve_todas_lojas`, `le_todas_lojas`, `pode_ler_capa`, `pode_editar_capa`, `pode_ver_compras` (admin, direção, gerente, compras, financeiro, logística), `pode_ver_financeiro` (admin, direção, financeiro), `pode_importar(tipo)`, `lojas_tela(p_loja)` (0 = as duas, só para quem lê as duas).
- RLS com `(select interno.x())` (initplan) por desempenho — manter o padrão.
- Telas novas chamam uma RPC `SECURITY DEFINER` que checa papel e loja por dentro (o advisor avisa; é intencional).
- Desde a migration 40, o papel `anon` não executa funções do schema `public` (e as novas já nascem sem EXECUTE para anon). Função nova que a tela chama: `grant execute ... to authenticated`.
- Vendedor não vê Formação de Preço (ST, créditos, custo comercial), compras nem financeiro.

## Importadora (11 relatórios do Santri)
Padrão de todos: leitor JS confere com os totais e filtros do rodapé do relatório → tabela `*_staging` → prévia (RPC `previa_importacao_*`) → gravar sem DELETE (RPC `aplicar_importacao_*`, guarda eventos do que mudou, registro que sumiu vira `ativo=false`) → a Importadora limpa a staging → histórico em `importacoes`. Catálogo `relatorios_rotina` (filtros, setores, prazo); `status_relatorios()` alimenta o aviso de relatório atrasado.

| Relatório | Tabelas |
| --- | --- |
| Produtos | `produtos` |
| Formação de Custo e Preço (PVA_/RV_) | preços por loja (a importação sobrescreve; não guarda histórico) |
| Vendas e devoluções | `vendas_santri`, `vendas_santri_itens` |
| Orçamentos (abertos e cancelados) | `orcamentos_santri`, `_itens`, `_eventos` |
| Baixas a receber / a pagar | `baixas_santri` (lado), `_formas`, `_titulos`, `_eventos` |
| Compras | `compras_santri`, `compras_santri_itens`, `compras_santri_eventos` |
| Entradas (notas) | `entradas_santri`, `_itens`, `_compras` (nota × nº da compra), `_eventos` |
| Entregas | `entregas_santri`, `_itens`, `_eventos`; `entregas_pendentes` (foto) |
| Estoque por local (PVA_/RV_) | `estoque_foto` |
| Contas a pagar / a receber | `titulos_santri` (foto atual = `interno.titulos_ultima_importacao(lado)`) |
| DRE (PVA_/RV_) | `dre_santri` |

Detalhes úteis: venda direta = comissão de venda direta > 0; `pedido_numero` das baixas a receber vem do campo Documento (`13152/1-3`, `CAR…-ORC13152/…`); "Entrega total" = entrega concluída; Data de entrega do Santri = data em que a entrega foi gerada (não a real); tipo de nota pelo CFOP (`interno.tipo_entrada`: revenda, uso_consumo, amostra_bonificacao, reposicao, outras).

## Módulos e telas (rotas do `index.html`)
- **Capas de atendimento** (`#/capas`, `#/nova`): cliente/obra/profissionais, BANT, produtos vistos, checklist, orçamentos (leitor do PDF do Santri, versões, perda com motivo), negociação, pedido, linha do tempo.
- **Negociação:** RPC `calcular_negociacao` (fórmula da Formação de Custo e Preço do Santri; frete por tonelada de Parâmetros; cartão por condição; "juros pago pelo cliente" com desconto que mantém a margem).
- **Pedido:** PDF do pedido ou dados do relatório de vendas → MC real (`interno.calcular_mc_venda`), capa do pedido digital com etapas por setor (`pedidos`: datas, etapas `*_em`/`*_por`, `data_cliente_precisa`, `previsao_entrega`, `guarda_ate`, `local_mercadoria`).
- **Painel da gerência** (`#/painel`, RPC `painel_gerencia`, tabela `metas`).
- **Telas da jornada** (migration 38), cada uma com sua RPC: Direção `painel_direcao`, Orçamentos `tela_orcamentos`, Recebimentos `tela_recebimentos`, Chegada `tela_chegada`, Entregas `tela_entregas`, Estoque `tela_estoque`, Financeiro `tela_financeiro`. Helpers: `interno.pagamento_pedidos()`, `interno.categoria_pagar`, `interno.categoria_receber`, `interno.e_revestimento`.
- **Compras** (`#/compras`, refeita em 20/10, migration 39) — modelo para as outras páginas:
  - Topo: Fila de compra, Prazo pago → compra, Comprado no mês, Em trânsito, Fora da regra (clicáveis).
  - Caixa para comprar · 30 dias (só `pode_ver_financeiro`): saldo informado (`caixa_saldo`, RPC `informar_saldo_caixa`) + a receber − a pagar a vencer por semana − fila. Fora da conta: vencidos não baixados, antecipados (Pre), créditos.
  - Abas: Comprar (fila; marcação por item em `fila_compra_marcas` via `marcar_fila_compra`), Acompanhar (fábrica → faturada → depósito; "Faturadas: trazer agora?"), Corrigir, Analisar.
  - RPC `tela_compras(p_loja)`. Ligação venda × compra sugerida por item: mesma loja, compra de −3 a +150 dias do fechamento, mesmo código ou (revestimento) mesma família `interno.familia_produto`. Argamassas `interno.e_marca_estoque` ficam fora. Item com estoque ≥ quantidade vai para "conferir".
- **Base comum do Controller** (migration 41, F1+F2): tabela `plano_contas_classe` (grupo do caixa por conta do plano: fornecedor, pessoal, impostos, comissoes_rt, divida, fixo, outros, fora · `fixa` recorrente · colunas da F1 nulas), funções `interno.grupo_caixa_padrao` (heurística pelo nome), `interno.grupo_caixa` (tabela, senão heurística), `interno.status_titulo` (pago/aberto/vencido, regra única) e `interno.titulos_status(lado, hoje)` (foto atual + baixas ativas). Tela `#/plano-contas` (direção) com `lista_plano_contas` / `salvar_classe_conta`. Carga inicial é rascunho a revisar.
- **Contas bancárias e caixa mínimo** (migration 42): `contas_bancarias` (loja, banco, nome, ativo), `caixa_saldo.conta_id` (saldos antigos e o `informar_saldo_caixa` da Compras vão para a conta "Geral" da loja), `caixa_parametros` (caixa mínimo por loja). `interno.saldo_caixa(lojas)` = último saldo de cada conta ativa. RPCs `salvar_conta_bancaria`, `informar_saldo_conta`, `salvar_parametros_caixa`. `tela_compras` soma o saldo das contas (mesmo formato).
- **Triagem de títulos** (migration 43): `titulos_tratativa` (uma linha por título, `titulo_id` estável entre importações) + `titulos_tratativa_eventos` (histórico a cada gravação). RPC `tratar_titulos(ids, decisao, nova_data, nota)` em lote. A pagar: pagar_em, renegociado, em_disputa, nao_e_divida, para_diretoria. A receber: prometeu, negociando, perdido. pagar_em/renegociado/prometeu exigem data.
- **Caixa — projeção do lançado** (migration 44/44b/44c, RPCs `tela_caixa(p_loja, p_atrasados, p_hoje)` e `caixa_detalhe`): `interno.caixa_movimentos` gera a lista (data, grupo, valor ±) e `interno.caixa_projecao` agrega em 13 semanas (segunda a domingo) e 12 meses. Regras do lançado:
  - **A pagar:** aberto no vencimento. Fora: tipos Pre/Cre/Adi, pago (inclusive por baixa importada depois da foto) e conta do grupo `fora`.
  - **A pagar vencido:** sem triagem ou `para_diretoria` cai em hoje (pior caso). `pagar_em`/`renegociado` cai em `greatest(data, hoje)`. `em_disputa` e `nao_e_divida` ficam fora. Modo `pagar_tudo`: tudo em hoje, menos `nao_e_divida`.
  - **A receber:** aberto no vencimento (grupo `clientes`, ou `outros_entrada` para empréstimo/recuperação). Fora: Cartão (já antecipado), Crédito, Adiantamento, Previsão e crédito de fornecedor.
  - **A receber vencido:** até 60 dias entra em hoje+7. Mais de 60 dias só com `prometeu` (data anotada). `perdido` fica fora.
  - **Saldo:** soma do último saldo de cada conta ativa. `saldo.informado` só é verdadeiro quando TODA loja da tela tem ao menos um saldo. Sem isso `primeira_abaixo` vem nulo e a tela deve avisar "informe o saldo".
  - `atrasado_pagar`/`atrasados` ignoram `nao_e_divida`. `atualizado.titulos` = a importação mais antiga entre a pagar e a receber.
- **Tela Caixa** (`#/caixa`, papéis `admin`/`direcao`/`financeiro`): topo com 4 números (Saldo hoje, Primeira semana abaixo do mínimo, Maior buraco, Atrasado a pagar), aviso amarelo se a importação ou o saldo tiver mais de 7 dias, chave "Atrasados: seguir a triagem / Pagar tudo agora", abas Projeção (gráfico de barras do saldo no fim de cada período + tabela por grupo, semana a semana ou mês a mês, célula clicável abre `caixa_detalhe`), Atrasados a pagar (triagem em lote: filtros Todos/Sem decisão/Para a diretoria/Em disputa, marcar vários títulos, decisão + data + nota via `tratar_titulos`) e Saldos (contas bancárias por loja, "Informar saldos", "Nova conta", desativar conta, caixa mínimo por loja; saldo com mais de 7 dias fica vermelho). Conta desativada some da soma e não tem botão para reativar. Código no bloco `// ---------- CAIXA ----------` do `index.html` (`telaCaixaJ`, `graficoSaldoCx`, estado `CX`). Teste de tela: Playwright em `_testes/caixa/` (fora do repositório, mock com números inventados).
- **Direção:** Usuários, Parâmetros (`parametros_loja`), Condições de pagamento, Conferência de ST.
- Front: estado `J`, helpers `kpiJ`, `listaJ`/`csvJ` (lista com busca e planilha), `abasJ`, `mesNavJ`, `rpcJ`; padrão por setor: `indCmp`, `.topoSetor`, `.fluxo/.etapa`, `.cxM`.

## Decisões (regras de negócio)
- Pedido do Santri é a verdade da venda; nº do pedido = nº do orçamento. Margem do mês = vendas do Santri pela data de fechamento + pedidos lançados.
- Devolução desconta no mês em que aconteceu.
- Arquiteto (RT 5%), Goyases/Metropolitano e condição de pagamento vêm da capa do pedido preenchida pelo vendedor.
- Parcelado só cartão ou PIX (sem boleto). "Juros pago pelo cliente": nota à vista, desconto padrão = o máximo que mantém a margem.
- RV (GO) não tem ST. Em PVA, confiar no %ST do Santri.
- **Compra liberada quando o cliente paga a 1ª parcela** (cartão antecipado = quase à vista).
- Cada loja faz as próprias compras, dentro do mês (a tabela da fábrica muda todo mês).
- Dexco é paga antecipado (título "Pre"): não é dívida a pagar.
- Argamassa é compra para estoque. Revenda sem compra ligada = estoque. CFOP x.949 = reposição de quebra.
- Nota que chega = fábrica faturou; baixa da nota = mercadoria chegou.
- Antes de trazer a mercadoria para o depósito, confirmar a data com o cliente.
- Negociação de preço com a fábrica fica com o gerente comercial. Meta de frete de compras: R$ 470/t (o parâmetro da negociação segue R$ 625/t).
- Prazo de guarda conta a partir do fechamento do pedido (dias e cobrança em definição — ver `PROXIMOS_PASSOS.md`).
- Venda perdida fica no orçamento, com motivo.
- Cada setor importa só os próprios relatórios; direção e "importa tudo" importam todos.

## Testes
- Sintaxe: extrair o `<script>` do HTML e rodar `node --check`.
- Navegador: Playwright com Chromium; rotear `cdn.jsdelivr.net` para `node_modules/@supabase/supabase-js/dist/umd/supabase.js` e `*.supabase.co` para respostas simuladas (dados reais copiados do banco); sessão falsa no localStorage (`sb-vmpxssoyqfdnnyhnvkyl-auth-token`, JWT sem assinatura serve). Testar desktop e 390 px de largura (sem rolagem horizontal).
- RPC no banco real sem gravar nada:
  ```sql
  do $$ declare r jsonb; begin
    perform set_config('request.jwt.claims', '{"sub":"<uuid do seu usuário>","role":"authenticated"}', true);
    select public.tela_compras(0::smallint) into r;
    raise exception 'OK-ROLLBACK %', left(r::text, 2000);
  end $$;
  ```
- Supabase via conector: `apply_migration` volta "cancelled" se um texto entre aspas tiver ponto e vírgula, e às vezes com DELETE/REVOKE. Em plpgsql com variável e coluna de mesmo nome, usar `#variable_conflict use_column`. Para ajuste pequeno numa função grande dá para aplicar `replace()` sobre `pg_get_functiondef` num bloco DO (deixe o `.sql` em `sql/` com a versão final).

## Publicar
Editar `index.html` / `importadora.html` → testar → commit e push no `main` → GitHub Pages atualiza em ~1 minuto. Registrar em `docs/ALTERACOES.md`.
