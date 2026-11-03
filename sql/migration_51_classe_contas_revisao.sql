-- Migration 51: revisão do rascunho da classificação do plano de contas (revisão Opus do plano 2 da F2)
-- O rascunho jogava no "custo fixo" tudo o que não reconhecia. Com o plano 2, conta fixa vira média mensal projetada,
-- então três tipos de conta precisavam sair do fixo:
-- 1. Compra de mercadoria: é fornecedor. Como fixo, contava em dobro com o custo das vendas futuras.
-- 2. Investimento que não se repete (veículo, construção, imobilizado de loja nova, decoração): grupo outros, não fixa.
-- 3. Formas de pagamento e ajustes que não são despesa (crédito, dinheiro, pix, boletos, descontos concedidos, recuperação): outros, não fixa.
-- Contribuição social (CSLL) vai para impostos. Só mexe em conta que o Bruno ainda não revisou.

create or replace function interno.grupo_caixa_padrao(p_plano_nome text)
returns text language sql immutable set search_path to '' as $$
  select case
    when upper(coalesce(p_plano_nome,'')) ~ 'PARCELAMENTO|^SIMPLES$|EMPRESTIMO|FINANCIAMENTO|CONSORCIO' then 'divida'
    when upper(coalesce(p_plano_nome,'')) ~ 'FORNECEDOR|FRETE|DESPESAS EXTRAS DE COMPRAS|COMPRA DE MERCADORIA' then 'fornecedor'
    when upper(coalesce(p_plano_nome,'')) ~ 'COMISS|REFLEXOS? DE COMISS' then 'comissoes_rt'
    when upper(coalesce(p_plano_nome,'')) ~ 'SALARIO|FERIAS|13|RESCIS|INSS|FGTS|VALE TRANSPORTE|PRO.?LABORE|ENCARGO|PLANO DE SAUDE|ALIMENTA' then 'pessoal'
    when upper(coalesce(p_plano_nome,'')) ~ 'ICMS|COFINS|^PIS$|IMPOSTO|ISSQN|IRRF|DIFAL|TAXAS MUNICIPAIS|CONTRIBUICAO SOCIAL' then 'impostos'
    when upper(coalesce(p_plano_nome,'')) ~ 'IMOBILIZADO|COMPRA DE VEICULO|CONSTRU|DECORACAO|^CR.DITO$|^DINHEIRO$|^PIX$|^BOLETOS$|DESCONTOS CONCEDIDOS|RECUPERACAO DE DESPESAS' then 'outros'
    else 'fixo' end
$$;

update public.plano_contas_classe
   set grupo_caixa = interno.grupo_caixa_padrao(plano_nome),
       fixa = interno.grupo_caixa_padrao(plano_nome) in ('pessoal','fixo'),
       atualizado_em = now()
 where not revisado
   and grupo_caixa is distinct from interno.grupo_caixa_padrao(plano_nome);
