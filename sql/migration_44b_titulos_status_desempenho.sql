-- Migration 44b: desempenho de interno.titulos_status (migration 41)
-- A última importação era buscada linha a linha. Agora é buscada uma vez por chamada.

create or replace function interno.titulos_status(p_lado text, p_hoje date)
returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso int)
language sql stable security definer set search_path to '' as $$
  with u as (
    select interno.titulos_ultima_importacao(p_lado) id
  ), b as (
    select bs.lado, bt.cod_financeiro, sum(bt.valor_baixado) pago
    from public.baixas_santri bs
    join public.baixas_santri_titulos bt on bt.baixa_id = bs.id and bt.ativo
    where bs.ativo and bs.lado = p_lado
    group by bs.lado, bt.cod_financeiro
  ), t as (
    select t.id, t.loja_id, t.situacao, t.vencimento,
           (coalesce(t.saldo,0) > 0 and coalesce(b.pago,0) >= t.saldo) pago_baixa
    from public.titulos_santri t
    join u on t.ultima_importacao_id = u.id
    left join b on b.cod_financeiro = t.codigo and b.lado = t.lado
    where t.lado = p_lado
  )
  select t.id, t.loja_id,
         interno.status_titulo(t.situacao, t.vencimento, t.pago_baixa, p_hoje),
         case when interno.status_titulo(t.situacao, t.vencimento, t.pago_baixa, p_hoje) = 'vencido'
              then greatest(p_hoje - t.vencimento, 0) else 0 end
  from t
$$;
