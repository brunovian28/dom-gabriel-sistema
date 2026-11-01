# F1 — DRE gerencial (Resultado do mês) — desenho

Data: 01/11/2026 · Autor: Bruno (com a Claude) · Situação: **aguardando revisão do Bruno**

Primeira entrega do módulo **Controller** (diretoria). Sem valores nem nomes neste documento (repositório público).

## 1. Objetivo

Mostrar à diretoria, de forma clara e com detalhe até cada venda e cada conta:
1. **Se está compensando vender** — margem de contribuição (MC) real × meta de 20%.
2. **Quanto sobra para pagar as contas e a dívida** — MC − custo fixo − juros − parcelas de dívida e investimentos.

Hoje a informação está misturada: a DRE do Santri é por caixa (só o que foi pago), mistura dívida antiga com imposto da venda e não separa Quirinópolis.

## 2. Ordem do módulo Controller

| # | Entrega | Situação |
|---|---|---|
| **F1** | DRE gerencial (este documento) | desenho |
| F2 | Fluxo de caixa (realizado + projetado) | depois da F1 — reaproveita a classificação das contas |
| F3 | Simulador de decisões (demissão, veículo, Quirinópolis, comissão da diretoria, nova empresa) | depois |
| C1 | Ferramenta do discurso "juros pago pelo cliente" (tabela à vista × parcelas na proposta) | pequena, entra quando der |
| F4 | Visão do investidor: DRE no padrão de mercado (CPC) + indicadores (dívida líquida/EBITDA, cobertura de juros, liquidez, ciclo de caixa) + estimativa de valor da empresa | depois do caixa e do balanço |
| — | Balanço; Chapadão do Sul (sistema próprio, emprestou dinheiro da loja) | depois de PVA e RV |

## 3. Conceito: os três momentos de uma venda

| Momento | O que acontece | O que fica real |
|---|---|---|
| **1 — Venda** (mês do fechamento) | Pedido fechado, nota de simples faturamento, cliente paga (cartão antecipado/PIX), loja paga a fábrica à vista | Receita, comissões, RT/Goyases, cartão |
| **2 — Chegada** | Nota de entrada da fábrica + CT-e (baixa da nota = chegou) | Custo da mercadoria, frete de compra |
| **3 — Entrega** | Nota fiscal oficial, entrega ao cliente | Custo de entrega (chapa/caminhão), impostos devidos |

**Decisão (30/10):** DRE 1 e DRE 2 são **a mesma DRE, do mês da venda, que vai ficando mais certa**. Cada valor é marcado como *estimado* ou *real*; a estimativa original é guardada para comparar "estimado na venda × hoje". A DRE 3 é outra régua de tempo (mês da entrega/nota oficial) — ver §8.

## 4. Estrutura da DRE

Uma coluna por unidade — **PVA · RV · Quirinópolis · Total**.

| Linha | Fonte | Estimado (momento 1) | Real |
|---|---|---|---|
| **Receita** = vendas fechadas no mês − devoluções do mês | Vendas do Santri | — | já é real |
| − Impostos sobre a venda (ICMS, PIS, COFINS) | alíquotas por loja (`parametros_loja`) | alíquota × venda | acerto oficial só na DRE 3 |
| − Custo da mercadoria | Formação/compra → nota de entrada | custo da Formação / do pedido | nota de entrada ligada à venda |
| − Frete de compra | R$/t × peso → CT-e | parâmetro R$/t × peso | CT-e rateado **por peso** |
| − Comissão dos vendedores | % da venda | — | real |
| − **Comissão da diretoria** (linha própria) | % sobre o faturamento | — | real |
| − RT e Goyases | capa do pedido | — | real |
| − Cartão (taxa + antecipação) | condição de pagamento | — | real |
| − Entrega ao cliente (chapa, frete terceirizado) | R$/t entregue | R$/t histórico × peso | rateio do mês por peso (§5.3) |
| **= MC** (R$ e % · meta 20%) | | | |
| − Custo fixo por grupo: Pessoal · Ocupação · Veículos (inclui desgaste) · Administrativo · Marketing · Bancos e tarifas | contas a pagar (§6) | | |
| **= Resultado da operação** | | | |
| − Juros de empréstimos e financiamentos | contas a pagar | | |
| − IRPJ/CSLL estimado | % parametrizado sobre o lucro positivo | | |
| **= Lucro do mês** | | | |
| − Parcelas de dívida (principal de empréstimos, parcelamento de impostos antigos) | contas a pagar | | fora da DRE: capacidade de pagamento |
| − Investimentos pagos (principal de financiamento de veículos, reformas, consórcios) | contas a pagar | | idem |
| − Empréstimos concedidos (ex.: abertura de Chapadão do Sul) | contas a pagar | | idem |
| **= Sobra / falta** | | | |

