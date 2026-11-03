-- Migration 55: dívida total, curva da dívida e tela_dividas; entre lojas fora do atrasado do Total (F2 Caixa, plano 3)
-- Mesmas assinaturas de caixa_atrasados, caixa_projecao e tela_caixa (versões anteriores: migrations 46 e 50).

-- Título entre lojas sai com o grupo entre_lojas também na lista de atrasados
create or replace function interno.caixa_atrasados(p_lojas smallint[], p_hoje date)
returns table(titulo_id bigint, loja smallint, nome text, plano_nome text, grupo text, tipo text, vencimento date, dias int,
              saldo numeric, decisao text, nova_data date, nota text, por_nome text, em timestamptz)
language sql stable security definer set search_path to '' as $$
  select t.id, t.loja_id, t.nome, t.plano_nome,
         case when coalesce(interno.loja_do_cadastro(t.cadastro_codigo) <> t.loja_id, false) then 'entre_lojas' else g.grupo end, t.tipo, t.vencimento, s.dias_atraso,
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

-- O atrasado do Total (mais de uma loja) não conta entre lojas
create or replace function interno.caixa_projecao(p_lojas smallint[], p_hoje date, p_atrasados text, p_vendas text, p_entrada_pct numeric)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
#variable_conflict use_column
declare
  v_saldo0 numeric; v_data_ant date; v_contas jsonb; v_sem_saldo smallint[]; v_informado boolean; v_minimo numeric;
  v_ini_sem date := date_trunc('week', p_hoje)::date;
  v_ini_mes date := date_trunc('month', p_hoje)::date;
  v_sem jsonb; v_mes jsonb; v_prim jsonb; v_buraco jsonb; v_atr numeric; v_atr_nt numeric;
