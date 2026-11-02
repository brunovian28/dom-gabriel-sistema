# F2 — Fluxo de caixa + contas a pagar e a receber — desenho

Data: 02/11/2026 · Autor: Bruno (com a Claude) · Situação: **aguardando revisão do Bruno**

Segunda entrega do módulo **Controller** (diretoria). Usa a mesma base comum da F1 (`2026-11-01-dre-gerencial-design.md`). Sem valores nem nomes neste documento (repositório público).

## 1. Objetivo

Mostrar à diretoria inteira — inclusive aos diretores comerciais — **o tamanho do buraco e quando ele aperta**, para que todos entendam e aceitem decisões duras (cortar custo, segurar compra, renegociar).

Perguntas que a tela responde:
1. Quanto temos hoje e quando o caixa fica abaixo do mínimo?
2. Quanto está atrasado, e o que foi decidido sobre cada atraso?
3. Quanto devemos no total, a quem, e quando acaba?
4. Quem nos deve, há quanto tempo, e quem está cobrando?

## 2. Decisões (conversa de 01–02/11/2026)

| # | Decisão |
|---|---|
| 1 | Propósito: mostrar o buraco para a diretoria aceitar decisões duras (não é ferramenta de venda) |
| 2 | Horizonte: **13 semanas, semana a semana**, depois **mês a mês até 12 meses** |
| 3 | Projeção = títulos lançados + custo fixo recorrente estimado + vendas futuras. Cada valor marcado *lançado* ou *estimado* |
| 4 | Saldo inicial: **informado por conta bancária, toda semana** (extrato OFX fica para depois) |
| 5 | Atrasados: bloco com **triagem**; a projeção segue a decisão de cada título |
| 6 | Dívidas: **cadastro de contratos** no sistema, ligado às parcelas do Santri |
| 7 | Unidades: **PVA · RV · Total** (Quirinópolis dentro de RV no caixa) |
| 8 | Cartão: **antecipação automática** em todas as vendas — título de cartão a receber não entra na projeção |
| 9 | Rotina: Ana Emilia importa, informa saldos e tria; diretoria vê na reunião |
| 10 | Alerta: **caixa mínimo por loja** definido pela diretoria |
| 11 | Simulação na F2: poucas chaves fixas; simulador completo fica na F3 |
| 12 | A receber: projeção + **cobrança simples** com vendedor responsável |
| 13 | Abordagem: projeção calculada na hora + **foto semanal dos números do topo** |
| 14 | **Comissão é paga sempre no mês seguinte ao fechamento** |
| 15 | Status pago / aberto / vencido é **uma regra só** na base comum, usada pela DRE (F1) e pelo Caixa (F2) |
| 16 | Diretores comerciais têm papel `direcao` e veem tudo |

## 3. Tela "Caixa"

Rota nova na área da direção. Padrão do sistema: números no topo, trabalho embaixo.
Chaves no topo: **PVA · RV · Total** e simulação (§5.4).

### 3.1 Topo (5 números, clicáveis)
1. **Saldo hoje** — soma das contas; data do saldo mais antigo; ⚠ se passar de 7 dias.
2. **Primeira semana abaixo do mínimo** — 🟡 abaixo do mínimo, 🔴 negativo.
3. **Maior buraco nas 13 semanas** — menor saldo projetado (R$ e data).
4. **Atrasado a pagar** — total · quanto ainda não foi triado.
5. **Dívida total** — saldo devedor · parcela média por mês.

Aviso no topo quando a última importação de títulos tiver mais de 7 dias.

### 3.2 Abas (na ordem do trabalho)
1. **Projeção** — gráfico de saldo (13 semanas com a linha do mínimo; depois 12 meses). Tabela entradas × saídas por grupo do caixa (fornecedor, pessoal, impostos, comissões/RT, dívida, fixo, outros); ◐ marca valor com parte estimada. Tudo abre: grupo → conta → títulos.
2. **Atrasados a pagar** — fila da triagem, maior valor primeiro; filtro "novos desde a última segunda" e "para a diretoria".
3. **A receber** — vencido por cliente (idade, valor, vendedor responsável, anotação de cobrança) e a vencer por semana.
4. **Dívidas** — contratos por credor (saldo, taxa, parcela, quando acaba) e gráfico da dívida caindo mês a mês.
5. **Saldos** — contas bancárias por loja, último saldo e "informar saldo".

### 3.3 Outras telas
- **Compras:** "Caixa para comprar · 30 dias" passa a ler a mesma projeção (um cálculo só).
- **Cobrança · meus clientes** (vendedor e gerente): cliente, valor vencido, dias, anotação; o vendedor pode anotar ("prometeu pagar em [data]"). Não mostra caixa, dívida nem números da empresa.