Regras que mudam em relação à DRE do Santri:
- Parcelamento de impostos antigos sai de "impostos sobre venda" e vai para dívida.
- Amortização de empréstimo/financiamento não é custo; fica no bloco de baixo.
- **Imposto e conta do mês não pagos aparecem mesmo assim** (competência). O atraso aparece na F2 (caixa) e no balanço.
- Empréstimo entre lojas (PVA ↔ RV) se anula na coluna Total.

## 5. Regras de cálculo

### 5.1 Venda → unidade
- Loja = loja da venda no Santri.
- Quirinópolis = vendas do(s) vendedor(es) cadastrados como Quirinópolis (cadastro vendedor → unidade). Venda de cliente de Quirinópolis feita por vendedor de RV fica em RV (teria acontecido de qualquer jeito).

### 5.2 Custo e frete reais (momento 2)
- Usa a ligação venda × compra que já existe (`tela_compras`: mesma loja, compra −3 a +150 dias, mesmo código ou mesma família). Item sem compra ligada **continua estimado** e conta como não confirmado.
- Frete do CT-e rateado por **peso** entre os itens da nota (decisão anterior do Bruno), não por valor como o Santri.

### 5.3 Custo de entrega (chapa / caminhão terceirizado)
- PVA paga chapa por tonelada; RV paga caminhão terceirizado + chapa por diária. Regra única para as duas: **R$ por tonelada entregue**.
- Estimado: R$/t médio da loja nos últimos 6 meses (contas "Despesa com chapa" e "Fretes pagos a terceiros" ÷ toneladas entregues) × peso da venda.
- Real: total dessas contas no mês ÷ entregas concluídas no mês, por peso. Cada venda recebe sua parte e o valor passa a "real".
- Consequência: a venda só fica 100% confirmada depois de entregue.

### 5.4 Comissões
- Vendedor e diretoria: custo da venda no **mês do fechamento** (DRE não muda se a regra de pagamento mudar).
- Quando a comissão é paga (mês seguinte ao fechamento, ou após a 1ª parcela recebida — mudança em estudo) é um parâmetro usado só na F2.
- % da diretoria por pessoa: cadastro visível só para direção/admin.

### 5.5 Desgaste de bens
- Cadastro de bens (veículos e, se quiserem, móveis/reforma): valor, data, vida útil em meses. Desgaste mensal = valor ÷ vida útil, no grupo do bem (Veículos etc.) enquanto estiver dentro da vida útil.

## 6. Custo fixo, dívida e investimentos (contas a pagar)

- Fonte: `titulos_santri` lado pagar (plano de contas + centro de custo), **pagos ou não**.
- Cada conta do plano é classificada uma vez pela direção: linha da DRE (grupo de custo fixo, variável, juros, dívida, investimento, empréstimo concedido, entre lojas, fora da DRE) e **regra do mês**:
  - **Mês anterior ao vencimento:** salários, encargos, impostos (se referem ao mês trabalhado/vendido).
  - **Mês da emissão:** o resto (aluguel, energia, combustível…).
- Cada conta também recebe a **linha equivalente na DRE padrão de mercado** (receita líquida, lucro bruto, despesas operacionais, depreciação, resultado financeiro, IR/CSLL), para a F4 sair sem reclassificar. O desgaste de bens fica marcado à parte para o EBITDA (= resultado da operação + desgaste) sair certo.
- A Claude prepara o rascunho da classificação; o Bruno confirma.
- Contas variáveis já calculadas por venda (comissões, chapa, frete de compra) não entram de novo pelo contas a pagar — servem só para apurar o real (§5.3) e conferir.
- Centro de custo QUIRINÓPOLIS → unidade Quirinópolis. **Decisão (01/11): Quirinópolis carrega só custos diretos** e o resultado dela se lê como "quanto contribui" para a estrutura de RV.

## 7. Cadastros novos (direção, em Parâmetros)

1. Plano de contas → linha da DRE + regra do mês.
2. Vendedor → unidade; centro de custo → unidade.
3. % da comissão da diretoria por pessoa (só direção/admin).
4. Bens com desgaste.
5. Alíquotas estimadas (ICMS/PIS/COFINS) por loja e % IRPJ/CSLL estimado — usar as que já existem em `parametros_loja` e completar.

