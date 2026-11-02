-- Migration 44c: tela_caixa chamava a projeção 7 vezes por loja (expansão de subconsulta). Agora 1 vez por loja.

create or replace function public.tela_caixa(p_loja smallint, p_atrasados text default 'triagem', p_hoje date default null)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare
  v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Cuiaba')::date);
  v_lojas smallint[]; v_l smallint; v_proj jsonb; v_p jsonb; v_por jsonb; v_atr jsonb; v_atual jsonb;
  v_pagar timestamptz; v_receber timestamptz; v_pbx timestamptz; v_rbx timestamptz;
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  if p_atrasados is null or p_atrasados not in ('triagem','pagar_tudo') then raise exception 'Modo de atrasados inválido'; end if;
  v_lojas := interno.lojas_tela(p_loja);
  v_proj := interno.caixa_projecao(v_lojas, v_hoje, p_atrasados);

  -- uma projeção por loja (num laço: em subconsulta o Postgres repetiria a função em cada referência)
  v_por := '[]'::jsonb;
  foreach v_l in array v_lojas loop
    v_p := case when array_length(v_lojas, 1) = 1 then v_proj else interno.caixa_projecao(array[v_l], v_hoje, p_atrasados) end;
    v_por := v_por || jsonb_build_array(jsonb_build_object('loja', v_l, 'saldo_hoje', v_p->'kpi'->'saldo_hoje', 'saldo_informado', v_p->'saldo'->'informado',
                                               'minimo', v_p->'minimo', 'primeira_abaixo', v_p->'kpi'->'primeira_abaixo',
                                               'maior_buraco', v_p->'kpi'->'maior_buraco', 'atrasado_pagar', v_p->'kpi'->'atrasado_pagar'));
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

  return jsonb_build_object('hoje', v_hoje, 'lojas', to_jsonb(v_lojas), 'atrasados_modo', p_atrasados, 'atualizado', v_atual,
                            'saldo', v_proj->'saldo', 'minimo', v_proj->'minimo', 'semanas', v_proj->'semanas', 'meses', v_proj->'meses',
                            'kpi', v_proj->'kpi', 'por_loja', v_por, 'atrasados', v_atr);
end $$;
