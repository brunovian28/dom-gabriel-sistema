-- Migration 67: tela_pedidos, nota de "Entregas agrupadas" passa a marcar as entregas certas
-- Entrega agrupada (Bruno, 03/11/2026): mesmo cliente com mercadoria em depósitos diferentes gera duas ou mais ordens
-- de entrega, e a logística emite UMA nota juntando as ordens. O "Cód. movimento" dessa nota é o número do agrupamento,
-- não o de uma entrega. Ligação:
--   1) a observação traz o nº do pedido ("... ao 15.711"): entregas desse pedido, mesmo cliente;
--   2) senão: entregas do mesmo cliente cadastradas até 30 dias antes da nota.
--   Nos dois casos, só entrega cadastrada até a emissão e sem nota "Entregas" própria.
-- Conferido na carga completa: 611 de 611 números da observação batem com pedido do mesmo cliente; das 1.087 sem número,
-- 1.077 acham entregas candidatas e 1.064 juntam duas ou mais ordens (o caso descrito).
-- Nota "Entregas" continua ligando pelo código da entrega + mesmo cliente (migration 66). Troca feita no texto atual da função.

do $$
declare d text; i int; j int; novo text;
begin
  d := pg_get_functiondef('public.tela_pedidos(smallint)'::regprocedure);
  i := position('  rem as materialized (' in d);
  j := position('  b1 as (' in d);
  if i = 0 or j <= i then raise exception 'CTE rem não encontrada em tela_pedidos'; end if;
  novo := $q$  agr as materialized (
    select n.id, n.loja_id, n.cliente_codigo, n.emissao, n.nr_nota,
           replace((regexp_match(n.observacao, '(?:pedido|ped\.?|ao)\s*(?:n[ºo°.]*\s*)?(\d{1,3}(?:\.\d{3})+|\d{4,6})', 'i'))[1], '.', '') ped
    from public.notas_saida n
    where n.tipo_movimento = 'Entregas agrupadas' and n.ativo and n.loja_id = any(lojas) and n.emissao >= hoje - 400
      and not exists (select 1 from public.notas_saida c
                      where c.loja_id = n.loja_id and c.cod_movimento = n.cod_movimento
                        and c.tipo_movimento = 'Dev. por canc. de entrega' and c.ativo)),
  remv as (
    select g.loja_id, g.pedido numero, n.emissao, n.nr_nota, n.id
    from public.entregas_santri g
    join vd on vd.loja_id = g.loja_id and vd.numero = g.pedido
    join public.notas_saida n on n.loja_id = g.loja_id and n.cod_movimento = g.entrega
         and n.tipo_movimento = 'Entregas' and n.ativo and n.cliente_codigo is not distinct from g.cliente_codigo
    where g.ativo and g.loja_id = any(lojas)
      and not exists (select 1 from public.notas_saida c
                      where c.loja_id = n.loja_id and c.cod_movimento = n.cod_movimento
                        and c.tipo_movimento = 'Dev. por canc. de entrega' and c.ativo)
    union all
    select g.loja_id, g.pedido, a.emissao, a.nr_nota, a.id
    from public.entregas_santri g
    join vd on vd.loja_id = g.loja_id and vd.numero = g.pedido
    join agr a on a.loja_id = g.loja_id and a.cliente_codigo is not distinct from g.cliente_codigo
         and g.data_cadastro::date <= a.emissao
         and (case when a.ped is not null then g.pedido = a.ped else g.data_cadastro::date >= a.emissao - 30 end)
    where g.ativo and g.loja_id = any(lojas)
      and not exists (select 1 from public.notas_saida r
                      where r.loja_id = g.loja_id and r.cod_movimento = g.entrega and r.tipo_movimento = 'Entregas' and r.ativo)),
  rem as materialized (
    select remv.loja_id, remv.numero, max(remv.emissao) rem_em,
           (array_agg(remv.nr_nota order by remv.emissao desc nulls last, remv.id desc))[1] rem_nf
    from remv group by remv.loja_id, remv.numero),
$q$;
  execute substr(d, 1, i - 1) || novo || substr(d, j);
end $$;
