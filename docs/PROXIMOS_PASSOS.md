# Próximos passos e ideias em aberto

Atualizado em 20/10/2026 (seção 0 em 01/11/2026). Antes de construir qualquer item, confirme com o Bruno as decisões marcadas como "falta decidir".

## 0. Módulo Controller (diretoria) — PRIORIDADE (01/11/2026)
Objetivo: dar clareza à diretoria (inclusive aos diretores comerciais) sobre margem, caixa, contas a pagar e a receber.

| # | Entrega | Situação |
|---|---|---|
| F1 | DRE gerencial (três momentos da venda) | **desenhada** — `docs/superpowers/specs/2026-11-01-dre-gerencial-design.md`. Não construir ainda |
| F2 | Fluxo de caixa + contas a pagar e a receber | **planos 1 a 3 construídos (03/11/2026):** base comum, saldos por conta, projeção do lançado, triagem dos atrasados, custo fixo recorrente, vendas futuras com custo, RT e impostos das vendas, chaves "Vendas futuras" e "% à vista", dívidas (contratos, parcelas, curva, "Dívida total"), entre lojas espelhado e fora do Total, e "Renegociado" virando parcelas (tela `#/caixa`). Falta a **carga dos contratos** (Task 7, quando o Bruno e a Ana preencherem a tabela) e o plano 4 (a receber/cobrança, foto semanal, Compras lendo a projeção). Desenho: `docs/superpowers/specs/2026-11-02-fluxo-caixa-design.md` |
| F3 | Simulador de decisões | depois |
| C1 | Discurso "juros pago pelo cliente" (tabela à vista × parcelas) | pequena |
| B1 | Balanço gerencial (reaproveita saldos, títulos, dívidas da F2 + carteira e bens da F1 + estoque) | depois da F1 |
| F4 | Visão do investidor (padrão de mercado) | depois do balanço |

Ordem de construção: **base comum** (classificação do plano de contas, status pago/aberto/vencido único, unidades) → **F2 caixa** (a dor mais urgente) → **F1 DRE** → **B1 balanço** → F4.

### Pendências técnicas do plano 1 da F2 (02/11/2026)
- Atrasado marcado "Não é dívida" some da lista e não há tela para desfazer nem para listar as tarefas "corrigir no Santri".
- Conta bancária desativada não tem botão de reativar.
- ~~Revisão da Claude Opus nas regras de dinheiro~~ feita em 02/11/2026 (migration 46: baixa parcial e saldo em dobro).
- `statement_timeout 60s` dentro das funções do caixa não vale: o limite real é 8 s do papel `authenticated`. Depois do plano 3, `tela_caixa(0)` leva ~4,3 s: `caixa_fluxo` (~1 s) roda três vezes (Total + cada loja). Saída quando passar de 5 s: calcular o fluxo uma vez para as duas lojas sem o filtro final e derivar o Total (sem `entre_lojas`) e cada loja (filtro por `loja_id`, espelhos incluídos) dessa mesma lista.

### Tarefas do Bruno (fora do sistema, antes/durante a F2)
1. Organizar e aprender a parametrizar a antecipação do cartão no Santri.
2. ~~Descobrir onde está lançada a comissão~~ respondido 02/11/2026: paga na folha (entra no custo fixo de salários).
3. Primeira carga do cadastro de dívidas (contratos, saldos, taxas).
4. Definir o caixa mínimo de cada loja.
5. Revisar o rascunho da classificação do plano de contas (Direção › Plano de contas). Agora pesa no caixa: conta marcada "fixa recorrente" vira média mensal projetada pelos 12 meses. Começar por **DESPESA NÃO DEDUTIVEL** (a maior estimativa de fixo depois de salários: se não se repete todo mês, desmarcar "fixa").
6. Retomar a importação semanal (relatórios parados em 16/10).

## 1. Funil do cliente numa página só (ideia do Bruno, 20/10)
Uma página à vista de todos com um card por cliente/pedido que anda sozinho da prospecção à entrega. No card: situação e datas importantes. No futuro, cada mudança de coluna dispara ou sugere uma mensagem ao cliente.

| # | Coluna | O que move o card | Dado já existe? | Mensagem ao cliente (futuro) |
| --- | --- | --- | --- | --- |
| 1 | Prospecção | capa criada (obra/contato novo) | capas (vendedores ainda não usam) | — |
| 2 | Atendimento | capa com qualificação e produtos vistos | capas | — |
| 3 | Orçamento | orçamento no Santri ou PDF na capa | `orcamentos_santri` | — |
| 4 | Negociação | proposta enviada / orçamento quente | capas | — |
| 5 | Venda fechada | pedido no relatório de vendas | `vendas_santri` | pedido confirmado |
| 6 | Pago | 1ª parcela nas baixas a receber | `interno.pagamento_pedidos()` | pagamento confirmado |
| 7 | Comprado | compra ligada à venda | sugerida (ver `tela_compras`) | pedido enviado à fábrica |
| 8 | Faturado na fábrica | nota de entrada lançada | `entradas_santri` (Aberta) | material pronto |
| 9 | No depósito | baixa da nota | `entradas_santri` (data_entrada) | chegou, agendar entrega? |
| 10 | Entregue | manifesto baixado / "Entrega total" | `entregas_santri` | entregue |
| 11 | Pós-venda | feedback registrado | não existe | pedido de avaliação |

