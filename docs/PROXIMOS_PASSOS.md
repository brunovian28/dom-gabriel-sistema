# Próximos passos e ideias em aberto

Atualizado em 20/10/2026 (seção 0 em 01/11/2026). Antes de construir qualquer item, confirme com o Bruno as decisões marcadas como "falta decidir".

## 0. Módulo Controller (diretoria) — PRIORIDADE (01/11/2026)
Objetivo: dar clareza à diretoria (inclusive aos diretores comerciais) sobre margem, caixa, contas a pagar e a receber.

| # | Entrega | Situação |
|---|---|---|
| F1 | DRE gerencial (três momentos da venda) | **desenhada** — `docs/superpowers/specs/2026-11-01-dre-gerencial-design.md`. Não construir ainda |
| F2 | Fluxo de caixa + contas a pagar e a receber | **plano 1 construído (02/11/2026):** base comum, saldos por conta, projeção do lançado, triagem dos atrasados (tela `#/caixa`). Faltam os planos 2–4 (fixo recorrente + vendas futuras · dívidas · a receber/cobrança, foto semanal, Compras lendo a projeção). Desenho: `docs/superpowers/specs/2026-11-02-fluxo-caixa-design.md` |
| F3 | Simulador de decisões | depois |
| C1 | Discurso "juros pago pelo cliente" (tabela à vista × parcelas) | pequena |
| B1 | Balanço gerencial (reaproveita saldos, títulos, dívidas da F2 + carteira e bens da F1 + estoque) | depois da F1 |
| F4 | Visão do investidor (padrão de mercado) | depois do balanço |

Ordem de construção: **base comum** (classificação do plano de contas, status pago/aberto/vencido único, unidades) → **F2 caixa** (a dor mais urgente) → **F1 DRE** → **B1 balanço** → F4.

### Pendências técnicas do plano 1 da F2 (02/11/2026)
- **Segurança (decidir com o Bruno):** as 8 RPCs novas (`tela_caixa`, `caixa_detalhe`, `tratar_titulos`, `informar_saldo_conta`, `salvar_conta_bancaria`, `salvar_parametros_caixa`, `lista_plano_contas`, `salvar_classe_conta`) ficaram executáveis por `anon` (o advisor avisa). Não vazam dado (cada uma checa o papel e devolve "acesso negado"), mas falta uma migration 45 só com `REVOKE EXECUTE ... FROM anon, public`. O conector pede aprovação para REVOKE. Vale também para as RPCs dos próximos planos: já nascem abertas.
- Atrasado marcado "Não é dívida" some da lista e não há tela para desfazer nem para listar as tarefas "corrigir no Santri".
- Conta bancária desativada não tem botão de reativar.
- Revisão da Claude Opus nas regras de dinheiro (`interno.caixa_movimentos`, `interno.caixa_projecao`).

### Tarefas do Bruno (fora do sistema, antes/durante a F2)
1. Organizar e aprender a parametrizar a antecipação do cartão no Santri.
2. Descobrir onde está lançada a comissão desde mar/2026 (paga sempre no mês seguinte, mas quase não aparece como título).
3. Primeira carga do cadastro de dívidas (contratos, saldos, taxas).
4. Definir o caixa mínimo de cada loja.
5. Revisar o rascunho da classificação do plano de contas (a Claude prepara).
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
