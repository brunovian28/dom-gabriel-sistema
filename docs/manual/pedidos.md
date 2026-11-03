# Pedidos e mercadoria

**Onde fica:** menu lateral → grupo **Operação** → **Pedidos**
**Última revisão:** 03/11/2026

## Para que serve

Mostra tudo o que já foi vendido e ainda não chegou na mão do cliente, e em que ponto cada pedido está: esperando pagamento, esperando compra, na fábrica, a caminho, pronto na loja ou saindo para entrega.

A tela **se monta sozinha** com os relatórios do Santri. Ninguém precisa lançar o pedido no sistema para ele aparecer aqui.

## Quem usa e para quê

| Perfil | Usa para |
| --- | --- |
| Vendedor | Acompanhar os pedidos, combinar a data com o cliente e informar a previsão de entrega |
| Logística | Agendar entregas, reagendar as atrasadas e fechar no Santri os manifestos que ficaram abertos |
| Gerente | Ver pedidos parados, cobrar datas e perceber compras travadas |
| Direção | Visão das duas lojas: onde há mercadoria ou dinheiro parado |
| Compras e financeiro | Só consultam. Não alteram datas |

## De onde vêm as informações

A tela é tão atual quanto o último relatório importado. Cada informação vem de um relatório do Santri:

| Relatório | O que a tela mostra com ele |
| --- | --- |
| Vendas | O pedido, o cliente, o vendedor e o valor |
| Baixas a receber | Se o cliente já pagou |
| Compras | Se a mercadoria já foi comprada |
| Notas de entrada | Se a fábrica já faturou e se a mercadoria já chegou |
| Gerenciamento de entregas | Entregas agendadas, sem agendamento, manifesto aberto e entrega total |
| Notas fiscais emitidas | A nota de remessa, que prova que a mercadoria saiu |

No alto da tela aparece a **data e a hora da última importação** de vendas, entregas, compras, notas de entrada e pagamentos. Se uma delas estiver velha, a tela está mostrando o passado: avise quem importa. Cada setor importa os seus relatórios pela Importadora, que mostra o que está atrasado. As notas fiscais emitidas são importadas pela logística, uma vez por semana.

## Escolhendo a loja

Quem enxerga as duas lojas escolhe no menu lateral, em **Ver loja**: Ambas, PVA ou RV. Os demais veem a própria loja.

O vendedor vê só os próprios pedidos quando a direção liga o "Nome no Santri" dele ao cadastro de usuários. Enquanto essa ligação não existir, ele vê a loja toda.

## Como a tela é organizada

### 1. Faixa "onde está a mercadoria"

Cada quadro é uma etapa, com a quantidade de pedidos e o valor. **Clicar num quadro filtra a lista**; clicar de novo tira o filtro.

| Etapa | O que quer dizer |
| --- | --- |
| Aguardando pagamento | Falta comprar e o cliente ainda não pagou nada. A compra só é liberada depois do pagamento |
| Falta comprar | O cliente já pagou, mas a compra ainda não foi feita |
| Na fábrica | Já foi comprado, e a fábrica ainda não faturou |
| Faturado (a caminho) | A fábrica faturou, a mercadoria está vindo |
| Pronto para entregar | A mercadoria já está na loja (ou é de estoque). Falta entregar ao cliente |
| Saindo | O manifesto de entrega está aguardando carregamento há até 30 dias |

Quando o pedido tem vários itens, vale a etapa mais atrasada. Um pedido com um item "Falta comprar" e os outros prontos aparece em "Falta comprar".

### 2. Faixa de alertas

É o trabalho do dia. O número em vermelho é o que precisa de atenção. Clicar filtra a lista. Veja "O que fazer com cada alerta", mais abaixo.

### 3. Lista de pedidos

Uma linha por pedido. Dá para buscar por número do pedido, cliente ou vendedor, e marcar **Mostrar entregues (30 dias)** para ver também os pedidos entregues no último mês.

