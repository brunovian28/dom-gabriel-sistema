-- Migration 50: tela_caixa e caixa_detalhe com as chaves "vendas futuras" e "% à vista" (F2 Caixa, plano 2)
-- Mudar a lista de parâmetros de uma RPC sem apagar a antiga (o conector recusa apagar função mesmo com aprovação):
-- as versões novas têm p_vendas e p_entrada_pct SEM valor padrão, então o PostgREST não confunde (chamada só com p_loja e p_atrasados vai para a antiga).
-- As antigas, com a mesma assinatura, viram atalho para a nova (p_vendas = 'media', p_entrada_pct = null), sem lógica velha no banco.

-- Projeção de um conjunto de lojas: saldo, semanas, meses e números do topo.
-- Cada semana e cada mês ganha grupos_est: a parte estimada (origem diferente de lancado) de cada grupo.
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
    into v_atr, v_atr_nt from interno.caixa_atrasados(p_lojas, p_hoje) a;

  return jsonb_build_object(
    'saldo', jsonb_build_object('informado', v_informado, 'total', v_saldo0, 'data_mais_antiga', v_data_ant,
                                'lojas_sem_saldo', to_jsonb(coalesce(v_sem_saldo, '{}'::smallint[])), 'contas', v_contas),
    'minimo', v_minimo, 'semanas', v_sem, 'meses', v_mes,
    'kpi', jsonb_build_object('saldo_hoje', v_saldo0, 'saldo_data', v_data_ant, 'primeira_abaixo', v_prim, 'maior_buraco', v_buraco,
                              'atrasado_pagar', v_atr, 'atrasado_nao_triado', v_atr_nt));
end $$;

create or replace function public.tela_caixa(p_loja smallint, p_atrasados text, p_vendas text, p_entrada_pct numeric, p_hoje date default null)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare
  v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Cuiaba')::date);
  v_lojas smallint[]; v_l smallint; v_proj jsonb; v_p jsonb; v_por jsonb; v_atr jsonb; v_atual jsonb;
  v_perfil jsonb := '[]'::jsonb; v_vm jsonb := '[]'::jsonb; v_pf jsonb; v_dc smallint; v_di smallint;
  v_pagar timestamptz; v_receber timestamptz; v_pbx timestamptz; v_rbx timestamptz;
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  if p_atrasados is null or p_atrasados not in ('triagem','pagar_tudo') then raise exception 'Modo de atrasados inválido'; end if;
  if p_vendas is null or p_vendas not in ('media','meta','zero') then raise exception 'Modo de vendas inválido'; end if;
  if p_entrada_pct is not null and (p_entrada_pct < 0 or p_entrada_pct > 100) then raise exception 'Percentual à vista inválido'; end if;
  v_lojas := interno.lojas_tela(p_loja);
  v_proj := interno.caixa_projecao(v_lojas, v_hoje, p_atrasados, p_vendas, p_entrada_pct);

  -- uma projeção por loja (num laço: em subconsulta o Postgres repetiria a função em cada referência)
  v_por := '[]'::jsonb;
  foreach v_l in array v_lojas loop
    v_p := case when array_length(v_lojas, 1) = 1 then v_proj else interno.caixa_projecao(array[v_l], v_hoje, p_atrasados, p_vendas, p_entrada_pct) end;
    v_dc := null; v_di := null;
    select cp.dia_comissao, cp.dia_impostos into v_dc, v_di from public.caixa_parametros cp where cp.loja_id = v_l;
    v_por := v_por || jsonb_build_array(jsonb_build_object('loja', v_l, 'saldo_hoje', v_p->'kpi'->'saldo_hoje', 'saldo_informado', v_p->'saldo'->'informado',
                                               'minimo', v_p->'minimo', 'primeira_abaixo', v_p->'kpi'->'primeira_abaixo',
                                               'maior_buraco', v_p->'kpi'->'maior_buraco', 'atrasado_pagar', v_p->'kpi'->'atrasado_pagar',
                                               'dia_comissao', coalesce(v_dc, 10), 'dia_impostos', coalesce(v_di, 20)));
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
    into v_atr from interno.caixa_atrasados(v_lojas, v_hoje) a;

  select max(criado_em) filter (where tipo = 'pagar'), max(criado_em) filter (where tipo = 'receber'),
         max(criado_em) filter (where tipo = 'pagar_baixas'), max(criado_em) filter (where tipo = 'receber_baixas')
    into v_pagar, v_receber, v_pbx, v_rbx from public.importacoes where status = 'aplicada';
  -- vale a importação mais antiga entre as duas pontas (a pagar e a receber)
  v_atual := jsonb_build_object(
    'titulos', case when v_pagar is null or v_receber is null then null else least(v_pagar, v_receber) end,
    'baixas', case when v_pbx is null or v_rbx is null then null else least(v_pbx, v_rbx) end);

  return jsonb_build_object('hoje', v_hoje, 'lojas', to_jsonb(v_lojas), 'atrasados_modo', p_atrasados, 'vendas_modo', p_vendas, 'entrada_pct', to_jsonb(p_entrada_pct),
                            'atualizado', v_atual, 'saldo', v_proj->'saldo', 'minimo', v_proj->'minimo', 'semanas', v_proj->'semanas', 'meses', v_proj->'meses',
                            'kpi', v_proj->'kpi', 'por_loja', v_por, 'perfil', v_perfil, 'vendas_mes', v_vm, 'atrasados', v_atr);