## 4. Status do título (base comum)

`interno.status_titulo()` — regra única para F1 e F2:
- 🟢 **pago** — situação Baixado (ou baixa encontrada em `baixas_santri`).
- 🟡 **aberto** — em aberto, vencimento ≥ hoje.
- 🔴 **vencido** — em aberto, vencimento < hoje (dias de atraso = hoje − vencimento).

"Hoje" é a data de Cuiabá (America/Cuiaba), não UTC.
Liga com a F1: o rodapé da DRE "despesas deste mês ainda não pagas (R$ vencido)" e o bloco Atrasados da F2 saem do mesmo cálculo.

## 5. Regras de cálculo

### 5.1 Ponto de partida
Soma do último saldo informado de cada conta bancária ativa da loja.

### 5.2 Entradas
- **A receber lançado:** títulos em aberto, na data de vencimento. Fora: tipo Cartão (já antecipado), Crédito, Adiantamento, Previsão (crédito do cliente, não dinheiro a entrar).
- **A receber vencido:** até 60 dias → semana seguinte; mais de 60 dias → fora. Com anotação "prometeu em [data]", vale a data anotada; "perdido" → fora.
- **Vendas futuras:** venda da semana = meta do mês ÷ semanas (ou média de 6 meses, ou zero — chave). Recebimento pelo perfil dos últimos 6 meses (parte à vista / PIX / cartão D+x e parte a prazo), ajustado pela chave "% de entrada".

### 5.3 Saídas
- **A pagar lançado:** títulos em aberto, no vencimento. Fora: tipos Pre, Cre, Adi (adiantamento ou crédito com fornecedor).
- **A pagar vencido:** segue a triagem (§6). Não triado → semana 1.
- **Fixo recorrente:** conta classificada como *fixa* → média dos últimos 6 meses **menos o já lançado** naquele mês (nunca negativo). Evita contar em dobro e cobre salário, energia etc. ainda não lançados.
- **Custo das vendas futuras:** fornecedor (% de custo médio, pago à vista na mesma semana); comissão e RT (mês seguinte); impostos (alíquota da F1, no dia de vencimento do mês seguinte); taxa do cartão; entrega (R$/t da F1).
- **Comissão e imposto de vendas já fechadas:** se o título existe no contas a pagar, vale o título; se não existe, estima pela venda e marca *estimado*.
- **Dívidas:** parcelas do cadastro que não estão ligadas a um título do Santri.
- **Entre lojas:** saída numa loja, entrada na outra; some no Total.

### 5.4 Chaves de simulação (não gravam nada)
- Vendas futuras: meta / média 6 meses / zero.
- % de entrada à vista nas vendas futuras.
- Atrasados: seguir a triagem / pagar tudo agora.

### 5.5 Observado nos dados (16/10/2026)
- Comissão de vendedores aparece como título até fev–mar/2026 e quase some depois (é paga, mas o lançamento está em outro lugar — ver §9).
- ICMS sobre vendas lançado; PIS/COFINS lançados até jul–ago.
- "Impostos federais — parcelamento" e "Simples" têm dezenas de parcelas abertas por loja: são **dívida antiga** e vão para o cadastro de dívidas, não para imposto do mês.
- Cerca de 1.000 títulos a pagar e 560 a receber vencidos; metade com mais de 60 dias. Parte é crédito/adiantamento ou título pago e não baixado.

## 6. Triagem e cobrança (`titulos_tratativa`)

Uma tabela para as duas pontas, com histórico (quem, quando, o quê).

| Lado | Decisão | Efeito na projeção |
|---|---|---|
| Pagar | pagar em [data] | sai na data |
| Pagar | renegociado | vira parcelas (cadastro de dívidas) |
| Pagar | em disputa | fora, listado à parte |
| Pagar | não é dívida | fora; tarefa "corrigir no Santri" |
| Pagar | para a diretoria | semana 1 até decidir |
| Receber | prometeu pagar em [data] | entra na data |
| Receber | negociando | regra padrão (§5.2) |
| Receber | perdido | fora |

Responsável no a receber: vendedor da venda (pelo pedido) ou o informado.
Primeira triagem: fila pelos maiores valores; "não é dívida" em lote para os tipos Pre/Cre/Adi.

## 7. Dados

### 7.1 Base comum (F1 + F2)
- `plano_contas_classe`: por conta do plano — linha da DRE, **grupo do caixa**, *fixa recorrente* (s/n), regra do mês, linha de mercado (F4).
- `interno.status_titulo()` (§4).
- Vendedor → unidade; centro de custo → unidade (F1 §7).

