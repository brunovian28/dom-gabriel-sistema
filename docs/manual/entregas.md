# Entregas

**Onde fica:** menu lateral → grupo **Operação** → **Entregas**
**Última revisão:** 04/11/2026
**Quem vê:** direção, gerente, compras, financeiro e logística. O vendedor não vê esta tela.

## Para que serve

Responde três perguntas da logística:

1. **O que ainda falta entregar?** As entregas pendentes no Santri, com a data prometida ao cliente, e as que nem têm data.
2. **O que já saiu?** As entregas que já têm **nota fiscal de remessa**. É a prova de que a mercadoria saiu do depósito.
3. **O que está esquecido no Santri?** Manifesto que ficou aberto depois da entrega e entrega gerada que ainda não teve nota.

A regra que orienta tudo: **a entrega saiu quando existe a nota de remessa** (a nota "Entregas" ou "Entregas agrupadas" do Santri). O manifesto não é usado para dizer se saiu, porque a logística só fecha o manifesto depois, para ainda poder fazer devolução.

## Quem usa e para quê

| Perfil | Usa para |
| --- | --- |
| Logística | Ver o que falta entregar, reagendar o que venceu e fechar os manifestos antigos |
| Gerente | Cobrar dos vendedores as datas vencidas e as entregas sem agendamento |
| Direção | Ver quanto o cliente já pagou e ainda não recebeu, e quanto saiu no mês |
| Compras e financeiro | Só consulta |

## De onde vêm as informações

| Relatório do Santri | O que a tela mostra com ele |
| --- | --- |
| Entregas pendentes | O que falta entregar, a previsão de cada uma e as sem agendamento |
| Gerenciamento de entregas | As entregas geradas e a situação do manifesto |
| Notas fiscais emitidas (sintético) | A nota de remessa: se e quando a entrega saiu |
| Vendas e Baixas a receber | O vendedor e quanto o cliente já pagou |

No alto da tela aparece a data da última importação das **entregas** e das **notas fiscais**. Se a das notas estiver velha, a tela mostra como pendente uma entrega que já saiu. **Importe o relatório de notas toda semana, junto com os outros.**

## Como a tela é organizada

### 1. Os números do topo

| Quadro | O que mostra |
| --- | --- |
| Pendentes | Quantas entregas o Santri ainda tem como pendentes, e o valor |
| Pendentes com previsão vencida | Das pendentes, quantas já passaram da data prometida. Fica em destaque quando há alguma |
| Sem agendamento | Entregas pendentes que ainda não têm data |
| Pagas e ainda não entregues | O cliente já pagou (98% ou mais da venda) e a entrega ainda está pendente |
| Saíram no mês | Entregas com nota de remessa emitida no mês |
| Manifestos para fechar | A nota saiu há mais de 30 dias e o manifesto ainda está "Aguardando carregamento" |
| Geradas sem nota | Entrega gerada no Santri e a nota de remessa ainda não emitida |

### 2. As quatro abas

**Pendentes e sem agendamento · Manifesto para fechar · Saíram (30 dias) · Geradas sem nota.**

## Aba Pendentes e sem agendamento

A lista do que falta entregar, primeiro as pendentes (pela data prometida, da mais antiga para a mais nova) e depois as sem agendamento.

Cada linha traz o pedido, a situação, o cliente, o telefone, a data do cadastro, a **maior previsão** de entrega dos itens, os **dias de atraso** (em vermelho), quantos itens faltam, o valor, **quanto o cliente já pagou** e o vendedor.

**O que fazer:**
- **Previsão vencida:** falar com o cliente, combinar a nova data e **atualizar a previsão no Santri**. Na próxima importação a linha sai do atraso.
- **Já foi entregue:** se a mercadoria saiu e a nota de remessa não foi emitida, emitir a nota. Depois de importar as notas, a entrega aparece em "Saíram".
- **Cliente desistiu ou devolveu:** cancelar a entrega no Santri.
- **Sem agendamento:** combinar a data com o cliente e lançar a previsão.

Linhas com mais de um ano de atraso quase sempre são cadastro antigo que ficou aberto. Confira e limpe no Santri.

## Aba Manifesto para fechar

Entregas que **já saíram com nota de remessa há mais de 30 dias** e continuam com o manifesto "Aguardando carregamento". Mostra o pedido, o número da entrega, o cliente, o local, a nota, a data em que saiu e há quantos dias.

**Regra:** fechar o manifesto no Santri **até 30 dias depois da nota**. Não precisa fechar na hora da entrega, porque depois de fechado o Santri não deixa fazer devolução. Mostra até 1.000 linhas, as mais antigas primeiro. Use **Baixar planilha** para dividir a limpeza.

## Aba Saíram (30 dias)

Entregas com nota de remessa emitida nos últimos 30 dias, com a nota, a data, o valor e o vendedor. Serve para conferir o que saiu e responder ao cliente ou ao vendedor.

## Aba Geradas sem nota

Entregas geradas no Santri (manifesto aberto) que ainda **não têm nota de remessa**. Mostra há quantos dias foi gerada (vermelho depois de 7), a situação da separação, o peso e a cidade.

**O que fazer:** se a mercadoria já saiu, emitir a nota de remessa. Se ainda vai sair, é a fila de carregamento. Se foi gerada por engano, cancelar no Santri.

## Rotina do dia a dia

### Logística
1. Olhe **Geradas sem nota**: o que já saiu precisa de nota.
2. Em **Pendentes**, reagende com o cliente as de previsão vencida, começando pelas **pagas**.
3. Uma vez por semana, feche um lote de **Manifesto para fechar**.
4. Importe o relatório de **notas fiscais** toda semana.

### Gerente
1. Olhe **Pendentes com previsão vencida** e **Sem agendamento** e cobre o vendedor de cada uma.

### Direção
1. Olhe **Pagas e ainda não entregues** (dinheiro do cliente que ainda é obrigação nossa) e **Saíram no mês**.

## Dúvidas comuns

**A entrega já saiu e aparece como pendente.**
Ou a nota de remessa não foi emitida, ou o relatório de notas não foi importado depois da emissão. Confira a data das "notas fiscais" no alto da tela.

**A nota juntou duas entregas ("Entregas agrupadas"). Ela conta?**
Conta. Quando o mesmo cliente tem mercadoria em depósitos diferentes, o Santri gera duas ordens de entrega e uma nota só. O sistema liga a nota às entregas do mesmo cliente (pelo número do pedido na observação da nota ou, sem ele, pelas entregas geradas nos 30 dias antes da nota).

**A nota de simples faturamento conta como entrega?**
Não. A nota de simples faturamento (venda para entrega futura) e a nota de serviço (comissão de venda direta) não mostram que a mercadoria saiu. Só a nota de remessa conta.

**Por que o número de pendentes aqui é diferente do "Pronto para entregar" da tela Pedidos?**
Aqui estão todas as entregas pendentes no Santri. Em Pedidos, "Pronto para entregar" são só as pendentes cuja mercadoria **já chegou** ao depósito.

## O que ainda não existe

- **Tela do entregador no celular:** o entregador marcar na hora a entrega feita (data real, quem levou, veículo). A parte das notas já está pronta; falta a tela e o cadastro de entregadores e veículos.
- **Frete por entrega:** quanto custou cada viagem e quantas entregas cada entregador fez.
