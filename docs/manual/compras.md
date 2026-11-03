# Compras

**Onde fica:** menu lateral → grupo **Operação** → **Compras**
**Última revisão:** 03/11/2026
**Quem vê:** direção, gerente, compras, financeiro e logística. O vendedor não vê esta tela.

## Para que serve

Responde três perguntas de quem compra:

1. **O que eu preciso comprar agora?** São as vendas que o cliente já pagou e que ainda não têm compra feita.
2. **O que já comprei e ainda não chegou?** A mercadoria que está na fábrica, a que a fábrica já faturou e a que está no depósito esperando o cliente.
3. **O que está errado ou esquecido?** Compra sem o cliente ter pago, compra parada há muito tempo, venda paga que ficou sem compra.

A regra que orienta tudo: **a compra é liberada quando o cliente paga a primeira parcela** (cartão antecipado conta como quase à vista). A meta é comprar em até **7 dias** depois do pagamento.

## Quem usa e para quê

| Perfil | Usa para |
| --- | --- |
| Compras | Fazer a fila de compra do dia, cobrar a fábrica e anotar o retorno |
| Gerente | Acompanhar o prazo entre o pagamento e a compra e as compras fora da regra |
| Direção | Ver quanto está parado na fábrica e em trânsito, e se o caixa dá para comprar |
| Logística | Decidir com Compras quando trazer a mercadoria faturada |
| Financeiro | Só consulta (caixa para comprar e compras sem pagamento do cliente) |

Quem **marca a fila** ("já comprado", "saiu do estoque"…) e **anota o retorno** das compras: direção, gerente e compras. Financeiro e logística só consultam.

## De onde vêm as informações

| Relatório do Santri | O que a tela mostra com ele |
| --- | --- |
| Vendas | As vendas e os itens que precisam de compra |
| Baixas a receber | Se o cliente já pagou, e quando |
| Compras | O que já foi comprado, de quem, e se já entrou |
| Notas de entrada | Se a fábrica já faturou e se a mercadoria já chegou |
| Gerenciamento de entregas | A situação da entrega ao cliente |
| Notas fiscais emitidas | Se a entrega já saiu (nota de remessa) |
| Estoque | Se a loja já tem o produto |

No alto da tela aparece a data e a hora da última importação de cada um. Se estiver velha, a tela mostra o passado. A ligação entre uma venda e uma compra é **sugerida pelo produto** (mesmo código, ou, no revestimento, a mesma linha e marca), até o Santri trazer o número da venda no relatório de compras.

## Como a tela é organizada

### 1. Os cinco números do topo

Cada quadro é clicável e leva ao assunto.

| Quadro | O que mostra |
| --- | --- |
| Fila de compra | Quantas vendas já pagas ainda estão sem compra, o valor a custo e quantas esperam há mais de 7 dias |
| Prazo pago → compra | A mediana de dias entre o pagamento do cliente e o cadastro da compra (últimos 90 dias) e a % feita em até 7 dias. Vermelho se passar de 7 dias |
| Comprado no mês | O que foi comprado no mês, comparado com o que foi vendido a custo, e o mesmo do mês passado |
| Em trânsito | O valor que está na fábrica (comprado, sem nota) mais o faturado (nota emitida, mercadoria ainda não baixada) |
| Fora da regra | Compras sem pagamento do cliente mais compras na fábrica há mais de 60 dias |

### 2. Caixa para comprar (próximos 30 dias)

Aparece para quem vê o financeiro. Mostra, semana a semana, o saldo informado mais o que vai entrar, menos o que vai sair e menos a fila de compra, e diz em uma frase se **dá para comprar** (sobra) ou **falta** dinheiro. Se ninguém informou o saldo das contas, a frase pede isso: o botão **Informar no Caixa** leva à aba de saldos.

Fora da conta ficam os títulos vencidos, mostrados numa linha de aviso. A frase de apoio é: **compre primeiro o que o cliente pagou há mais tempo.**

### 3. As quatro abas