### 7.2 Novas da F2
- `contas_bancarias` (loja, banco, nome, ativo). `caixa_saldo` ganha `conta_id`; saldos já existentes vão para uma conta "geral" da loja.
- `caixa_parametros` por loja: caixa mínimo, cartão (D+x, taxa), mês de pagamento da comissão (padrão: seguinte) e da RT, dia de vencimento dos impostos.
- `dividas` (credor, tipo: banco / parcelamento de imposto / sócio / entre lojas / Chapadão do Sul / outro; loja; outra loja; valor original; saldo; taxa; parcela; início; fim) + `dividas_parcelas` (geradas) + ligação parcela × título do Santri + conferência mensal do saldo.
- `titulos_tratativa` (§6) + eventos.
- `caixa_fotos`: por loja e segunda-feira — saldo, menor saldo e data, primeira semana abaixo do mínimo, atrasado, não triado, dívida total.

### 7.3 RPCs (`SECURITY DEFINER`, checam papel e loja por dentro)
- `tela_caixa(p_loja, p_vendas, p_entrada_pct, p_atrasados)`
- `informar_saldo_conta`, `tratar_titulo`, `salvar_divida`, `salvar_parametros_caixa`
- `gravar_foto_caixa` — automática toda segunda às 12h (Cuiabá) e por botão
- `tela_cobranca_vendedor` — só os clientes do vendedor logado

### 7.4 Importação
Sem DELETE (padrão). A triagem precisa sobreviver a nova importação: conferir se o `id` de `titulos_santri` é estável entre importações; se não for, a chave da tratativa é loja + lado + código do título.

## 8. Rotina e acesso

**Segunda-feira:**
1. Ana Emilia importa a pagar, a receber e baixas (as duas lojas).
2. Informa o saldo de cada conta bancária.
3. Tria os atrasados novos; marca "para a diretoria" o que precisa de decisão.
4. 12h: foto da semana gravada.
5. Reunião de diretoria: topo → projeção → "para a diretoria" → dívidas.

**Acesso:**
- Tela Caixa e cadastros: `admin` e `direcao` (diretores comerciais e a operação/financeiro incluídos).
- Cobrança · meus clientes: vendedor e gerente, só os próprios clientes.

## 9. Tarefas do Bruno (fora do sistema)
1. Organizar e aprender a parametrizar a **antecipação do cartão no Santri**.
2. Descobrir **onde está lançada a comissão desde mar/2026** (outra conta do plano? folha?).
3. Primeira carga do **cadastro de dívidas** (contratos, saldos, taxas).
4. Definir o **caixa mínimo** de cada loja.
5. Revisar o rascunho da **classificação do plano de contas** (a Claude prepara).
6. Retomar a importação semanal (relatórios parados em 16/10).

## 10. Ordem de construção
Cada etapa é útil sozinha.
1. Base comum (classificação + status único).
2. Contas bancárias, saldos e parâmetros.
3. Projeção com o lançado + atrasados com triagem.
4. Fixo recorrente + vendas futuras + chaves de simulação.
5. Dívidas.
6. A receber / cobrança (inclui a lista do vendedor).
7. Foto semanal + Compras lendo a mesma projeção.

Depois da F2: F1 (DRE) → **B1 Balanço gerencial** → F4. O balanço reaproveita saldos, títulos, dívidas (F2), carteira e bens (F1) e o estoque (`estoque_foto` valorizado ao custo).

## 11. Testes
- Semana 1 de uma loja conferida à mão: saldo informado + a receber − a pagar da semana.
- Nada em dobro: título lançado de comissão/imposto anula a estimativa do mês; parcela de dívida ligada a título não aparece duas vezes; fixo recorrente nunca soma com o lançado acima da média.
- Entre lojas zera no Total.
- Tratativa continua no título após nova importação.
- Status igual na DRE (F1) e no Caixa (F2).
- RPC no banco real sem gravar (bloco DO com rollback, ver HANDOFF).
- Tela: Playwright, desktop e 390 px (sem rolagem horizontal).

## 12. Riscos
- **Dados desatualizados** (16/10): importar antes de mostrar à diretoria.
- **Primeira triagem pesada:** começar pelos maiores valores e pelo lote Pre/Cre/Adi.
- **Cartão:** enquanto a antecipação não estiver parametrizada no Santri, "cartão = já recebido" pode errar um pouco.
- **Perfil de recebimento e % de custo** vêm de médias de 6 meses: mudança de mix de pagamento demora a aparecer — a foto semanal mostra o erro.

## 13. Estacionado
- Extrato bancário OFX (saldo automático e conciliação).
- Régua de cobrança com mensagens (WhatsApp).
- Simulador completo (F3).
