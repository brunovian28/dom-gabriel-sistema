-- Migration 57: titulos_aberto ignora títulos já Baixados no Santri
-- Com o histórico completo importado, a última importação de pagar/receber traz ~60 mil títulos baixados.
-- Eles sempre saem com status 'pago' e todas as funções que usam titulos_aberto descartam 'pago',
-- então filtrar na entrada não muda resultado e tira ~90% das linhas da Caixa e das Dívidas.

create or replace function interno.titulos_aberto(p_lado text, p_hoje date)
 returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso integer, saldo_aberto numeric)
 language sql
 stable security definer
 set search_path to ''
as $function$
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
    where t.lado = p_lado and lower(coalesce(t.situacao, '')) <> 'baixado'
  ), x as (
    select t.*, interno.status_titulo(t.situacao, t.vencimento, t.saldo > 0 and t.pago >= t.saldo - 0.005, p_hoje) st
    from t
  )
  select x.id, x.loja_id, x.st,
         case when x.st = 'vencido' then greatest(p_hoje - x.vencimento, 0) else 0 end,
         case when x.st = 'pago' then 0 else greatest(x.saldo - x.pago, 0) end
  from x
$function$;

create index if not exists titulos_santri_ult_nao_baixado_idx
  on public.titulos_santri (lado, ultima_importacao_id)
  where lower(coalesce(situacao, '')) <> 'baixado';