| Coluna | O que mostra |
| --- | --- |
| Pedido | Número no Santri e a loja |
| Cliente e Vendedor | Quem comprou e quem vendeu |
| Fechamento e Dias | Data do fechamento e há quantos dias. Fica vermelho depois de 60 dias sem entregar |
| Pagamento | Pago, pago em parte (com a %) ou sem pagamento |
| Mercadoria | A etapa e quantos itens já chegaram ("3 de 5 itens chegaram") |
| Entrega | A situação da entrega, a data em que a nota de remessa saiu ("Saiu 28/10 · NF …") e a previsão. Depois da previsão aparece se ela veio do **sistema** ou do **Santri** |
| Cliente precisa | A data limite que o cliente precisa receber, quando alguém informou |
| Alertas | O que está pendente naquele pedido |
| Botões | **Datas**, e **Lançar** ou **Capa** |

## Duas perguntas diferentes: etapa e entrega

- **Etapa (coluna Mercadoria):** onde está a mercadoria do pedido? Ainda na fábrica? Já chegou?
- **Entrega (coluna Entrega):** como está a entrega ao cliente?

| Situação da entrega | O que quer dizer |
| --- | --- |
| Agendada | Existe entrega pendente no Santri, com data |
| Sem agendamento | Existe entrega pendente no Santri, sem data |
| Manifesto gerado | A entrega foi gerada e o manifesto aguarda carregamento |
| Entrega parcial | Uma parte já saiu e outra ainda está pendente |
| Entregue | A mercadoria saiu |
| Sem info no Santri | O Santri não tem nenhuma entrega desse pedido |

## Quando o pedido conta como entregue

O sistema considera o pedido entregue quando não há mais entrega pendente dele no Santri **e** acontece uma destas coisas:

1. A **nota fiscal de remessa** da entrega foi emitida. A data dela aparece em "Saiu".
2. O Santri registra **entrega total**.
3. O **manifesto está aberto há mais de 30 dias**. O sistema entende que a mercadoria já foi entregue e só falta a logística fechar o manifesto (aparece o alerta "Fechar manifesto").
4. **Entregue presumido:** passaram mais de 60 dias do fechamento e o Santri não tem nenhum registro de entrega do pedido.

Pedido entregue sai da lista normal. Para vê-lo, marque "Mostrar entregues (30 dias)", ou clique no alerta "Fechar manifesto".

## Rotina do dia a dia

### Vendedor
1. Abra **Pedidos** e clique em **Sem previsão**.
2. Combine a data com o cliente e clique em **Datas** na linha do pedido para informar.
3. Olhe **Cliente precisa antes**: o cliente precisa receber antes da data prevista. Veja se dá para antecipar ou avise o cliente.
4. Se aparecer **Atualize no Santri**, corrija a previsão também no Santri.

### Logística
1. Trabalhe **Pronto para entregar**: agende no Santri o que está parado na loja.
2. Reagende os pedidos com **Previsão vencida**.
3. Feche no Santri os manifestos da lista **Fechar manifesto**. O certo é fechar até 30 dias depois da nota fiscal de entrega.
4. Importe as **notas fiscais emitidas** uma vez por semana.

### Gerente e direção
1. Olhe a faixa de etapas. Muitos pedidos em **Falta comprar** com cliente já pago é dinheiro do cliente parado esperando compra. **Aguardando pagamento** mostra a venda que ainda não virou dinheiro.
2. Olhe **Mais de 60 dias** nas linhas: pedido velho, ainda sem entrega.
3. Cobre as datas dos pedidos **Sem previsão**.

## Passo a passo

### Informar a data de entrega

1. Na linha do pedido, clique em **Datas**. Abre uma linha logo abaixo.
2. Preencha a **Previsão de entrega** e, se o cliente tiver um limite, a data em **Cliente precisa**.
3. Clique em **Salvar**.
4. Se a previsão ficar diferente da do Santri, o sistema avisa: **"Atualize a previsão também no Santri."** Faça isso para que os dois fiquem iguais.

