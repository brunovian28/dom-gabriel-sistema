-- Migration 60: tela Pedidos montada pelo Santri (etapa, entrega e alertas calculados dos relatorios importados).
-- interno.pedidos_mercadoria: situacao dos itens (mesma ligacao venda -> compra da tela_compras, migration 57d).
-- (Versao final = 60 + 60b: entregue_em usa data_entrega das linhas 'Entrega total', pois concluida_em e a data da 1a importacao e ficou igual para todo o historico.)
-- public.tela_pedidos: lista de pedidos PED (sem venda direta) dos ultimos 365 dias. Plano: docs/superpowers/plans/2026-11-03-pedidos-automaticos.md

create or replace function interno.pedidos_mercadoria(p_lojas smallint[], p_desde date)
returns table(loja_id smallint, numero text, itens int, falta int, fabrica int, faturado int, chegou int)
language sql stable security definer set search_path to '' as $f$
  with
  vd as materialized (
    select v.id, v.loja_id, v.numero, v.data_fechamento::date f
    from public.vendas_santri v
    where v.tipo = 'PED' and not coalesce(v.venda_direta, false) and v.loja_id = any(p_lojas) and v.data_fechamento >= p_desde),
  vi as materialized (
    select vd.id, vd.loja_id, vd.numero, vd.f, i.ordem, i.codigo, upper(coalesce(i.marca,'')) marca,
           interno.familia_produto(i.marca, i.descricao) fam
    from vd join public.vendas_santri_itens i on i.venda_id = vd.id),
  ci as materialized (
    select c.loja_id, c.numero, c.data_cadastro d, it.codigo, upper(coalesce(it.marca,'')) marca, interno.familia_produto(it.marca, it.nome) fam
    from public.compras_santri c join public.compras_santri_itens it on it.compra_id = c.id
    where c.status <> 'Cancelado' and it.ativo and c.loja_id = any(p_lojas) and c.data_cadastro >= p_desde - 3),
  lig_cand as (
    select vi.id, vi.ordem, 0 pri, ci.numero, ci.d from vi join ci on ci.loja_id = vi.loja_id and ci.codigo = vi.codigo and ci.d between vi.f - 3 and vi.f + 150
    union all
    select vi.id, vi.ordem, 1, ci.numero, ci.d from vi join ci on ci.loja_id = vi.loja_id and ci.fam = vi.fam and ci.marca = vi.marca and ci.d between vi.f - 3 and vi.f + 150 where vi.fam is not null),
  lig_pick as (select distinct on (id, ordem) id, ordem, numero, d from lig_cand order by id, ordem, pri, d, numero),
  lig as materialized (
    select vi.id, vi.loja_id, vi.numero, vi.marca, l.numero compra, m.situacao marca_sit
    from vi
    left join lig_pick l on l.id = vi.id and l.ordem = vi.ordem
    left join public.fila_compra_marcas m on m.loja_id = vi.loja_id and m.pedido = vi.numero and m.codigo = vi.codigo and m.situacao is not null),
  nota as (
    select e.loja_id, ec.compra_numero, bool_or(e.status = 'Baixada') baixada, bool_or(e.status = 'Aberta') aberta
    from public.entradas_santri_compras ec
    join public.entradas_santri e on e.id = ec.entrada_id
    join (select distinct lig.loja_id, lig.compra from lig where lig.compra is not null) k on k.loja_id = e.loja_id and k.compra = ec.compra_numero
    where ec.ativo
    group by e.loja_id, ec.compra_numero),
  sit as (
    select lig.loja_id, lig.numero,
           case when lig.marca_sit in ('venda_direta','nao_comprar') then 'ignorado'
                when lig.compra is null and coalesce(lig.marca_sit,'') <> 'comprado' then
                  case when lig.marca_sit = 'estoque' or interno.e_marca_estoque(lig.marca) then 'chegou' else 'falta' end
                when lig.compra is null then 'fabrica'
                when coalesce(n.baixada, false) then 'chegou'
                when coalesce(n.aberta, false) then 'faturado'
                else 'fabrica' end s
    from lig left join nota n on n.loja_id = lig.loja_id and n.compra_numero = lig.compra)
  select sit.loja_id, sit.numero,
         (count(*) filter (where sit.s <> 'ignorado'))::int,
         (count(*) filter (where sit.s = 'falta'))::int,
         (count(*) filter (where sit.s = 'fabrica'))::int,
         (count(*) filter (where sit.s = 'faturado'))::int,
         (count(*) filter (where sit.s = 'chegou'))::int
  from sit group by sit.loja_id, sit.numero
$f$;

create or replace function public.tela_pedidos(p_loja smallint)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $f$
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
           bool_or(g.status_entrega ilike 'Entrega total') total, max(case when g.status_entrega ilike 'Entrega total' then coalesce(g.data_entrega, g.concluida_em) end) entregue_em
    from public.entregas_santri g
    join vd on vd.loja_id = g.loja_id and vd.numero = g.pedido
    where g.ativo and g.loja_id = any(lojas)
    group by g.loja_id, g.pedido),
  b1 as (
    select vd.*, coalesce(pg.pago, 0) pago, coalesce(mer.itens, 0) itens, coalesce(mer.falta, 0) falta, coalesce(mer.fabrica, 0) fabrica,
           coalesce(mer.faturado, 0) faturado, coalesce(mer.chegou, 0) chegou,
           case when ep.numero is not null and coalesce(eg.total, false) then 'parcial'
                when ep.numero is not null and ep.pend then 'agendada'
                when ep.numero is not null then 'sem_agendamento'
                when coalesce(eg.aguard, false) then 'gerada'
                when coalesce(eg.total, false) then 'entregue'
                else 'sem_info' end entrega,
           eg.entregue_em, ep.prev prev_santri,
           pd.previsao_entrega prev_sistema, pd.data_cliente_precisa precisa,
           p.id capa_id
    from vd
    left join pg on pg.loja_id = vd.loja_id and pg.numero = vd.numero
    left join mer on mer.loja_id = vd.loja_id and mer.numero = vd.numero
    left join ep on ep.loja_id = vd.loja_id and ep.numero = vd.numero
    left join eg on eg.loja_id = vd.loja_id and eg.numero = vd.numero
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
           coalesce(prev_sistema, prev_santri) previsao
    from b1),
  b3 as (
    select b2.*,
           case when etapa = 'entregue' then array[]::text[]
                else array_remove(array[
                  case when previsao is null then 'sem_previsao' end,
                  case when previsao < hoje then 'previsao_vencida' end,
                  case when prev_sistema is not null and prev_sistema is distinct from prev_santri then 'atualizar_santri' end,
                  case when precisa is not null and (previsao is null or precisa < previsao) then 'precisa_antes' end,
                  case when fechamento < hoje - 60 then 'parado_60' end,
                  case when pedido_id is null then 'nao_lancado' end], null) end alertas
    from b2
    where etapa <> 'entregue' or entregue_em >= hoje - 30)
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
        'prev_sistema', b3.prev_sistema, 'prev_santri', b3.prev_santri, 'previsao', b3.previsao, 'precisa', b3.precisa,
        'alertas', to_jsonb(b3.alertas)) order by b3.fechamento, b3.loja_id, b3.numero) from b3), '[]'::jsonb)
  ) into res;
  return res;
end $f$;

revoke execute on function public.tela_pedidos(smallint) from anon, public;
grant execute on function public.tela_pedidos(smallint) to authenticated;
