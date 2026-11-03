-- Migration 57b: caixa_fluxo só lê títulos a pagar a partir de 6 meses atrás
-- pag alimenta media (6 meses anteriores), pagm (meses futuros) e pagg (mês atual em diante).
-- Com o histórico completo eram 40 mil títulos com grupo_caixa calculado um a um, agora ~5 mil. Resultado igual.

create or replace function interno.caixa_fluxo(p_lojas smallint[], p_hoje date, p_atrasados text, p_vendas text, p_entrada_pct numeric)
 returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean, descricao text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with pag as (
    select t.loja_id, t.plano_codigo, t.plano_nome, t.vencimento, t.valor_documento, interno.grupo_caixa(t.plano_codigo, t.plano_nome) grupo
    from public.titulos_santri t
    where t.lado = 'pagar' and t.ultima_importacao_id = interno.titulos_ultima_importacao('pagar')
      and t.loja_id = any(p_lojas) and t.plano_codigo is not null and t.vencimento is not null
      and t.vencimento >= (date_trunc('month', p_hoje) - interval '6 months')::date
      and coalesce(t.tipo, '') not in ('Pre','Cre','Adi')
  ), pagm as (
    select p.loja_id, p.plano_codigo, date_trunc('month', p.vencimento)::date mes, sum(p.valor_documento) v from pag p group by 1, 2, 3
  ), pagg as (
    select p.loja_id, p.grupo, date_trunc('month', p.vencimento)::date mes, sum(p.valor_documento) v
    from pag p where p.grupo in ('comissoes_rt','impostos') group by 1, 2, 3
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
           f.media - coalesce(pm.v, 0) falta, f.nome
    from fixa f cross join meses ms
    left join pagm pm on pm.loja_id = f.loja_id and pm.plano_codigo = f.plano_codigo and pm.mes = ms.mes
  ), h as (
    select p_hoje hoje, date_trunc('week', p_hoje)::date wk0, (date_trunc('month', p_hoje) + interval '12 months')::date - 1 fim_h
  ), perf as materialized (
    select l loja_id, interno.caixa_perfil(l) perfil from unnest(p_lojas) l
  ), par as (
    select l loja_id, coalesce(cp.dia_comissao, 10)::int dia_com, coalesce(cp.dia_impostos, 20)::int dia_imp
    from unnest(p_lojas) l left join public.caixa_parametros cp on cp.loja_id = l
  ), vm as (
    select p.loja_id, x.mes, x.venda, x.fonte
    from perf p cross join lateral interno.caixa_vendas_mes_media(p.loja_id, p_hoje, p_vendas, (p.perfil->>'venda_media_mes')::numeric) x
    where p.perfil is not null
  ), rcb as (
    select p.loja_id, interno.caixa_receb(p.perfil, p_entrada_pct) arr from perf p where p.perfil is not null
  ), dias as (
    select v.loja_id, h.hoje + i dia, date_trunc('month', h.hoje + i)::date mes, v.fonte,
           v.venda / extract(day from (date_trunc('month', h.hoje + i) + interval '1 month' - interval '1 day')) vdia
    from h cross join generate_series(0, (select fim_h - hoje from h)) i
    join vm v on v.mes = date_trunc('month', h.hoje + i)::date
  ), sw as (
    select d.loja_id, floor((d.dia - h.wk0) / 7.0)::int w, sum(d.vdia) venda, (array_agg(d.fonte order by d.dia))[1] fonte
    from dias d cross join h
    group by d.loja_id, floor((d.dia - h.wk0) / 7.0)::int
  ), swd as (
    select sw.loja_id, sw.w, sw.venda, sw.fonte, greatest(h.wk0 + 7 * sw.w, h.hoje) dw from sw cross join h
  ), ent as (
    select s.loja_id, (s.dw + 7 * (r.k::int - 1))::date data, 'vendas_futuras'::text grupo, s.venda * r.v valor, 'vendas'::text origem,
           case when s.fonte = 'meta' then 'Vendas futuras (meta)' else 'Vendas futuras (média 6 meses)' end descricao
    from swd s
    join rcb on rcb.loja_id = s.loja_id
    cross join h
    cross join lateral unnest(rcb.arr) with ordinality r(v, k)
    where r.v > 0 and s.dw + 7 * (r.k::int - 1) <= h.fim_h
  ), cus as (
    select s.loja_id, s.dw data, 'fornecedor'::text grupo,
           -s.venda * ((p.perfil->'pct'->>'custo_compra')::numeric + (p.perfil->'pct'->>'frete')::numeric) valor,
           'custo_vendas'::text origem, 'Custo das vendas futuras'::text descricao
    from swd s join perf p on p.loja_id = s.loja_id
    union all
    select s.loja_id, s.dw, 'outros'::text, -s.venda * (p.perfil->'pct'->>'financeiro')::numeric, 'custo_vendas'::text, 'Taxa do cartão das vendas futuras'::text
    from swd s join perf p on p.loja_id = s.loja_id
  ), mc as (
    select (date_trunc('month', p_hoje) + make_interval(months => k))::date mes from generate_series(-1, 10) k
  ), vreal as (
    select v.loja_id, date_trunc('month', v.data_fechamento)::date mes,
           sum(case v.tipo when 'PED' then v.vlr_liquido when 'DEV' then -v.vlr_liquido else 0 end) venda
    from public.vendas_santri v
    where v.loja_id = any(p_lojas) and v.data_fechamento >= (select min(mes) from mc) and v.data_fechamento < (select max(mes) from mc) + interval '1 month'
    group by 1, 2
  ), vest as (
    select d.loja_id, d.mes, sum(d.vdia) venda from dias d group by 1, 2
  ), base as (
    select p.loja_id, mc.mes, (mc.mes + interval '1 month')::date pm, p.perfil, pa.dia_com, pa.dia_imp,
           coalesce(vr.venda, 0) + coalesce(ve.venda, 0) base
    from perf p join par pa on pa.loja_id = p.loja_id cross join mc
    left join vreal vr on vr.loja_id = p.loja_id and vr.mes = mc.mes
    left join vest ve on ve.loja_id = p.loja_id and ve.mes = mc.mes
    where p.perfil is not null
  ), cm as (
    select x.loja_id,
           greatest(make_date(extract(year from x.pm)::int, extract(month from x.pm)::int, x.dia_com), p_hoje) data, 'comissoes_rt'::text grupo,
           x.base * (x.perfil->'pct'->>'comissao')::numeric
             - coalesce((select g.v from pagg g where g.loja_id = x.loja_id and g.grupo = 'comissoes_rt' and g.mes = x.pm), 0) falta,
           'comissao_vendas'::text origem, 'RT dos arquitetos das vendas de ' || to_char(x.mes, 'MM/YYYY') descricao
    from base x
    union all
    select x.loja_id,
           greatest(make_date(extract(year from x.pm)::int, extract(month from x.pm)::int, x.dia_imp), p_hoje), 'impostos'::text,
           x.base * (x.perfil->'pct'->>'impostos')::numeric
             - coalesce((select g.v from pagg g where g.loja_id = x.loja_id and g.grupo = 'impostos' and g.mes = x.pm), 0),
           'imposto_vendas'::text, 'Impostos das vendas de ' || to_char(x.mes, 'MM/YYYY')
    from base x
  ), ext as (
    select array(
      select x from unnest(p_lojas) x
      union
      select t.loja_id from public.titulos_santri t
       where t.lado = 'pagar' and t.ultima_importacao_id = interno.titulos_ultima_importacao('pagar')
         and t.loja_id <> all(p_lojas)
         and t.cadastro_codigo = any(array(select unnest(cp.cadastros_santri) from public.caixa_parametros cp where cp.loja_id = any(p_lojas)))
      union
      select d.loja_id from public.dividas d where d.ativo and d.tipo = 'entre_lojas' and d.outra_loja = any(p_lojas)
    ) arr
  ), lan as (
    select l.* from ext, interno.caixa_lancado(ext.arr, p_hoje, p_atrasados) l
  ), esp as (
    select c.cl loja_id, l.data, l.grupo, -l.valor valor, l.origem, l.titulo_id, l.vencido, l.descricao
    from lan l
    join public.titulos_santri t on t.id = l.titulo_id
    cross join lateral (select interno.loja_do_cadastro(t.cadastro_codigo) cl) c
    where l.grupo = 'entre_lojas' and l.valor < 0 and c.cl = any(p_lojas) and c.cl <> l.loja_id
  ), parc as (
    select pt.loja_id, d.tipo, d.outra_loja, pt.vencimento, pt.valor, 'Parcela ' || pt.numero || '/' || pt.n_total || ' · ' || d.credor descricao
    from ext cross join lateral interno.dividas_parcelas_todas(ext.arr, p_hoje) pt
    join public.dividas d on d.id = pt.divida_id
    where not pt.no_santri and pt.vencimento >= p_hoje and pt.vencimento <= (select fim_h from h)
  )
  select u.* from (
    select l.loja_id, l.data, l.grupo, l.valor, l.origem, l.titulo_id, l.vencido, l.descricao
    from lan l where l.loja_id = any(p_lojas)
    union all
    select e.loja_id, e.data, e.grupo, e.valor, e.origem, e.titulo_id, e.vencido, e.descricao from esp e
    union all
    select e.loja_id, e.data, e.grupo, -e.falta, 'fixo'::text, null::bigint, false, e.nome
    from est e
    where e.falta > 0.005
    union all
    select n.loja_id, n.data, n.grupo, n.valor, n.origem, null::bigint, false, n.descricao
    from ent n
    where abs(n.valor) > 0.005
    union all
    select c.loja_id, c.data, c.grupo, c.valor, c.origem, null::bigint, false, c.descricao
    from cus c
    where abs(c.valor) > 0.005
    union all
    select k.loja_id, k.data, k.grupo, -k.falta, k.origem, null::bigint, false, k.descricao
    from cm k
    where k.falta > 0.005
    union all
    select q.loja_id, q.vencimento, case when q.tipo = 'entre_lojas' then 'entre_lojas' else 'divida' end, -q.valor, 'divida'::text, null::bigint, false, q.descricao
    from parc q
    where q.loja_id = any(p_lojas)
    union all
    select q.outra_loja, q.vencimento, 'entre_lojas', q.valor, 'divida'::text, null::bigint, false, q.descricao
    from parc q
    where q.tipo = 'entre_lojas' and q.outra_loja = any(p_lojas)
  ) u
  where not (cardinality(p_lojas) > 1 and u.grupo = 'entre_lojas')
$function$;