begin
  select coalesce(sum(s.saldo), 0), min(s.data),
         coalesce(jsonb_agg(jsonb_build_object('conta_id', s.conta_id, 'loja', s.loja_id, 'banco', s.banco, 'nome', s.nome, 'saldo', s.saldo, 'data', s.data)
                            order by s.loja_id, s.conta_id), '[]'::jsonb)
    into v_saldo0, v_data_ant, v_contas
    from interno.saldo_caixa(p_lojas) s;
  select array_agg(l) into v_sem_saldo from unnest(p_lojas) l
   where not exists (select 1 from interno.saldo_caixa(array[l]) s where s.saldo is not null);
  v_informado := v_sem_saldo is null;
  select coalesce(sum(caixa_minimo), 0) into v_minimo from public.caixa_parametros where loja_id = any(p_lojas);

  with mov as materialized (select * from interno.caixa_fluxo(p_lojas, p_hoje, p_atrasados, p_vendas, p_entrada_pct)),
  sem as (select k, v_ini_sem + 7 * k ini, v_ini_sem + 7 * k + 6 fim from generate_series(0, 12) k),
  sv as (
    select s.k, s.ini, s.fim,
           coalesce(sum(m.valor) filter (where m.valor > 0), 0) entradas,
           coalesce(-sum(m.valor) filter (where m.valor < 0), 0) saidas,
           (select coalesce(jsonb_object_agg(g.grupo, g.v), '{}'::jsonb)
              from (select m2.grupo, sum(m2.valor) v from mov m2 where m2.data between s.ini and s.fim group by m2.grupo) g) grupos,
           (select coalesce(jsonb_object_agg(g.grupo, g.v), '{}'::jsonb)
              from (select m2.grupo, sum(m2.valor) v from mov m2 where m2.origem <> 'lancado' and m2.data between s.ini and s.fim group by m2.grupo) g) grupos_est
    from sem s left join mov m on m.data between s.ini and s.fim
    group by s.k, s.ini, s.fim
  ),
  sa as (select sv.*, v_saldo0 + sum(sv.entradas - sv.saidas) over (order by sv.k) saldo_fim from sv),
  mes as (select k, (v_ini_mes + make_interval(months => k))::date ini, (v_ini_mes + make_interval(months => k + 1))::date - 1 fim from generate_series(0, 11) k),
  mv as (
    select s.k, s.ini, s.fim,
           coalesce(sum(m.valor) filter (where m.valor > 0), 0) entradas,
           coalesce(-sum(m.valor) filter (where m.valor < 0), 0) saidas,
           (select coalesce(jsonb_object_agg(g.grupo, g.v), '{}'::jsonb)
              from (select m2.grupo, sum(m2.valor) v from mov m2 where m2.data between s.ini and s.fim group by m2.grupo) g) grupos,
           (select coalesce(jsonb_object_agg(g.grupo, g.v), '{}'::jsonb)
              from (select m2.grupo, sum(m2.valor) v from mov m2 where m2.origem <> 'lancado' and m2.data between s.ini and s.fim group by m2.grupo) g) grupos_est
    from mes s left join mov m on m.data between s.ini and s.fim
    group by s.k, s.ini, s.fim
  ),
  ma as (select mv.*, v_saldo0 + sum(mv.entradas - mv.saidas) over (order by mv.k) saldo_fim from mv)
  select (select jsonb_agg(jsonb_build_object('k', sa.k, 'ini', sa.ini, 'fim', sa.fim, 'entradas', sa.entradas, 'saidas', sa.saidas,
                                              'saldo_fim', sa.saldo_fim, 'grupos', sa.grupos, 'grupos_est', sa.grupos_est) order by sa.k) from sa),
         (select jsonb_agg(jsonb_build_object('mes', ma.ini, 'fim', ma.fim, 'entradas', ma.entradas, 'saidas', ma.saidas,
                                              'saldo_fim', ma.saldo_fim, 'grupos', ma.grupos, 'grupos_est', ma.grupos_est) order by ma.k) from ma)
    into v_sem, v_mes;

  if v_informado then
    select jsonb_build_object('k', (e->>'k')::int, 'ini', e->>'ini', 'negativo', (e->>'saldo_fim')::numeric < 0)
      into v_prim from jsonb_array_elements(v_sem) e
     where (e->>'saldo_fim')::numeric < v_minimo order by (e->>'k')::int limit 1;
  end if;
  select jsonb_build_object('valor', (e->>'saldo_fim')::numeric, 'ini', e->>'ini')
    into v_buraco from jsonb_array_elements(v_sem) e order by (e->>'saldo_fim')::numeric, (e->>'k')::int limit 1;

  select coalesce(sum(a.saldo), 0), coalesce(sum(a.saldo) filter (where a.decisao is null), 0)
    into v_atr, v_atr_nt from interno.caixa_atrasados(p_lojas, p_hoje) a
    where not (cardinality(p_lojas) > 1 and a.grupo = 'entre_lojas');

  return jsonb_build_object(
    'saldo', jsonb_build_object('informado', v_informado, 'total', v_saldo0, 'data_mais_antiga', v_data_ant,
                                'lojas_sem_saldo', to_jsonb(coalesce(v_sem_saldo, '{}'::smallint[])), 'contas', v_contas),
    'minimo', v_minimo, 'semanas', v_sem, 'meses', v_mes,
    'kpi', jsonb_build_object('saldo_hoje', v_saldo0, 'saldo_data', v_data_ant, 'primeira_abaixo', v_prim, 'maior_buraco', v_buraco,
                              'atrasado_pagar', v_atr, 'atrasado_nao_triado', v_atr_nt));
end $$;

-- Dívida total, contratos, títulos de dívida sem contrato e a curva da dívida caindo mês a mês.
-- Com mais de uma loja (Total), contratos e títulos entre lojas aparecem na lista mas ficam fora de total, parcela média e curva.
create or replace function interno.dividas_resumo(p_lojas smallint[], p_hoje date)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare
  v_total boolean := cardinality(p_lojas) > 1;
  v_fim12 date := (p_hoje + interval '12 months')::date - 1;
  v_m0 int := extract(year from p_hoje)::int * 12 + extract(month from p_hoje)::int;
  v_res jsonb;
