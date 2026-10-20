# Próximos passos e ideias em aberto

Atualizado em 20/10/2026. Antes de construir qualquer item, confirme com o Bruno as decisões marcadas como "falta decidir".

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
6. **Entrega ao cliente:** previsto = data confirmada; realizado = baixa do manifesto.
7. **Feedback:** entrega + ~5 dias, pós-venda.

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
