-- Migration 46: correções da revisão do plano 1 da F2 (Caixa)
-- 1. Baixa parcial: só contam as baixas com data depois da foto dos títulos (as anteriores já estão no saldo do título),
--    e o que foi baixado em parte é descontado do saldo. Antes, uma baixa antiga de 600 num título de saldo 400 o marcava como pago.
-- 2. Saldo em dobro: o saldo da loja inteira (tela de Compras) ia para a conta Geral e somava com as contas bancárias.
--    Agora o saldo é informado só por conta, na tela Caixa. Conta Geral sem nenhum saldo é desativada.
-- 3. Funções internas novas fechadas para anon e public.

-- Título em aberto com o saldo que ainda falta (desconta baixas feitas depois da foto)
create or replace function interno.titulos_aberto(p_lado text, p_hoje date)
returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso int, saldo_aberto numeric)
language sql stable security definer set search_path to '' as $$
  with u as (
    select i.id, (i.criado_em at time zone 'America/Cuiaba')::date dia
    from public.importacoes i where i.id = interno.titulos_ultima_importacao(p_lado)
  ), b as (
    select bt.cod_financeiro, sum(bt.valor_baixado) pago
    from public.baixas_santri bs
    join public.baixas_santri_titulos bt on bt.baixa_id = bs.id and bt.ativo
    where bs.ativo and bs.lado = p_lado and bs.data_baixa > (select u.dia from u)
    group by bt.cod_financeiro
  ), t as (
    select t.id, t.loja_id, t.situacao, t.vencimento, coalesce(t.saldo, 0) saldo, coalesce(b.pago, 0) pago
    from public.titulos_santri t
    join u on t.ultima_importacao_id = u.id
    left join b on b.cod_financeiro = t.codigo
    where t.lado = p_lado
  ), x as (
    select t.*, interno.status_titulo(t.situacao, t.vencimento, t.saldo > 0 and t.pago >= t.saldo - 0.005, p_hoje) st
    from t
  )
  select x.id, x.loja_id, x.st,
         case when x.st = 'vencido' then greatest(p_hoje - x.vencimento, 0) else 0 end,
         case when x.st = 'pago' then 0 else greatest(x.saldo - x.pago, 0) end
  from x
$$;

-- Mesma assinatura de antes (a F1 vai usar): agora lê de titulos_aberto
create or replace function interno.titulos_status(p_lado text, p_hoje date)
returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso int)
language sql stable security definer set search_path to '' as $$
  select a.titulo_id, a.loja_id, a.status, a.dias_atraso from interno.titulos_aberto(p_lado, p_hoje) a
$$;

create or replace function interno.caixa_movimentos(p_lojas smallint[], p_hoje date, p_atrasados text)
returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean)
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
  )
  select m.loja_id, m.data, m.grupo, m.valor, 'lancado'::text, m.titulo_id, m.vencido
  from m
  where m.data is not null and m.grupo <> 'fora'
$$;

create or replace function interno.caixa_atrasados(p_lojas smallint[], p_hoje date)
returns table(titulo_id bigint, loja smallint, nome text, plano_nome text, grupo text, tipo text, vencimento date, dias int,
              saldo numeric, decisao text, nova_data date, nota text, por_nome text, em timestamptz)
language sql stable security definer set search_path to '' as $$
  select t.id, t.loja_id, t.nome, t.plano_nome, g.grupo, t.tipo, t.vencimento, s.dias_atraso,
         s.saldo_aberto, tr.decisao, tr.nova_data, tr.nota, u.nome, tr.em
  from interno.titulos_aberto('pagar', p_hoje) s
  join public.titulos_santri t on t.id = s.titulo_id
  cross join lateral (select interno.grupo_caixa(t.plano_codigo, t.plano_nome) grupo) g
  left join public.titulos_tratativa tr on tr.titulo_id = t.id
  left join public.usuarios u on u.id = tr.por
  where s.status = 'vencido' and s.loja_id = any(p_lojas) and s.saldo_aberto > 0
    and coalesce(t.tipo, '') not in ('Pre','Cre','Adi')
    and g.grupo <> 'fora' and coalesce(tr.decisao, '') <> 'nao_e_divida'
  order by s.saldo_aberto desc, t.id
$$;

-- Saldo da loja inteira não é mais aceito (somava com as contas bancárias)
create or replace function public.informar_saldo_caixa(p_loja smallint, p_saldo numeric, p_obs text default null)
returns void language plpgsql security definer set search_path to '' as $$
begin
  raise exception 'O saldo agora é informado por conta bancária, na tela Caixa (aba Saldos)';
end $$;

update public.contas_bancarias c set ativo = false
 where c.nome = 'Geral' and c.banco = '—' and c.ativo
   and not exists (select 1 from public.caixa_saldo s where s.conta_id = c.id);

revoke execute on function interno.titulos_aberto(text, date) from anon, public;
revoke execute on function interno.titulos_status(text, date) from anon, public;
revoke execute on function interno.caixa_movimentos(smallint[], date, text) from anon, public;
revoke execute on function interno.caixa_atrasados(smallint[], date) from anon, public;
revoke execute on function interno.caixa_projecao(smallint[], date, text) from anon, public;
revoke execute on function interno.saldo_caixa(smallint[]) from anon, public;
revoke execute on function interno.grupo_caixa(text, text) from anon, public;
grant execute on function interno.titulos_aberto(text, date) to authenticated;
grant execute on function interno.titulos_status(text, date) to authenticated;
grant execute on function interno.caixa_movimentos(smallint[], date, text) to authenticated;
grant execute on function interno.caixa_atrasados(smallint[], date) to authenticated;
grant execute on function interno.caixa_projecao(smallint[], date, text) to authenticated;
grant execute on function interno.saldo_caixa(smallint[]) to authenticated;
grant execute on function interno.grupo_caixa(text, text) to authenticated;