begin
  with recursive d as (
    select dd.* from public.dividas dd where dd.ativo and dd.loja_id = any(p_lojas)
  ), pt as materialized (
    select * from interno.dividas_parcelas_todas(p_lojas, p_hoje)
  ), ptm as (
    -- mês da parcela em relação ao mês de hoje (parcela vencida conta no mês 0)
    select pt.divida_id, pt.vencimento, pt.valor, pt.no_santri,
           greatest((extract(year from pt.vencimento)::int * 12 + extract(month from pt.vencimento)::int) - v_m0, 0) m
    from pt
  ), pm as (
    select ptm.divida_id id, ptm.m, sum(ptm.valor) v from ptm group by 1, 2
  ), pc as (
    select d.id,
           count(ptm.divida_id) filter (where ptm.vencimento >= p_hoje or d.modo = 'santri') faltam,
           coalesce(sum(ptm.valor) filter (where ptm.vencimento >= p_hoje or d.modo = 'santri'), 0) soma_faltam,
           min(ptm.vencimento) filter (where ptm.vencimento >= p_hoje) proxima,
           max(ptm.vencimento) acaba_em,
           max(ptm.m) last_m,
           count(ptm.divida_id) filter (where ptm.no_santri) ps,
           count(ptm.divida_id) filter (where not ptm.no_santri) pf
    from d left join ptm on ptm.divida_id = d.id
    group by d.id
  ), ctr as (
    select d.id, d.credor, d.tipo, d.loja_id, d.outra_loja, d.modo, d.origem, d.saldo_data, d.taxa_mes, d.parcela,
           coalesce(d.saldo_informado, pc.soma_faltam) saldo, d.saldo_informado is null saldo_estimado,
           pc.faltam, pc.proxima, pc.acaba_em, coalesce(pc.last_m, 0) last_m, pc.ps, pc.pf,
           d.tipo = 'entre_lojas' entre, d.tipo = 'entre_lojas' and v_total fora,
           (d.santri_cadastro is not null and exists (
              select 1 from public.dividas o
               where o.ativo and o.id <> d.id and o.loja_id = d.loja_id and o.santri_cadastro = d.santri_cadastro
                 and o.santri_plano is not distinct from d.santri_plano and o.santri_doc_prefixo is not distinct from d.santri_doc_prefixo)) repetido
    from d join pc on pc.id = d.id
  ), rec as (
    -- saldo no começo de cada mês: s(m+1) = s(m) x (1 + taxa) - parcelas do mês m, nunca abaixo de 0
    select c.id, 0 m, c.saldo s from ctr c where not c.fora
    union all
    select rc.id, rc.m + 1, greatest(rc.s * (1 + coalesce(c.taxa_mes, 0) / 100) - coalesce(pm.v, 0), 0)
    from rec rc join ctr c on c.id = rc.id left join pm on pm.id = rc.id and pm.m = rc.m
    where rc.m < c.last_m
  ), sct as (
    -- títulos de dívida (grupo dívida) que não casam o filtro de nenhum contrato ativo
    select t.id, t.loja_id, t.cadastro_codigo cad, t.nome, t.plano_codigo, t.plano_nome, t.vencimento, a.saldo_aberto saldo,
           coalesce(interno.loja_do_cadastro(t.cadastro_codigo) <> t.loja_id, false) entre,
           greatest((extract(year from t.vencimento)::int * 12 + extract(month from t.vencimento)::int) - v_m0, 0) o
    from interno.titulos_aberto('pagar', p_hoje) a
    join public.titulos_santri t on t.id = a.titulo_id
    where a.loja_id = any(p_lojas) and a.status <> 'pago' and a.saldo_aberto > 0 and coalesce(t.tipo, '') not in ('Pre','Cre','Adi')
      and interno.grupo_caixa(t.plano_codigo, t.plano_nome) = 'divida'
      and not exists (select 1 from public.dividas dd where dd.ativo and interno.divida_casa(dd, t))
      and not exists (select 1 from public.titulos_tratativa tr left join public.dividas dv on dv.id = tr.divida_id
                       where tr.titulo_id = t.id and (tr.decisao = 'nao_e_divida' or (tr.decisao = 'renegociado' and dv.ativo)))
  ), scg as (
    select s.loja_id, s.cad, max(s.nome) nome, max(s.plano_nome) plano_nome, count(*) parcelas, sum(s.saldo) saldo, max(s.vencimento) ultima, bool_or(s.entre) entre
    from sct s group by s.loja_id, s.cad, s.plano_codigo
  ), cv as (
    select rc.m, sum(rc.s) s from rec rc group by rc.m
    union all
    select g.m, sum(s.saldo)
    from sct s cross join generate_series(0, (select coalesce(max(o), 0) from sct)) g(m)
    where s.o >= g.m and not (v_total and s.entre)
    group by g.m
  ), cvt as (
    select cv.m, sum(cv.s) s from cv group by cv.m
  )
  select jsonb_build_object(
    'total', coalesce((select sum(c.saldo) from ctr c where not c.fora), 0) + coalesce((select sum(s.saldo) from sct s where not (v_total and s.entre)), 0),
    'parcela_media_mes', (coalesce((select sum(p.valor) from ptm p join ctr c on c.id = p.divida_id where not c.fora and p.vencimento between p_hoje and v_fim12), 0)
                          + coalesce((select sum(s.saldo) from sct s where not (v_total and s.entre) and s.vencimento between p_hoje and v_fim12), 0)) / 12,
    'sem_contrato_saldo', coalesce((select sum(s.saldo) from sct s where not (v_total and s.entre)), 0),
    'contratos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'credor', c.credor, 'tipo', c.tipo, 'loja', c.loja_id, 'outra_loja', c.outra_loja,
                    'modo', c.modo, 'origem', c.origem, 'saldo', c.saldo, 'saldo_data', c.saldo_data, 'saldo_estimado', c.saldo_estimado, 'taxa_mes', c.taxa_mes,
                    'parcela', c.parcela, 'faltam', c.faltam, 'proxima', c.proxima, 'acaba_em', c.acaba_em, 'parcelas_santri', c.ps, 'parcelas_fora', c.pf,
                    'filtro_repetido', c.repetido, 'entre_lojas', c.entre) order by c.saldo desc, c.id), '[]'::jsonb) from ctr c),
    'sem_contrato', (select coalesce(jsonb_agg(jsonb_build_object('loja', g.loja_id, 'cadastro', g.cad, 'nome', g.nome, 'plano_nome', g.plano_nome,
                    'parcelas', g.parcelas, 'saldo', g.saldo, 'ultima', g.ultima, 'entre_lojas', g.entre) order by g.saldo desc), '[]'::jsonb) from scg g),
    'curva', (select coalesce(jsonb_agg(jsonb_build_object('mes', (date_trunc('month', p_hoje) + make_interval(months => v.m))::date, 'saldo', v.s) order by v.m), '[]'::jsonb) from cvt v),
    'por_loja', (select coalesce(jsonb_agg(jsonb_build_object('loja', l, 'total',
                    coalesce((select sum(c.saldo) from ctr c where c.loja_id = l), 0) + coalesce((select sum(s.saldo) from sct s where s.loja_id = l), 0)) order by l), '[]'::jsonb)
                 from unnest(p_lojas) l)
  ) into v_res;
  return v_res;
