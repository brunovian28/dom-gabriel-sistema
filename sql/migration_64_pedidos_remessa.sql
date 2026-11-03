-- Migration 64: tela_pedidos usa a nota de remessa (notas_saida) como prova de entrega
-- Remessa = nota ativa 'Entregas' ou 'Entregas agrupadas' cujo cod_movimento e o codigo da entrega (entregas_santri, mesma loja).
-- Remessa cancelada (existe nota ativa 'Dev. por canc. de entrega' com o mesmo codigo e loja) nao conta.
-- Pedido com remessa valida: fora das entregas pendentes = entregue (entregue_em = maior emissao), nas pendentes = parcial.
-- Pedido sem remessa valida segue as regras da migration 62 (entrega total, manifesto > 30 dias, presumido > 60 dias).
-- JSON ganha remessa_em e remessa_nf. Base: definicao viva da migration 62.

create or replace function public.tela_pedidos(p_loja smallint)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '60s'
as $function$
#variable_conflict use_column
declare
  lojas smallint[]; res jsonb;
  hoje date := (now() at time zone 'America/Cuiaba')::date;
  imp_ep bigint; v_papel text; v_nome text;
begin
  lojas := interno.lojas_tela(p_loja);
  select u.papel, nullif(upper(trim(u.nome_santri)), '') into v_papel, v_nome
    from public.usuarios u where u.id = (select auth.uid()) and u.ativo;
  if v_papel is distinct from 'vendedor' then v_nome := null; end if;
  imp_ep := (select max(x.importacao_id) from public.entregas_pendentes x);

  with
  vd as materialized (
    select v.id, v.loja_id, v.numero, v.data_fechamento::date fechamento, v.cliente_nome cliente, v.vendedor_santri vendedor,
           coalesce(v.vlr_liquido, 0) valor, v.pedido_id
    from public.vendas_santri v
    where v.tipo = 'PED' and not coalesce(v.venda_direta, false) and v.loja_id = any(lojas) and v.data_fechamento >= hoje - 365
      and (v_nome is null or upper(trim(v.vendedor_santri)) = v_nome)),
  pg as materialized (
    select b.loja_id, t.pedido_numero numero, sum(t.valor_baixado) pago
    from public.baixas_santri b
    join public.baixas_santri_titulos t on t.baixa_id = b.id and t.ativo
    join vd on vd.loja_id = b.loja_id and vd.numero = t.pedido_numero
    where b.lado = 'receber' and b.ativo and b.loja_id = any(lojas)
    group by b.loja_id, t.pedido_numero),
  mer as materialized (select * from interno.pedidos_mercadoria(lojas, hoje - 365)),
  ep as materialized (
    select e.loja_id, e.pedido numero, bool_or(e.secao = 'pendente') pend, max(e.prev_maior) prev
    from public.entregas_pendentes e
    join vd on vd.loja_id = e.loja_id and vd.numero = e.pedido
    where e.importacao_id = imp_ep and e.loja_id = any(lojas)
    group by e.loja_id, e.pedido),
  eg as materialized (
    select g.loja_id, g.pedido numero, bool_or(g.status_manifesto ilike 'Aguardando%') aguard,
           bool_or(g.status_entrega ilike 'Entrega total') total,
           max(case when g.status_entrega ilike 'Entrega total' then coalesce(g.data_entrega, g.concluida_em) end) entregue_total,
           max(g.data_cadastro) ultimo_cad,
           max(g.data_cadastro) filter (where g.status_manifesto ilike 'Aguardando%') aguard_cad
    from public.entregas_santri g
    join vd on vd.loja_id = g.loja_id and vd.numero = g.pedido
    where g.ativo and g.loja_id = any(lojas)
    group by g.loja_id, g.pedido),
  rem as materialized (
    select g.loja_id, g.pedido numero, max(n.emissao) rem_em,
           (array_agg(n.nr_nota order by n.emissao desc nulls last, n.id desc))[1] rem_nf
    from public.entregas_santri g
    join vd on vd.loja_id = g.loja_id and vd.numero = g.pedido
    join public.notas_saida n on n.loja_id = g.loja_id and n.cod_movimento = g.entrega
         and n.tipo_movimento in ('Entregas', 'Entregas agrupadas') and n.ativo
    where g.ativo and g.loja_id = any(lojas)
      and not exists (select 1 from public.notas_saida c
                      where c.loja_id = n.loja_id and c.cod_movimento = n.cod_movimento
                        and c.tipo_movimento = 'Dev. por canc. de entrega' and c.ativo)
    group by g.loja_id, g.pedido),
  b1 as (
    select vd.*, coalesce(pg.pago, 0) pago, coalesce(mer.itens, 0) itens, coalesce(mer.falta, 0) falta, coalesce(mer.fabrica, 0) fabrica,
           coalesce(mer.faturado, 0) faturado, coalesce(mer.chegou, 0) chegou,
           case when ep.numero is not null and (rem.numero is not null or coalesce(eg.total, false)) then 'parcial'
                when ep.numero is not null and ep.pend then 'agendada'
                when ep.numero is not null then 'sem_agendamento'
                when rem.numero is not null then 'entregue'
                when coalesce(eg.total, false) then 'entregue'
                when coalesce(eg.aguard, false) and eg.aguard_cad >= hoje - 30 then 'gerada'
                when coalesce(eg.aguard, false) then 'entregue'
                when vd.fechamento < hoje - 60 then 'entregue'
                else 'sem_info' end entrega,
           (ep.numero is null and coalesce(eg.aguard, false) and coalesce(eg.aguard_cad < hoje - 30, true)) fechar,
           eg.entregue_total, eg.ultimo_cad, ep.prev prev_santri,
           rem.numero rem_numero, rem.rem_em, rem.rem_nf,
           pd.previsao_entrega prev_sistema, pd.data_cliente_precisa precisa,
           p.capa_id
    from vd
    left join pg on pg.loja_id = vd.loja_id and pg.numero = vd.numero
    left join mer on mer.loja_id = vd.loja_id and mer.numero = vd.numero
    left join ep on ep.loja_id = vd.loja_id and ep.numero = vd.numero
    left join eg on eg.loja_id = vd.loja_id and eg.numero = vd.numero
    left join rem on rem.loja_id = vd.loja_id and rem.numero = vd.numero
    left join public.pedido_datas pd on pd.loja_id = vd.loja_id and pd.numero = vd.numero
    left join public.pedidos p on p.id = vd.pedido_id),
  b2 as (
    select b1.*,
           case when entrega = 'entregue' then 'entregue'
                when entrega = 'gerada' then 'saindo'
                when falta > 0 and pago = 0 then 'aguardando_pagamento'
                when falta > 0 then 'falta_comprar'
                when fabrica > 0 then 'na_fabrica'
                when faturado > 0 then 'faturado'
                else 'pronto' end etapa,
           coalesce(prev_sistema, prev_santri) previsao,
           case when entrega = 'entregue' and rem_numero is not null then rem_em
                else coalesce(entregue_total, case when entrega = 'entregue' then ultimo_cad end) end entregue_em
    from b1),
  b3 as (
    select b2.*,
           case when etapa = 'entregue' then array_remove(array[case when fechar then 'fechar_manifesto' end], null)
                else array_remove(array[
                  case when previsao is null then 'sem_previsao' end,
                  case when previsao < hoje then 'previsao_vencida' end,
                  case when prev_sistema is not null and prev_sistema is distinct from prev_santri then 'atualizar_santri' end,
                  case when precisa is not null and (previsao is null or precisa < previsao) then 'precisa_antes' end,
                  case when fechamento < hoje - 60 then 'parado_60' end,
                  case when pedido_id is null then 'nao_lancado' end], null) end alertas
    from b2
    where etapa <> 'entregue' or entregue_em >= hoje - 30 or fechar)
  select jsonb_build_object(
    'hoje', hoje, 'lojas', to_jsonb(lojas),
    'atualizado', jsonb_build_object(
       'vendas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'vendas'),
       'entregas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'entregas'),
       'compras', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'compras'),
       'entradas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'entradas'),
       'baixas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'receber_baixas')),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object(
        'venda_id', b3.id, 'loja_id', b3.loja_id, 'numero', b3.numero, 'fechamento', b3.fechamento, 'dias', hoje - b3.fechamento,
        'cliente', b3.cliente, 'vendedor', b3.vendedor, 'valor', b3.valor,
        'pago_pct', case when b3.valor > 0 then round(100 * least(b3.pago, b3.valor) / b3.valor) end,
        'lancado', b3.pedido_id is not null, 'capa_id', b3.capa_id,
        'itens', b3.itens, 'falta', b3.falta, 'fabrica', b3.fabrica, 'faturado', b3.faturado, 'chegou', b3.chegou,
        'etapa', b3.etapa, 'entrega', b3.entrega, 'entregue_em', b3.entregue_em,
        'remessa_em', b3.rem_em, 'remessa_nf', b3.rem_nf,
        'prev_sistema', b3.prev_sistema, 'prev_santri', b3.prev_santri, 'previsao', b3.previsao, 'precisa', b3.precisa,
        'alertas', to_jsonb(b3.alertas)) order by b3.fechamento, b3.loja_id, b3.numero) from b3), '[]'::jsonb)
  ) into res;
  return res;
end $function$;

revoke all on function public.tela_pedidos(smallint) from anon, public;
grant execute on function public.tela_pedidos(smallint) to authenticated;
