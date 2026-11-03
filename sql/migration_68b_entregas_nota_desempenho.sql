-- Migration 68b: interno.entregas_nota mais rápida, mesmo resultado
-- Antes: a checagem de nota cancelada ia linha a linha (1,4 milhão de comparações) e a ligação da nota agrupada
-- comparava cada nota com cada entrega da loja e lia a observação a cada comparação (4 milhões).
-- Agora: cancelamento pelo índice, observação lida uma vez por nota, ligação por loja + cliente (igualdade).
-- Cliente nulo não ocorre (0 entregas e 0 notas de entrega sem cliente em 03/11/2026) e nota sem cliente não deve ligar.

create or replace function interno.entregas_nota(p_lojas smallint[])
returns table(entrega_id bigint, loja_id smallint, entrega text, pedido text, nota_em date, nota_nr text, nota_id bigint)
language sql stable security definer set search_path to '' as $$
  with ent as materialized (
    select e.id, e.loja_id, e.entrega, e.pedido, e.cliente_codigo, e.data_cadastro::date cad
    from public.entregas_santri e
    where e.ativo and e.loja_id = any(p_lojas)
  ), dir as (
    select e.id, e.loja_id, e.entrega, e.pedido, n.emissao, n.nr_nota, n.id nid
    from ent e
    join public.notas_saida n on n.loja_id = e.loja_id and n.tipo_movimento = 'Entregas' and n.cod_movimento = e.entrega
         and n.ativo and n.cliente_codigo = e.cliente_codigo
    where not exists (select 1 from public.notas_saida c
                      where c.loja_id = n.loja_id and c.tipo_movimento = 'Dev. por canc. de entrega'
                        and c.cod_movimento = n.cod_movimento and c.ativo)
  ), propria as (
    select distinct e.id from ent e
    join public.notas_saida r on r.loja_id = e.loja_id and r.tipo_movimento = 'Entregas' and r.cod_movimento = e.entrega and r.ativo
  ), agr as materialized (
    select n.id, n.loja_id, n.cliente_codigo, n.emissao, n.nr_nota,
           replace((regexp_match(n.observacao, '(?:pedido|ped\.?|ao)\s*(?:n[ºo°.]*\s*)?(\d{1,3}(?:\.\d{3})+|\d{4,6})', 'i'))[1], '.', '') ped
    from public.notas_saida n
    where n.tipo_movimento = 'Entregas agrupadas' and n.ativo and n.loja_id = any(p_lojas)
      and not exists (select 1 from public.notas_saida c
                      where c.loja_id = n.loja_id and c.tipo_movimento = 'Dev. por canc. de entrega'
                        and c.cod_movimento = n.cod_movimento and c.ativo)
  ), ag as (
    select e.id, e.loja_id, e.entrega, e.pedido, a.emissao, a.nr_nota, a.id nid
    from ent e
    join agr a on a.loja_id = e.loja_id and a.cliente_codigo = e.cliente_codigo
    where e.cad <= a.emissao
      and (case when a.ped is not null then e.pedido = a.ped else e.cad >= a.emissao - 30 end)
      and not exists (select 1 from propria p where p.id = e.id)
  ), tudo as (
    select * from dir union all select * from ag
  )
  select distinct on (t.id) t.id, t.loja_id, t.entrega, t.pedido, t.emissao, t.nr_nota, t.nid
  from tudo t
  order by t.id, t.emissao desc, t.nid desc
$$;