**Comprar · Acompanhar · Corrigir · Analisar.** É a ordem do trabalho.

## Aba Comprar

Duas listas:

- **Comprar agora:** vendas dos últimos 60 dias com a primeira parcela paga e itens sem compra encontrada no Santri, e sem estoque suficiente na loja.
- **Tem estoque na loja: conferir:** vendas pagas, sem compra, mas em que a loja tem o produto. O item pode ter saído do estoque, ou o estoque ser de outro cliente esperando entrega. Confira e marque, ou compre.

Cada linha traz a venda, o cliente, quando foi fechada, **quando foi paga**, **quantos dias** faz (vermelho depois de 7), quanto já foi pago, os itens que faltam comprar (com custo e quanto tem no estoque) e o custo total.

**Marcar o item.** Ao lado de cada item há um seletor **marcar…** que tira o item da fila:

| Marca | Quando usar |
| --- | --- |
| Já comprado | A compra existe, mas o sistema não conseguiu ligar à venda |
| Saiu do estoque | O produto saiu do estoque da loja |
| Venda direta | A fábrica entrega direto ao cliente |
| Não comprar | Não vai ser comprado |

Avisos que a tela dá:
- Aparece uma faixa avisando quantas vendas dos últimos 60 dias têm itens a comprar **sem nenhum pagamento encontrado**. Regra: não comprar até o cliente pagar a primeira parcela.
- Argamassas (Portokoll, Ceramfix, Sika) ficam fora da fila: são compra para estoque.
- Rio Verde costuma lançar a compra no Santri só quando a nota chega. Até lançar, a venda continua na fila. Por isso o prazo de Rio Verde aparece maior do que o real.

## Aba Acompanhar

No alto, três etapas em sequência, do que já foi comprado:

1. **Na fábrica:** compras sem nota. A fábrica ainda não faturou.
2. **Faturada (fábrica ou transportadora):** a nota chegou e a mercadoria ainda não foi baixada no Santri. Está na fábrica ou na transportadora.
3. **No depósito, aguardando o cliente:** os pedidos "Pronto para entregar" da tela Pedidos, ou seja, a mercadoria já chegou e o Santri ainda tem entrega pendente. Mostra o valor, quantos pedidos e quantos estão sem previsão. Clicar abre a tela Pedidos já filtrada.

Três listas:

- **Faturadas: trazer agora?** Notas de revenda que já chegaram e a mercadoria ainda não. A coluna **O que fazer** diz:

  | Aviso | O que significa |
  | --- | --- |
  | Trazer: entrega gerada | O cliente já tem entrega gerada no Santri |
  | Trazer: cliente espera dd/mm | A entrega está prevista para os próximos 10 dias |
  | Aguardar: previsão dd/mm | A entrega do cliente é mais para a frente |
  | Previsão vencida: confirmar | A data do cliente passou |
  | Confirmar data com o cliente | A venda não tem data de entrega no Santri |
  | Entregue? Dar baixa na nota | Todos os clientes ligados já foram entregues |
  | Sem venda ligada (estoque?) | Não achou venda: provavelmente é estoque |

  **Antes de pedir para trazer, confirme se o cliente quer receber agora.** Mercadoria que chega sem entrega marcada ocupa o depósito.
- **Na fábrica:** compras abertas sem nenhuma nota e sem item com entrada. **Mais de 60 dias é alerta**: cobrar a fábrica ou cancelar no Santri. Mostra o número do pedido na fábrica e as vendas e entregas ligadas.
- **Todas as compras abertas:** a lista geral. Clicar numa compra abre os itens e o histórico das mudanças. Aqui se **anota o retorno** ("fábrica disse que sai dia 15"): a anotação fica guardada mesmo quando a compra é importada de novo.

Todas as listas têm busca e o botão **Baixar planilha**.

## Aba Corrigir

O número na aba é o do quadro **Fora da regra**.