end $$;

create or replace function public.caixa_detalhe(p_loja smallint, p_grupo text, p_ini date, p_fim date, p_atrasados text, p_vendas text, p_entrada_pct numeric, p_hoje date default null)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Cuiaba')::date); r jsonb;
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  if p_atrasados is null or p_atrasados not in ('triagem','pagar_tudo') then raise exception 'Modo de atrasados inválido'; end if;
  if p_vendas is null or p_vendas not in ('media','meta','zero') then raise exception 'Modo de vendas inválido'; end if;
  if p_entrada_pct is not null and (p_entrada_pct < 0 or p_entrada_pct > 100) then raise exception 'Percentual à vista inválido'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('titulo_id', m.titulo_id, 'loja', m.loja_id, 'nome', coalesce(t.nome, m.descricao), 'plano_nome', t.plano_nome,
                                               'vencimento', t.vencimento, 'data', m.data, 'valor', m.valor, 'vencido', m.vencido, 'decisao', tr.decisao,
                                               'origem', m.origem, 'descricao', m.descricao)
                            order by abs(m.valor) desc, m.titulo_id), '[]'::jsonb)
    into r
    from interno.caixa_fluxo(interno.lojas_tela(p_loja), v_hoje, p_atrasados, p_vendas, p_entrada_pct) m
    left join public.titulos_santri t on t.id = m.titulo_id
    left join public.titulos_tratativa tr on tr.titulo_id = m.titulo_id
   where m.grupo = p_grupo and m.data between p_ini and p_fim;
  return r;
end $$;

-- Assinaturas antigas: atalho para a nova
create or replace function interno.caixa_projecao(p_lojas smallint[], p_hoje date, p_atrasados text)
returns jsonb language sql stable security definer set search_path to '' as $$
  select interno.caixa_projecao(p_lojas, p_hoje, p_atrasados, 'media', null)
$$;

create or replace function public.tela_caixa(p_loja smallint, p_atrasados text default 'triagem', p_hoje date default null)
returns jsonb language sql stable security definer set search_path to '' as $$
  select public.tela_caixa(p_loja, p_atrasados, 'media', null, p_hoje)
$$;

create or replace function public.caixa_detalhe(p_loja smallint, p_grupo text, p_ini date, p_fim date, p_atrasados text default 'triagem', p_hoje date default null)
returns jsonb language sql stable security definer set search_path to '' as $$
  select public.caixa_detalhe(p_loja, p_grupo, p_ini, p_fim, p_atrasados, 'media', null, p_hoje)
$$;

revoke execute on function interno.caixa_projecao(smallint[], date, text, text, numeric) from anon, public;
grant execute on function interno.caixa_projecao(smallint[], date, text, text, numeric) to authenticated;
revoke execute on function public.tela_caixa(smallint, text, text, numeric, date) from anon, public;
grant execute on function public.tela_caixa(smallint, text, text, numeric, date) to authenticated;
revoke execute on function public.caixa_detalhe(smallint, text, date, date, text, text, numeric, date) from anon, public;
grant execute on function public.caixa_detalhe(smallint, text, date, date, text, text, numeric, date) to authenticated;
