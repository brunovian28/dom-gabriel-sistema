# Registro de alterações

Uma linha por alteração, **a mais nova no topo**. Quem entra lê daqui para baixo até a última linha que já conhece.

**Última migration: 44** (com 44b e 44c — a próxima é a 45 — avise antes de criar).

| Data | Quem | O que mudou | Migration | Commit |
| --- | --- | --- | --- | --- |
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