Regras:
- A data pode ser informada **no sistema ou no Santri**. O ideal é deixar nos dois.
- Se ninguém informar a data no sistema, **vale a do Santri**.
- Quando a data que você informa é igual à do Santri, a tela mostra "(Santri)": está certo, vale a mesma data.
- Quem altera datas: vendedor, gerente, logística, direção e administração. Compras e financeiro só consultam.
- Fica guardado quem mudou a data e quando.

### Lançar o pedido (completar a capa)

Lançar **não é obrigatório** para o pedido aparecer na tela. O botão **Lançar** aparece nos pedidos que ainda não foram lançados e serve para deixar o pedido completo no sistema.

1. Clique em **Lançar**. O sistema procura a capa do cliente e abre a aba de pedido. Se não achar a capa, pergunta se você quer criar uma nova.
2. Os dados do Santri já vêm preenchidos: número, cliente, vendedor, itens e valores, a previsão de entrega, a data que o cliente precisa e as formas de pagamento que o cliente já pagou.
3. Você só confere e completa o que o Santri não sabe: a **condição de pagamento**, se **tem arquiteto** e se é **Goyases / Metropolitano**.
4. Clique em **Confirmar pedido**.

Depois de lançado, o botão **Lançar** vira **Capa**, que abre a capa do pedido.

> **[Direção]** É por essa capa que o sistema calcula a margem real do pedido. Pedido sem capa fica com a margem incompleta.

## O que fazer com cada alerta

| Alerta | O que significa | O que fazer |
| --- | --- | --- |
| Sem previsão | Nem o sistema nem o Santri têm data de entrega | Combinar a data com o cliente e informar em **Datas** |
| Previsão vencida | A data passou e o pedido não foi entregue | Reagendar |
| Atualize no Santri | A data do sistema é diferente da do Santri | Corrigir a data também no Santri |
| Cliente precisa antes | O cliente precisa receber antes da previsão | Antecipar a entrega ou avisar o cliente |
| Não lançados | Pedido ainda sem capa no sistema | Clicar em **Lançar** (não é obrigatório para acompanhar) |
| Fechar manifesto | A mercadoria já saiu e o manifesto continua aberto no Santri | A logística fecha no Santri |
| Mais de 60 dias | O pedido foi fechado há mais de 60 dias e não foi entregue | Verificar o que está travando |

## Dúvidas comuns

**O pedido não aparece na tela.**
Veja se: (1) é venda direta, que não aparece aqui; (2) foi fechado há mais de um ano; (3) é da outra loja, e então basta trocar em **Ver loja**; (4) o relatório de vendas ainda não foi importado (confira a data no alto da tela); (5) já foi entregue, e então marque **Mostrar entregues (30 dias)**.

**Já entregamos e o pedido continua em aberto.**
O sistema só sabe da entrega pelo Santri. Confira se a entrega foi gerada e a nota fiscal de remessa emitida, e se a logística já importou as notas fiscais da semana. Se a entrega nunca foi registrada no Santri, o pedido sai da lista sozinho depois de 60 dias do fechamento.

**Aparece "Falta comprar", mas a mercadoria já foi comprada.**
O sistema liga a venda à compra pelo código do produto (ou pela família e marca) dentro de um prazo de alguns dias. Se a compra foi feita com outro código, ou muito depois da venda, ele não consegue ligar. Peça para Compras marcar o item na fila da tela **Compras** (comprado ou estoque).

**O alerta "Atualize no Santri" não sai.**
Ele sai quando a previsão do Santri passa a ser igual à do sistema. Isso só aparece depois da próxima importação do relatório de entregas.

**O botão Datas não aparece para mim.**
Só vendedor, gerente, logística, direção e administração alteram datas. Compras e financeiro só consultam.

## O que ainda não existe

- **Aplicativo de entrega no celular:** o entregador marcaria no próprio celular as entregas que fez, a partir das notas fiscais. Ideia em estudo.
- **Regra do prazo de guarda** da mercadoria no depósito (prazo grátis e cobrança): ainda em definição.