end $$;

create or replace function public.tela_dividas(p_loja smallint, p_hoje date default null)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Cuiaba')::date); v_lojas smallint[];
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  v_lojas := interno.lojas_tela(p_loja);
  return interno.dividas_resumo(v_lojas, v_hoje) || jsonb_build_object('hoje', v_hoje, 'lojas', to_jsonb(v_lojas),
    'cadastros', (select coalesce(jsonb_agg(jsonb_build_object('loja', l, 'cadastros_santri', to_jsonb(coalesce(cp.cadastros_santri, '{}'::text[]))) order by l), '[]'::jsonb)
                    from unnest(v_lojas) l left join public.caixa_parametros cp on cp.loja_id = l));
end $$;

-- tela_caixa: kpi.divida (total, parcela média por mês, parte sem contrato), a dívida de cada loja, e atrasados do Total sem entre lojas
create or replace function public.tela_caixa(p_loja smallint, p_atrasados text, p_vendas text, p_entrada_pct numeric, p_hoje date default null)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare
  v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Cuiaba')::date);
  v_lojas smallint[]; v_l smallint; v_proj jsonb; v_p jsonb; v_por jsonb; v_atr jsonb; v_atual jsonb;
  v_perfil jsonb := '[]'::jsonb; v_vm jsonb := '[]'::jsonb; v_pf jsonb; v_dc smallint; v_di smallint; v_dr jsonb;
  v_pagar timestamptz; v_receber timestamptz; v_pbx timestamptz; v_rbx timestamptz;
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  if p_atrasados is null or p_atrasados not in ('triagem','pagar_tudo') then raise exception 'Modo de atrasados inválido'; end if;
  if p_vendas is null or p_vendas not in ('media','meta','zero') then raise exception 'Modo de vendas inválido'; end if;
  if p_entrada_pct is not null and (p_entrada_pct < 0 or p_entrada_pct > 100) then raise exception 'Percentual à vista inválido'; end if;
  v_lojas := interno.lojas_tela(p_loja);
  v_proj := interno.caixa_projecao(v_lojas, v_hoje, p_atrasados, p_vendas, p_entrada_pct);
  v_dr := interno.dividas_resumo(v_lojas, v_hoje);

  -- uma projeção por loja (num laço: em subconsulta o Postgres repetiria a função em cada referência)
  v_por := '[]'::jsonb;
  foreach v_l in array v_lojas loop
    v_p := case when array_length(v_lojas, 1) = 1 then v_proj else interno.caixa_projecao(array[v_l], v_hoje, p_atrasados, p_vendas, p_entrada_pct) end;
    v_dc := null; v_di := null;
    select cp.dia_comissao, cp.dia_impostos into v_dc, v_di from public.caixa_parametros cp where cp.loja_id = v_l;
    v_por := v_por || jsonb_build_array(jsonb_build_object('loja', v_l, 'saldo_hoje', v_p->'kpi'->'saldo_hoje', 'saldo_informado', v_p->'saldo'->'informado',
                                               'minimo', v_p->'minimo', 'primeira_abaixo', v_p->'kpi'->'primeira_abaixo',
                                               'maior_buraco', v_p->'kpi'->'maior_buraco', 'atrasado_pagar', v_p->'kpi'->'atrasado_pagar',
                                               'dia_comissao', coalesce(v_dc, 10), 'dia_impostos', coalesce(v_di, 20),
                                               'divida', (select (e->>'total')::numeric from jsonb_array_elements(v_dr->'por_loja') e where (e->>'loja')::int = v_l)));
    v_pf := interno.caixa_perfil(v_l);
    if v_pf is not null then
      v_perfil := v_perfil || jsonb_build_array(jsonb_build_object('loja', v_l, 'ini', v_pf->'ini', 'fim', v_pf->'fim',
                                                                    'venda_media_mes', v_pf->'venda_media_mes', 'receb0', (interno.caixa_receb(v_pf, p_entrada_pct))[1]));
    end if;
    v_vm := v_vm || coalesce((select jsonb_agg(jsonb_build_object('loja', v_l, 'mes', x.mes, 'venda', x.venda, 'fonte', x.fonte) order by x.mes)
                               from interno.caixa_vendas_mes_media(v_l, v_hoje, p_vendas, (v_pf->>'venda_media_mes')::numeric) x), '[]'::jsonb);
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('titulo_id', a.titulo_id, 'loja', a.loja, 'nome', a.nome, 'plano_nome', a.plano_nome, 'grupo', a.grupo,
                                               'tipo', a.tipo, 'vencimento', a.vencimento, 'dias', a.dias, 'saldo', a.saldo, 'decisao', a.decisao,
                                               'nova_data', a.nova_data, 'nota', a.nota, 'por_nome', a.por_nome, 'em', a.em) order by a.saldo desc, a.titulo_id), '[]'::jsonb)
    into v_atr from interno.caixa_atrasados(v_lojas, v_hoje) a
    where not (cardinality(v_lojas) > 1 and a.grupo = 'entre_lojas');

  select max(criado_em) filter (where tipo = 'pagar'), max(criado_em) filter (where tipo = 'receber'),
         max(criado_em) filter (where tipo = 'pagar_baixas'), max(criado_em) filter (where tipo = 'receber_baixas')
    into v_pagar, v_receber, v_pbx, v_rbx from public.importacoes where status = 'aplicada';
  -- vale a importação mais antiga entre as duas pontas (a pagar e a receber)
  v_atual := jsonb_build_object(
    'titulos', case when v_pagar is null or v_receber is null then null else least(v_pagar, v_receber) end,
    'baixas', case when v_pbx is null or v_rbx is null then null else least(v_pbx, v_rbx) end);

  return jsonb_build_object('hoje', v_hoje, 'lojas', to_jsonb(v_lojas), 'atrasados_modo', p_atrasados, 'vendas_modo', p_vendas, 'entrada_pct', to_jsonb(p_entrada_pct),
                            'atualizado', v_atual, 'saldo', v_proj->'saldo', 'minimo', v_proj->'minimo', 'semanas', v_proj->'semanas', 'meses', v_proj->'meses',
                            'kpi', (v_proj->'kpi') || jsonb_build_object('divida', jsonb_build_object('total', v_dr->'total', 'parcela_media_mes', v_dr->'parcela_media_mes', 'sem_contrato', v_dr->'sem_contrato_saldo')), 'por_loja', v_por, 'perfil', v_perfil, 'vendas_mes', v_vm, 'atrasados', v_atr);
end $$;

revoke execute on function interno.dividas_resumo(smallint[], date) from anon, public;
grant execute on function interno.dividas_resumo(smallint[], date) to authenticated;
revoke execute on function public.tela_dividas(smallint, date) from anon, public;
grant execute on function public.tela_dividas(smallint, date) to authenticated;
