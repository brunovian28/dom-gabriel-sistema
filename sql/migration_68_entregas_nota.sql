-- Migration 68: uma regra só para "a mercadoria saiu" em todas as telas (Bruno, 03/11/2026)
-- Saiu = a entrega tem nota de remessa ("Entregas" pelo código da entrega + mesmo cliente, ou "Entregas agrupadas"
-- pelo nº do pedido na observação ou pelo mesmo cliente nos 30 dias antes da nota), sem "Dev. por canc. de entrega".
-- Manifesto "Aguardando carregamento" não quer dizer que a mercadoria está no depósito: na carga de 03/11/2026, as 3.718
-- entregas com manifesto aguardando já tinham nota de remessa.
-- Esta migration cria interno.entregas_nota e faz a tela_pedidos usá-la (mesma lógica das migrations 64, 66 e 67, resultado igual).

create or replace function interno.entregas_nota(p_lojas smallint[])
returns table(entrega_id bigint, loja_id smallint, entrega text, pedido text, nota_em date, nota_nr text, nota_id bigint)
language sql stable security definer set search_path to '' as $$
  with ent as (
    select e.id, e.loja_id, e.entrega, e.pedido, e.cliente_codigo, e.data_cadastro::date cad
    from public.entregas_santri e
    where e.ativo and e.loja_id = any(p_lojas)
  ), canc as (
    select c.loja_id, c.cod_movimento from public.notas_saida c
    where c.tipo_movimento = 'Dev. por canc. de entrega' and c.ativo and c.loja_id = any(p_lojas)
  ), dir as (
    select e.id, e.loja_id, e.entrega, e.pedido, n.emissao, n.nr_nota, n.id nid
    from ent e
    join public.notas_saida n on n.loja_id = e.loja_id and n.tipo_movimento = 'Entregas' and n.cod_movimento = e.entrega
         and n.ativo and n.cliente_codigo is not distinct from e.cliente_codigo
    where not exists (select 1 from canc c where c.loja_id = n.loja_id and c.cod_movimento = n.cod_movimento)
  ), propria as (
    select distinct e.id from ent e
    join public.notas_saida r on r.loja_id = e.loja_id and r.tipo_movimento = 'Entregas' and r.cod_movimento = e.entrega and r.ativo
  ), agr as (
    select n.id, n.loja_id, n.cliente_codigo, n.emissao, n.nr_nota,
           replace((regexp_match(n.observacao, '(?:pedido|ped\.?|ao)\s*(?:n[ºo°.]*\s*)?(\d{1,3}(?:\.\d{3})+|\d{4,6})', 'i'))[1], '.', '') ped
    from public.notas_saida n
    where n.tipo_movimento = 'Entregas agrupadas' and n.ativo and n.loja_id = any(p_lojas)
      and not exists (select 1 from canc c where c.loja_id = n.loja_id and c.cod_movimento = n.cod_movimento)
  ), ag as (
    select e.id, e.loja_id, e.entrega, e.pedido, a.emissao, a.nr_nota, a.id nid
    from ent e
    join agr a on a.loja_id = e.loja_id and a.cliente_codigo is not distinct from e.cliente_codigo
         and e.cad <= a.emissao
         and (case when a.ped is not null then e.pedido = a.ped else e.cad >= a.emissao - 30 end)
    where not exists (select 1 from propria p where p.id = e.id)
  ), tudo as (
    select * from dir union all select * from ag
  )
  select distinct on (t.id) t.id, t.loja_id, t.entrega, t.pedido, t.emissao, t.nr_nota, t.nid
  from tudo t
  order by t.id, t.emissao desc, t.nid desc
$$;

revoke execute on function interno.entregas_nota(smallint[]) from anon, public;
grant execute on function interno.entregas_nota(smallint[]) to authenticated;

-- tela_pedidos passa a ler a nota pela função comum (troca as CTEs agr, remv e rem)
do $$
declare d text; i int; j int;
begin
  d := pg_get_functiondef('public.tela_pedidos(smallint)'::regprocedure);
  i := position('  agr as materialized (' in d);
  j := position('  b1 as (' in d);
  if i = 0 or j <= i then raise exception 'CTEs da remessa não encontradas em tela_pedidos'; end if;
  execute substr(d, 1, i - 1) || $q$  rem as materialized (
    select x.loja_id, x.pedido numero, max(x.nota_em) rem_em,
           (array_agg(x.nota_nr order by x.nota_em desc nulls last, x.nota_id desc))[1] rem_nf
    from interno.entregas_nota(lojas) x
    join vd on vd.loja_id = x.loja_id and vd.numero = x.pedido
    group by x.loja_id, x.pedido),
$q$ || substr(d, j);
end $$;
