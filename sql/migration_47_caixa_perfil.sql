-- Migration 47: perfil das vendas para o Caixa (média, percentuais, ritmo de recebimento) e dias de pagar a RT e os impostos (F2 Caixa, plano 2)

alter table public.caixa_parametros add column if not exists dia_comissao smallint not null default 10 check (dia_comissao between 1 and 28);
alter table public.caixa_parametros add column if not exists dia_impostos smallint not null default 20 check (dia_impostos between 1 and 28);

-- Perfil de uma loja nos 6 meses completos antes do mês da última venda importada (a importação cobre as duas lojas).
-- Devolve null quando a loja não tem pedido na janela.
-- Comissão = só a RT dos arquitetos (a comissão dos vendedores é paga na folha). Frete soma ao custo (decisão do Bruno, 02/11/2026).
create or replace function interno.caixa_perfil(p_loja smallint)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare
  v_fim date; v_ini date; v_ped numeric; v_dev numeric; v_n int;
  v_custo numeric; v_frete numeric; v_imp numeric; v_rt numeric; v_fin numeric;
  v_receb numeric[]; v_soma numeric;
begin
  select (date_trunc('month', max(data_fechamento)))::date - 1 into v_fim from public.vendas_santri;
  if v_fim is null then return null; end if;
  v_ini := (date_trunc('month', v_fim) - interval '5 months')::date;

  select coalesce(sum(vlr_liquido) filter (where tipo = 'PED'), 0), coalesce(sum(vlr_liquido) filter (where tipo = 'DEV'), 0),
         count(*) filter (where tipo = 'PED'),
         coalesce(sum(custo_compra_santri) filter (where tipo = 'PED'), 0),
         coalesce(sum((resultado->>'frete')::numeric) filter (where tipo = 'PED'), 0),
         coalesce(sum((resultado->>'impostos')::numeric) filter (where tipo = 'PED'), 0),
         coalesce(sum((resultado->>'rt')::numeric) filter (where tipo = 'PED'), 0),
         coalesce(sum((resultado->>'custo_financeiro')::numeric) filter (where tipo = 'PED'), 0)
    into v_ped, v_dev, v_n, v_custo, v_frete, v_imp, v_rt, v_fin
    from public.vendas_santri
   where loja_id = p_loja and data_fechamento::date between v_ini and v_fim;
  if v_n = 0 or v_ped <= 0 then return null; end if;

  -- quando o dinheiro de cada pedido entrou (ou entra): semanas depois do fechamento
  with ped as (
    select v.numero, v.data_fechamento::date dia from public.vendas_santri v
     where v.loja_id = p_loja and v.tipo = 'PED' and v.data_fechamento::date between v_ini and v_fim
  ), j as (
    select least(greatest(floor((case when t.tipo ilike 'cart%' then t.emissao when t.situacao ilike 'baixado' then t.pagamento else t.vencimento end - ped.dia) / 7.0), 0), 52)::int k,
           t.valor_documento vd
      from public.titulos_santri t
      join ped on ped.numero = t.pedido_numero
     where t.lado = 'receber' and t.loja_id = p_loja and t.ultima_importacao_id = interno.titulos_ultima_importacao('receber')
       and coalesce(t.tipo, '') !~* '^(cr.dito|previs)'
       and (case when t.tipo ilike 'cart%' then t.emissao when t.situacao ilike 'baixado' then t.pagamento else t.vencimento end) is not null
  )
  select array_agg(coalesce(x.v, 0) / v_ped order by g.k) into v_receb
    from generate_series(0, 52) g(k)
    left join (select k, sum(vd) v from j group by k) x on x.k = g.k;

  select sum(e) into v_soma from unnest(v_receb) e;
  if v_soma < 1 then
    v_receb[1] := v_receb[1] + (1 - v_soma);      -- o que não tem título é à vista (semana 0)
  elsif v_soma > 1 then
    v_receb := array(select e / v_soma from unnest(v_receb) e);
  end if;

  return jsonb_build_object('ini', v_ini, 'fim', v_fim, 'venda_media_mes', (v_ped - v_dev) / 6,
    'pct', jsonb_build_object('custo_compra', v_custo / v_ped, 'frete', v_frete / v_ped, 'impostos', v_imp / v_ped, 'comissao', v_rt / v_ped, 'financeiro', v_fin / v_ped),
    'receb', to_jsonb(v_receb));
end $$;

create or replace function public.salvar_datas_caixa(p_loja smallint, p_dia_comissao smallint, p_dia_impostos smallint)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção definem as datas'; end if;
  if coalesce(p_loja, 0) = 0 or not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  if p_dia_comissao is null or p_dia_comissao not between 1 and 28 or p_dia_impostos is null or p_dia_impostos not between 1 and 28 then
    raise exception 'Dia inválido';
  end if;
  insert into public.caixa_parametros (loja_id, dia_comissao, dia_impostos, atualizado_por, atualizado_em)
  values (p_loja, p_dia_comissao, p_dia_impostos, auth.uid(), now())
  on conflict (loja_id) do update set dia_comissao = excluded.dia_comissao, dia_impostos = excluded.dia_impostos, atualizado_por = auth.uid(), atualizado_em = now();
end $$;

revoke execute on function interno.caixa_perfil(smallint) from anon, public;
grant execute on function interno.caixa_perfil(smallint) to authenticated;
revoke execute on function public.salvar_datas_caixa(smallint, smallint, smallint) from anon, public;
grant execute on function public.salvar_datas_caixa(smallint, smallint, smallint) to authenticated;