## 8. Tela "Resultado do mês"

Rota nova na área da direção. Padrão do sistema: números que norteiam no topo, detalhe embaixo. Mês com ◀ ▶.

1. **Topo (total):** MC (R$, % × meta) · Resultado da operação · Sobra/falta para a dívida (com o total de parcelas) · % confirmado.
2. **Loja por loja** (sem filtro): uma linha por PVA, RV, Quirinópolis com os mesmos 4 números.
3. **Chave de visão:** *Gerencial — mês da venda* (DRE 1→2) · *Contábil — mês da entrega* (DRE 3: o que foi entregue no mês, de qualquer mês de venda, com os custos daquelas vendas). A visão contábil é aproximada pelas entregas concluídas — o sistema não lê as notas de saída.
4. **Os três momentos por mês de venda:** barra por mês (só vendido / chegou / entregue) + "MC estimada na venda → MC de hoje".
5. **Gráfico-cascata** (para onde vai o dinheiro).
6. **Tabela DRE**: colunas Estimado na venda · Hoje · Diferença · PVA · RV · Quirinópolis; ◐ marca linha com parte estimada.
7. **Ponte gerencial → contábil:** receita vendida no mês − vendido e ainda não entregue + entregue no mês de vendas antigas = receita contábil. A carteira (vendido e não entregue) é o elo e alimenta o balanço depois.

**Tudo abre:** cada linha desce em níveis (grupo → conta → títulos; ou linha → vendas, com o momento de cada uma e link para o pedido).

Esboço aprovado: `.superpowers/brainstorm/` na pasta do Bruno (`dre-momentos.html`), fora do repositório.

## 9. Acesso
- Tela e cadastros: `admin` e `direcao`, com acesso a tudo (inclui o % da comissão da diretoria por pessoa). **Decisão (01/11):** a operação/financeiro também é diretoria e vê tudo — o usuário dela deve ter papel `direcao`.
- Padrão do sistema: RPC `SECURITY DEFINER` que checa papel por dentro; RLS com `(select interno.funcao())`.

## 10. Riscos e pré-requisitos
- **Dados desatualizados:** relatórios do Santri parados em 16/10. Antes de mostrar números à diretoria, importar vendas, entradas, entregas e contas a pagar atualizados.
- **Mês de competência das contas:** o Bruno acredita que o relatório do Santri já traz a competência e a data de pagamento — confirmar no relatório. Se trouxer, a competência do Santri vale e a regra por tipo (§6) fica só para conta sem competência. Conta com dúvida de classificação é decidida item a item com o Bruno.
- **Ligação venda × compra sugerida:** onde falhar, fica estimado. Melhora se a Santri gravar o nº da venda na compra (pedido feito).
- A DRE do Santri não é usada como fonte (é por caixa); serve só para conferência.
- **Reforma tributária:** em 2026 as notas já destacam CBS 0,9% e IBS 0,1% em caráter de teste (compensados, LC 214/2025); em 2027 a CBS substitui PIS/COFINS; de 2029 a 2032 o ICMS cai gradualmente e o IBS sobe; em 2033 o ICMS acaba. As alíquotas estimadas da DRE 1 ficam em parâmetros com data de vigência, para mudar sem mexer no cálculo.
- Regras de skills financeiras de padrão americano (`financial-analyst`, `month-end-close`) são conferidas contra a norma brasileira (CPC/CFC, legislação) antes de usar.

## 11. Testes
- Cálculo: conferir uma venda nos três momentos (estimado → custo real → entrega real) contra a capa do pedido e a nota de entrada.
- Conferir que a soma das contas classificadas bate com o total do contas a pagar do período (nada perdido, nada duplicado).
- Conferir que empréstimo entre lojas zera no Total.
- RPC no banco real sem gravar (bloco DO com rollback, ver HANDOFF).
- Tela: Playwright, desktop e 390 px (sem rolagem horizontal).

## 12. Estacionado para depois
- Perguntas e acréscimos do Bruno (ainda não listados).
- Módulo de integração da Santri (visões Oracle `VW_WEB_*`, pago): pode substituir a importação manual de vendas, títulos, entregas e notas.
- Fluxo de caixa (F2), simulador (F3), discurso do cartão (C1), balanço, Chapadão do Sul.
- Entender a DRE do Santri junto com o Bruno.