Card: cliente, obra, vendedor, valor, MC, % pago, datas (cliente precisa, fim da guarda, produção, chegada, entrega), vermelho quando passa do prazo da coluna. Primeira versão possível com as colunas 3, 5, 6, 7, 8, 9 e 10.
Falta decidir: quem vê (todos? vendedor só os dele?), prazos de cada coluna, canal das mensagens (WhatsApp?).

## 2. Datas do pedido (conversa de 20/10, pausada)
1. **Guarda grátis** no depósito: 6 meses, depois cobra. Falta decidir: valor e forma (por mês, por m², % do valor); contar do fechamento (decisão antiga) ou da chegada.
2. **Quantidade de entregas:** regra de entregas incluídas e cobrança acima disso. Proposta: 1 entrega a cada R$ 25 mil vendidos (mín. 1, máx. 3), extra cobrada por viagem. Falta decidir a regra e o valor.
3. **Cliente precisa (data de solicitação):** X dias antes, tarefa "confirmar com o cliente" (confirmado / adiou com nova data e motivo / cancelou). Só trazer da fábrica/transportadora com data confirmada. Falta decidir: quem liga (vendedor ou pessoa fixa) e onde mora a data (previsão de entrega do item no Santri ou capa do pedido no sistema).
4. **Produção na fábrica:** carteira das fábricas (Deca: prazo ATP; Portinari: data prazo/status). Precisa do nº do pedido no fornecedor na compra (só PVA preenche).
5. **Chegada na loja:** previsto = produção + trânsito; realizado = baixa da nota.
6. **Entrega ao cliente:** previsto = data confirmada; realizado = hoje não é confiável (o manifesto não é processo padrão, ver HANDOFF › Decisões). Futuro: o app de entrega (item 8).
7. **Feedback:** entrega + ~5 dias, pós-venda.

8. **App de entrega no celular (ideia do Bruno, 03/11/2026):** a logística emite a NF de entrega no Santri e importa o relatório de notas fiscais na Importadora, o que já cria a entrega numa página feita para celular. O entregador marca ali as entregas que fez (data real). Dá para controlar quem fez o frete, quantos fretes e o custo. Depois de uns meses a logística fecha o manifesto no Santri e o sistema confere os dois. **Status (03/11/2026):** a parte das notas está construída — tabela `notas_saida` (migrations 63, 63b, 65), leitor na Importadora (sintético e analítico) e uso na tela Pedidos (a nota de remessa marca a entrega real, migration 64). Falta a primeira carga e investigar as "Entregas agrupadas". Ainda não feito: tela mobile para o entregador (login simples) e cadastro de entregadores/veículos.
   - **Relatório escolhido (03/11/2026):** "Relação de Notas Fiscais" **sintético** do Santri, filtro por data de emissão, todas as empresas e todos os tipos de movimento (exemplo em `ERP Interno\aleatorios\`, fora do repo). As duas lojas vêm no mesmo arquivo (linha "1 - 1 - PVA" / "2 - 2 - RV" antes de cada bloco). Primeira carga desde 01/01/2026, depois semanal.
   - **Como liga (conferido com out/2026):** coluna "Tipo de movimento" + "Cód. movimento". `Pedido` (nota de faturamento, CFOP 5.922) → código = nº do pedido (`vendas_santri.numero`, 90 de 90). `Entregas` (nota de remessa, CFOP 5.117) → código = nº da entrega (`entregas_santri.entrega`, 167 de 168), que diz o pedido. `Entregas agrupadas`: **o código NÃO é o da entrega** (outra numeração, do agrupamento; na carga completa só 8 de 874 "ligações" tinham o mesmo cliente). Hoje elas não marcam entregue (migration 66 exige mesmo cliente). Pendente: perguntar à logística o que é "entrega agrupada" no Santri e achar onde o Santri mostra quais entregas/pedidos estão em cada agrupamento (são 1.698 notas no histórico). Também vêm devolução de venda, retorno parcial de entrega, cancelamento de entrega, baixa de perda, transferência.
   - **Uso:** nota de remessa = a mercadoria daquela entrega saiu (data real = emissão). 56 entregas de out/2026 tinham remessa e manifesto ainda "Aguardando carregamento", o que confirma que o manifesto não serve de "realizado". Trocar a regra de "entregue" da `tela_pedidos` para usar a remessa.

Princípio: toda data tem dono, previsto e realizado.

## 3. Refazer as outras páginas no padrão de Compras
Topo com os números que norteiam o setor; abaixo, o trabalho na ordem. Ordem sugerida: Chegada/Entregas (logística), Recebimentos/Financeiro, Orçamentos, Estoque, Direção.

## 4. Compras — continuação
- Aba de Frete: reais por tonelada por transportadora/fornecedor/mês, notas sem CT-e, frete por venda (rateio por peso). Meta 470 por tonelada.
- Topo: custo real (nota + CT-e) × custo usado na negociação.
- Alerta de compra acima do custo da promoção: precisa de leitor do log de custos do Santri (histórico da Formação).

## 5. Outros
- Vendedores começarem a usar capas e pedidos; metas do mês; "Nome no Santri" de cada vendedor.
- Pedidos à Santri: nº da venda no relatório de compras, data do orçamento no relatório de vendas, previsão de entrega por item.
- Exportar contas a pagar/receber por vencimento (hoje por emissão).
- `hoje()` do front usa UTC; trocar pela data local em todas as telas.
