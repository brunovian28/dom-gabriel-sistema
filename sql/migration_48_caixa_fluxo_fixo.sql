-- Migration 48: caixa_fluxo (lançado + custo fixo recorrente estimado) — F2 Caixa, plano 2
-- Todo valor com origem diferente de lancado é estimado. Valor positivo = entra, negativo = sai.
-- Custo fixo recorrente: para cada conta fixa, média dos 6 meses completos antes do mês de hoje menos o que já foi lançado no mês (nunca negativo).

create or replace function interno.caixa_fluxo(p_lojas smallint[], p_hoje date, p_atrasados text, p_vendas text, p_entrada_pct numeric)
returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean, descricao text)
language sql stable security definer set search_path to '' as $$
  with st as (
    select s.titulo_id, s.loja_id, s.status, s.dias_atraso, s.saldo_aberto, 'pagar'::text lado from interno.titulos_aberto('pagar', p_hoje) s
    union all
    select s.titulo_id, s.loja_id, s.status, s.dias_atraso, s.saldo_aberto, 'receber'::text from interno.titulos_aberto('receber', p_hoje) s
  ), b as (
    select t.id, st.lado, t.loja_id, t.vencimento, st.saldo_aberto saldo, t.tipo, t.plano_codigo, t.plano_nome,
           st.status, st.dias_atraso, tr.decisao, tr.nova_data
    from st
    join public.titulos_santri t on t.id = st.titulo_id
    left join public.titulos_tratativa tr on tr.titulo_id = t.id
    where st.loja_id = any(p_lojas) and st.status <> 'pago' and st.saldo_aberto > 0
  ), m as (
    select b.loja_id,
           case when b.status = 'aberto' then coalesce(b.vencimento, p_hoje)
                when b.decisao = 'nao_e_divida' then null
                when p_atrasados = 'pagar_tudo' then p_hoje
                when b.decisao in ('pagar_em','renegociado') then greatest(b.nova_data, p_hoje)
                when b.decisao = 'em_disputa' then null
                else p_hoje end data,
           interno.grupo_caixa(b.plano_codigo, b.plano_nome) grupo,
           -b.saldo valor, b.id titulo_id, b.status = 'vencido' vencido
    from b
    where b.lado = 'pagar' and coalesce(b.tipo, '') not in ('Pre','Cre','Adi')
    union all
    select b.loja_id,
           case when b.status = 'aberto' then b.vencimento
                when b.decisao = 'perdido' then null
                when b.decisao = 'prometeu' then greatest(b.nova_data, p_hoje)
                when b.dias_atraso <= 60 then p_hoje + 7
                else null end,
           case when interno.categoria_receber(b.tipo, b.plano_nome) in ('clientes','venda_direta') then 'clientes' else 'outros_entrada' end,
           b.saldo, b.id, b.status = 'vencido'
    from b
    where b.lado = 'receber' and coalesce(b.tipo, '') !~* '^(cart|cr.dito|adiant|previs)'
      and interno.categoria_receber(b.tipo, b.plano_nome) <> 'credito_fornecedor'
  ), pag as (
    -- títulos a pagar da foto atual (qualquer situação), sem adiantamento nem crédito
    select t.loja_id, t.plano_codigo, t.plano_nome, t.vencimento, t.valor_documento
    from public.titulos_santri t
    where t.lado = 'pagar' and t.ultima_importacao_id = interno.titulos_ultima_importacao('pagar')
      and t.loja_id = any(p_lojas) and t.plano_codigo is not null and t.vencimento is not null
      and coalesce(t.tipo, '') not in ('Pre','Cre','Adi')
  ), media as (
    select p.loja_id, p.plano_codigo, (array_agg(p.plano_nome))[1] nome, sum(p.valor_documento) / 6 media,
           least(round(avg(extract(day from p.vencimento)))::int, 28) dia
    from pag p
    where p.vencimento >= (date_trunc('month', p_hoje) - interval '6 months')::date and p.vencimento < date_trunc('month', p_hoje)::date
    group by p.loja_id, p.plano_codigo
  ), fixa as (
    select md.*, interno.grupo_caixa(md.plano_codigo, md.nome) grupo
    from media md
    where coalesce((select c.fixa from public.plano_contas_classe c where c.plano_codigo = md.plano_codigo),
                   interno.grupo_caixa_padrao(md.nome) in ('pessoal','fixo'))
      and interno.grupo_caixa(md.plano_codigo, md.nome) not in ('fornecedor','impostos','comissoes_rt','divida','fora')
  ), meses as (
    select (date_trunc('month', p_hoje) + make_interval(months => k))::date mes from generate_series(0, 11) k
  ), est as (
    select f.loja_id, greatest(make_date(extract(year from ms.mes)::int, extract(month from ms.mes)::int, f.dia), p_hoje) data, f.grupo,
           f.media - coalesce((select sum(p.valor_documento) from pag p where p.loja_id = f.loja_id and p.plano_codigo = f.plano_codigo
                                 and p.vencimento >= ms.mes and p.vencimento < (ms.mes + interval '1 month')::date), 0) falta,
           f.nome
    from fixa f cross join meses ms
  )
  select m.loja_id, m.data, m.grupo, m.valor, 'lancado'::text, m.titulo_id, m.vencido, null::text
  from m
  where m.data is not null and m.grupo <> 'fora'
  union all
  select e.loja_id, e.data, e.grupo, -e.falta, 'fixo'::text, null::bigint, false, e.nome
  from est e
  where e.falta > 0.005
$$;

-- Atalho para a parte lançada (mesma assinatura de antes)
create or replace function interno.caixa_movimentos(p_lojas smallint[], p_hoje date, p_atrasados text)
returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean)
language sql stable security definer set search_path to '' as $$
  select f.loja_id, f.data, f.grupo, f.valor, f.origem, f.titulo_id, f.vencido
  from interno.caixa_fluxo(p_lojas, p_hoje, p_atrasados, 'zero', null) f
  where f.origem = 'lancado'
$$;

revoke execute on function interno.caixa_fluxo(smallint[], date, text, text, numeric) from anon, public;
grant execute on function interno.caixa_fluxo(smallint[], date, text, text, numeric) to authenticated;
