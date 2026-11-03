# Registro de alterações

Uma linha por alteração, **a mais nova no topo**. Quem entra lê daqui para baixo até a última linha que já conhece.

**Última migration: 59** (a próxima é a 60 — avise antes de criar).

| Data | Quem | O que mudou | Migration | Commit |
| --- | --- | --- | --- | --- |
| 03/11/2026 | Bruno (Claude Sonnet) | Pedidos: datas de entrega e "cliente precisa" passam a existir no sistema, com histórico de mudanças (tabelas `pedido_datas` e `pedido_datas_eventos`, RPCs `salvar_datas_pedido` e `dados_lancar_pedido`). Gerente, logística, direção e admin alteram qualquer pedido da loja, vendedor só os dele | 59 | ver git log |
| 03/11/2026 | Bruno (Claude Opus) | Tela Financeiro: botão "Baixar títulos vencidos (planilha)" com todos os vencidos a pagar e a receber (RPC `exportar_titulos_vencidos`), com colunas em branco para o financeiro anotar a análise e o ajuste no Santri. Objetivo: limpar no Santri os lançamentos antigos errados | 58 | ver git log |
| 03/11/2026 | Bruno (Claude Opus) | Desempenho depois da importação do histórico completo do Santri. `titulos_aberto` ignora títulos Baixados (eram 60 mil dos 66 mil e saíam como pago), `caixa_fluxo` lê só 6 meses de títulos a pagar, painel da Direção e Financeiro calculam a última importação do DRE e dos títulos uma vez só (antes era linha a linha), e a tela de Compras liga venda → compra por junção em vez de varredura. Resultados conferidos iguais. Caixa (projeção das 2 lojas) 7,5 s → 1,3 s · DRE+títulos do painel ~3,5 s → 0,14 s · ligação de Compras 1,7 s → 0,3 s | 57, 57b, 57c, 57d | ver git log |
| 03/11/2026 | Bruno (Claude Opus) | Barra lateral em grupos que abrem para baixo: Direção solta no topo, depois Vendas, Operação, Financeiro e Configuração. O grupo da tela aberta já vem aberto e cada pessoa guarda quais deixou abertos. Celular sem mudança | — | ver git log |
| 03/11/2026 | Bruno (Claude Opus) | Revisão do plano 3 da F2: parcela de renegociação só liga a título do Santri de valor parecido (compra nova do mesmo fornecedor fazia a parcela sumir do caixa) · contrato de renegociação desativado não volta (contaria em dobro) · editar contrato exige permissão na loja atual · renegociar título da outra loja cria contrato entre lojas | 56 | ver git log |
| 03/11/2026 | Bruno (Claude) | Tela Caixa: triagem "Renegociado" abre o contrato com parcelas. Fecha as Tasks 1 a 6 do plano 3 da F2 | — | ver git log |
| 03/11/2026 | Bruno (Claude) | Tela Caixa: Dívida total no topo, aba Dívidas com contratos, curva e sem contrato, códigos das lojas e linha Entre lojas | — | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 3, Task 4: dívida total, curva da dívida e `tela_dividas`; atrasado do Total sem entre lojas | 55 | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 3, Task 3: Renegociado vira contrato com parcelas (`renegociar_titulos`), títulos antigos saem da projeção | 54 | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 3, Task 2: parcelas de dívida fora do Santri na projeção e entre lojas espelhado e fora do Total; códigos das lojas no Santri gravados | 53 | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 3, Task 1: cadastro de dívidas (contratos, parcelas, eventos), ligação ao Santri e códigos das lojas no Santri | 52 | ver git log |
| 02/11/2026 | Bruno (Claude) | Revisão do plano 2 da F2: rascunho do plano de contas corrigido. Compra de mercadoria vira fornecedor (contava em dobro com o custo das vendas futuras), investimento e formas de pagamento saem do custo fixo, CSLL vai para impostos | 51 | ver git log |
| 03/11/2026 | Bruno (Claude) | Tela Caixa: chaves "Vendas futuras" e "% à vista", valores estimados marcados com ◐, linha Vendas futuras, detalhe com estimativas e dias de pagar a RT e os impostos. Fecha o plano 2 da F2 | — | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 2, Task 4: `tela_caixa` e `caixa_detalhe` com as chaves de vendas futuras e % à vista (versões novas sem default, antigas viram atalho) | 50 | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 2, Task 3: vendas futuras com recebimento pelo perfil, custo das vendas, RT dos arquitetos e impostos das vendas, em `caixa_fluxo` (ainda não aparecem na tela) | 49, 49b | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 2, Task 2: custo fixo recorrente estimado (média de 6 meses menos o lançado) em `caixa_fluxo` | 48 | ver git log |
| 03/11/2026 | Bruno (Claude) | Caixa plano 2, Task 1: perfil das vendas (média, percentuais, ritmo de recebimento) e dias de pagar a RT e os impostos por loja | 47 | ver git log |
| 02/11/2026 | Bruno (Claude) | Revisão do plano 1 da F2: baixa parcial não marca mais o título como pago (só baixas depois da foto contam e o parcial é descontado) · saldo do caixa só por conta bancária (Compras leva para Caixa › Saldos, fim do saldo em dobro) · funções internas do caixa fechadas para anon | 46 | ver git log |
| 02/11/2026 | Bruno (Claude) | Segurança: RPCs novas do Caixa fechadas para anon e public (REVOKE). Regra nova: toda função public.* termina com revoke + grant authenticated | 45 | ver git log |
| 02/11/2026 | Bruno (Claude) | Tela Caixa: aba Saldos (contas bancárias, informar saldos, caixa mínimo). Fecha o plano 1 da F2 | — | ver git log |
| 02/11/2026 | Bruno (Claude) | Tela Caixa: aba Atrasados a pagar com triagem em lote | — | ver git log |
| 02/11/2026 | Bruno (Claude) | Tela Caixa: números do topo e projeção semana a semana / mês a mês (menu Caixa) | — | ver git log |
| 02/11/2026 | Bruno (Claude) | Caixa (F2): projeção de 13 semanas e 12 meses com o que está lançado, atrasados pela triagem (RPCs `tela_caixa` e `caixa_detalhe`) | 44, 44b, 44c | ver git log |
| 02/11/2026 | Bruno (Claude) | Caixa (F2): triagem dos títulos atrasados com histórico (decisão por título, em lote) | 43 | ver git log |
| 02/11/2026 | Bruno (Claude) | Caixa (F2): contas bancárias com saldo por conta, caixa mínimo por loja; Compras soma as contas | 42 | ver git log |
| 02/11/2026 | Bruno (Claude) | Caixa (F2) · base comum: classificação do plano de contas por grupo do caixa, status único do título (pago/aberto/vencido) e tela Plano de contas na Direção | 41 | ver git log |
| 01/11/2026 | Bruno (Claude) | Segurança: funções do banco (SECURITY DEFINER) não podem mais ser chamadas sem login (anon perde EXECUTE; funções novas já nascem fechadas). Spec da F1 (DRE gerencial) em `docs/superpowers/specs/` | 40 | ver git log |
| 20/10/2026 | Bruno (Claude) | CLAUDE.md: regra "faça, não mostre" (sem copiar e colar código) | — | ver git log |
| 20/10/2026 | Bruno (Claude) | Docs para trabalho a dois: `CLAUDE.md`, `docs/HANDOFF.md`, `docs/ALTERACOES.md`, `docs/PROXIMOS_PASSOS.md`; migrations 26–39 copiadas para `sql/` | — | ver git log |
| 20/10/2026 | Bruno (Claude) | Compras refeita no padrão por setor: indicadores no topo, caixa para comprar (saldo informado), fila de compra com marcação por item, "Faturadas: trazer agora?", Corrigir, Analisar | 39, 39b, 39c | 60e9689 |
| 16/10/2026 | Bruno (Claude) | Telas da jornada: Direção, Orçamentos, Recebimentos, Chegada, Entregas, Estoque, Financeiro; coluna "No Santri" em Pedidos | 38 | 8fee442 |
| 16/10/2026 | Bruno (Claude) | Importadora: loja escolhida à mão quando o arquivo não tem PVA_/RV_ | — | 75ff1f7 |
| 16/10/2026 | Bruno (Claude) | Leitores: orçamentos, baixas, entregas, estoque por local, contas a pagar/receber, DRE; entrega concluída = "Entrega total" | 30–37 | b70a13b |
| 16/10/2026 | Bruno (Claude) | Entradas: reposição (CFOP x.949) e revenda sem compra = estoque | 29 | — |
| 15/10/2026 | Bruno (Claude) | Rotina de relatórios, aviso de relatório atrasado, importação por setor, leitor de entradas | 28a–28d | c8cfab7 |
| 13/10/2026 | Bruno (Claude) | Compras do Santri (importação + tela) | 27 | 1d3565d |
| 08/10/2026 | Bruno (Claude) | Vendas do Santri (importação, MC por venda, pendências de pedido) | 26 | b9072fb |
| até 30/09/2026 | Bruno (Claude) | Base: cadastros, capas, orçamentos, negociação, pedidos, painel, Importadora de produtos e preços | 01–25 | — |
