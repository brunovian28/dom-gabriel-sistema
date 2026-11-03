-- Migration 68c: tela Entregas usa a nota de remessa (regra única da migration 68)
-- Sai o "aguardando carregamento" pelo manifesto (as 3.718 entregas assim já tinham nota) e entram:
-- pendentes e sem agendamento (do Santri, como antes), pagas e ainda pendentes, saíram no mês (com nota),
-- manifesto para fechar (nota há mais de 30 dias e manifesto aberto) e gerada sem nota (manifesto aberto, nota ainda não emitida).
-- Corrige também a junção com as vendas, que era só pelo número e repetia linhas quando o número existe nas duas lojas.

create or replace function public.tela_entregas(p_loja smallint)
returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date; ult bigint; ini date;
begin
  if not interno.pode_ver_compras() then raise exception 'sem acesso às entregas'; end if;
  lojas := interno.lojas_tela(p_loja);
  ini := date_trunc('month', hoje)::date;
  select max(i.id) into ult from public.importacoes i where i.status = 'aplicada' and i.tipo = 'entregas';
  with
  pag as materialized (select * from interno.pagamento_pedidos()),
  ven as (select v.loja_id, v.numero, v.vlr_liquido, initcap(lower(v.vendedor_santri)) vendedor, v.data_fechamento::date df
          from public.vendas_santri v where v.tipo = 'PED' and v.loja_id = any(lojas)),
  nota as materialized (select * from interno.entregas_nota(lojas)),
  eg as materialized (
    select e.id, e.loja_id, e.pedido, e.entrega, e.cliente_nome, e.telefone, e.local, e.valor, e.peso, e.data_cadastro, e.status_separacao,
           e.status_manifesto, e.cidade, hoje - e.data_cadastro::date dias, n.nota_em, n.nota_nr, hoje - n.nota_em dias_nota, ven.vendedor
    from public.entregas_santri e
    left join nota n on n.entrega_id = e.id
    left join ven on ven.loja_id = e.loja_id and ven.numero = e.pedido
    where e.loja_id = any(lojas) and e.ativo),
  ep as (
    select p.*, ven.vendedor, coalesce(pg.pago, 0) pago, ven.vlr_liquido venda_valor
    from public.entregas_pendentes p
    left join ven on ven.loja_id = p.loja_id and ven.numero = p.pedido
    left join pag pg on pg.numero = p.pedido
    where p.importacao_id = ult and p.loja_id = any(lojas)),
  fechar as (select * from eg where status_manifesto = 'Aguardando Carregamento' and nota_em < hoje - 30),
  semnota as (select * from eg where status_manifesto = 'Aguardando Carregamento' and nota_em is null),
  sairam as (select * from eg where nota_em >= hoje - 30)
  select jsonb_build_object(
    'foto_em', (select criado_em from public.importacoes where id = ult),
    'notas_em', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'notas_saida'),
    'resumo', jsonb_build_object(
      'pendentes', (select count(*) from ep where secao = 'pendente'), 'pendentes_valor', (select coalesce(sum(valor), 0) from ep where secao = 'pendente'),
      'pendentes_vencidas', (select count(*) from ep where secao = 'pendente' and prev_maior < hoje),
      'sem_agendamento', (select count(*) from ep where secao = 'sem_agendamento'),
      'sem_agendamento_valor', (select coalesce(sum(valor), 0) from ep where secao = 'sem_agendamento'),
      'pagas_pendentes', (select count(*) from ep where venda_valor > 0 and pago >= 0.98 * venda_valor),
      'pagas_pendentes_valor', (select coalesce(sum(valor), 0) from ep where venda_valor > 0 and pago >= 0.98 * venda_valor),
      'sairam_mes', (select count(*) from eg where nota_em >= ini), 'sairam_mes_valor', (select coalesce(sum(valor), 0) from eg where nota_em >= ini),
      'fechar_manifesto', (select count(*) from fechar), 'fechar_manifesto_valor', (select coalesce(sum(valor), 0) from fechar),
      'sem_nota', (select count(*) from semnota), 'sem_nota_valor', (select coalesce(sum(valor), 0) from semnota)),
    'pendentes', (select coalesce(jsonb_agg(jsonb_build_object('secao', secao, 'pedido', pedido, 'loja', loja_id, 'cliente', cliente_nome, 'telefone', telefone, 'valor', valor,
        'cadastro', data_cadastro, 'previsao', prev_maior, 'atraso', case when prev_maior < hoje then hoje - prev_maior end, 'vendedor', vendedor, 'cidade', cidade,
        'itens', jsonb_array_length(coalesce(itens, '[]'::jsonb)),
        'pago_pct', case when venda_valor > 0 then round(100 * least(pago, venda_valor) / venda_valor) end) order by secao, prev_maior nulls last), '[]'::jsonb) from ep),
    'fechar', (select coalesce(jsonb_agg(jsonb_build_object('pedido', pedido, 'entrega', entrega, 'loja', loja_id, 'cliente', cliente_nome, 'local', local,
        'nota', nota_nr, 'nota_em', nota_em, 'dias', dias_nota, 'valor', valor) order by dias_nota desc), '[]'::jsonb)
        from (select * from fechar order by dias_nota desc limit 1000) fechar),
    'sem_nota', (select coalesce(jsonb_agg(jsonb_build_object('pedido', pedido, 'entrega', entrega, 'loja', loja_id, 'cliente', cliente_nome, 'telefone', telefone,
        'local', local, 'cadastro', data_cadastro, 'dias', dias, 'separacao', status_separacao, 'valor', valor, 'peso', peso, 'cidade', cidade, 'vendedor', vendedor)
        order by dias desc), '[]'::jsonb) from semnota),
    'sairam', (select coalesce(jsonb_agg(jsonb_build_object('pedido', pedido, 'entrega', entrega, 'loja', loja_id, 'cliente', cliente_nome, 'cidade', cidade,
        'nota', nota_nr, 'nota_em', nota_em, 'valor', valor, 'vendedor', vendedor) order by nota_em desc, pedido), '[]'::jsonb) from sairam)
  ) into res;
  return res;
end $$;