| Lista | O que mostra | O que fazer |
| --- | --- | --- |
| Compra sem pagamento do cliente | Compras dos últimos 90 dias ligadas a uma venda sem pagamento até 3 dias depois | Pode ser compra sem o cliente pagar, ligação errada (outra venda do mesmo produto) ou pagamento no cartão que o Santri não ligou ao pedido. Conferir com o financeiro |
| Paradas +60 dias | Compras abertas há mais de 60 dias sem entrada | Cobrar a fábrica ou cancelar no Santri |
| Venda paga sem compra +60 dias | Vendas pagas, de 60 a 180 dias atrás, com itens sem compra | Quase sempre é ligação que o sistema não achou (outro código, outro fornecedor, saiu do estoque). Confira as maiores |
| Compra sem venda vinculada | Compras dos últimos 12 meses sem venda ligada | Conferir se é compra para estoque |
| Acima do custo da promoção | Em construção | — |

## Aba Analisar

- **Comprado × vendido:** por mês e por loja, com barras. Como a compra vem depois da venda, um mês forte de vendas puxa as compras do mês seguinte.
- **Prazo:** a mediana de dias entre o pagamento e a compra, por loja, e a % feita em até 7 dias.
- **Por fornecedor:** últimos 12 meses, com quantidade de compras, valor, quantas estão em aberto e a % que tem o número do pedido na fábrica. A mesma fábrica pode aparecer em mais de um cadastro (por exemplo, por centro de distribuição).

## Rotina do dia a dia

### Compras
1. Abra **Comprar** e faça a fila de cima para baixo, começando pelas que passaram de 7 dias.
2. Quem já foi comprado ou saiu do estoque, **marque** para sair da fila.
3. Olhe a lista **Tem estoque na loja: conferir**.
4. Em **Acompanhar → Na fábrica**, cobre as compras com mais de 60 dias e **anote o retorno**.
5. Em **Faturadas**, combine com a logística o que trazer.

### Gerente
1. Olhe o **Prazo pago → compra** e o **Fora da regra**.
2. Cobre a fila que passou de 7 dias.

### Direção
1. Olhe a frase do **Caixa para comprar**: dá para comprar ou falta dinheiro?
2. Olhe o **Em trânsito** e o **Comprado no mês** contra o vendido.

### Logística
1. Em **Faturadas: trazer agora?**, veja o que já tem entrega gerada e o que espera data.

## Dúvidas comuns

**A venda já foi comprada e continua na fila.**
A ligação é pelo produto. Se a compra foi feita com outro código, o sistema não liga. Marque **Já comprado**. Em Rio Verde, a compra só aparece no Santri quando a nota chega.

**O cliente pagou e a venda diz "sem pagamento".**
Pode ser pagamento no cartão que o Santri não ligou ao pedido. Confira com o financeiro.

**A tela pede o saldo das contas.**
O "Caixa para comprar" precisa do saldo informado. Informe em **Caixa → Saldos**.

**O número de Falta comprar aqui é diferente do da tela Pedidos.**
Esta tela olha só as vendas dos últimos 60 dias e inclui as que têm estoque na loja. As mais antigas ficam em **Corrigir → Venda paga sem compra +60 dias**. A tela Pedidos olha o último ano e já tira o que foi entregue.

**Os números de "No depósito" aqui e de "Pronto para entregar" em Pedidos são iguais?**
Sim, é o mesmo cálculo. Entrega que já saiu é reconhecida pela nota fiscal de remessa, não pelo manifesto.

**Na fábrica há muitas compras com mais de 60 dias.**
Parte é compra antiga que nunca foi baixada no Santri. Baixe a planilha da lista e confira uma a uma com a fábrica.

## O que ainda não existe

- **Acima do custo da promoção:** comparar o preço de cada compra com o custo da Formação de Custo e Preço do mês. Precisa guardar o histórico da Formação, que hoje a Importadora sobrescreve.
- **Aba de frete:** reais por tonelada por transportadora, fornecedor e mês, e notas sem CT-e. Está nos planos.
