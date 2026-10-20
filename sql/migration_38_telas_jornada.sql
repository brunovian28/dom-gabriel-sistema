-- Migration 38 · Telas do sistema pela jornada (16/10/2026): Direção, Orçamentos, Recebimentos, Chegada, Entregas, Estoque, Financeiro
-- Todas SECURITY DEFINER, cada uma checa o papel e a loja por dentro. p_loja = 0 → as duas lojas (só quem lê as duas).

create or replace function interno.lojas_tela(p_loja smallint) returns smallint[]
language plpgsql stable security definer set search_path to '' as $$
declare r smallint[];
begin
  if not interno.e_ativo() then raise exception 'acesso negado'; end if;
  if coalesce(p_loja,0) = 0 then
    if interno.le_todas_lojas() then select array_agg(id) into r from public.lojas;
    else r := array[interno.minha_loja()]; end if;
  else
    if not (interno.le_todas_lojas() or p_loja = interno.minha_loja()) then raise exception 'sem acesso a esta loja'; end if;
    r := array[p_loja];
  end if;
  return r;
end $$;

-- pagamento de cada pedido de venda (baixas a receber ativas cujo Documento traz o nº do pedido) e o que ainda está em aberto
create or replace function interno.pagamento_pedidos() returns table(numero text, pago numeric, primeiro date, ultimo date, aberto numeric, formas text)
language sql stable security definer set search_path to '' as $$
  with pg as (select t.pedido_numero n, sum(t.valor_baixado) pago, min(b.data_recebimento) prim, max(b.data_recebimento) ult,
                     string_agg(distinct f.forma, ', ') formas
              from public.baixas_santri_titulos t join public.baixas_santri b on b.id = t.baixa_id
              left join public.baixas_santri_formas f on f.baixa_id = b.id and f.ativo
              where b.lado = 'receber' and b.ativo and t.ativo and t.pedido_numero is not null group by 1),
       ab as (select pedido_numero n, sum(saldo) aberto from public.titulos_santri
              where lado = 'receber' and situacao = 'Aberto' and pedido_numero is not null
                and ultima_importacao_id = interno.titulos_ultima_importacao('receber') group by 1)
  select coalesce(pg.n, ab.n), coalesce(pg.pago,0), pg.prim, pg.ult, coalesce(ab.aberto,0), pg.formas
  from pg full join ab on ab.n = pg.n
$$;

create or replace function interno.categoria_receber(p_tipo text, p_plano text) returns text
language sql immutable set search_path to '' as $$
  select case when p_tipo ilike 'cr%dito' or p_plano = 'FORNECEDORES' or p_tipo ilike 'previs%' then 'credito_fornecedor'
              when p_plano ilike 'EMPRESTIMO%' then 'grupo_emprestimos'
              when p_plano ilike 'COMISSAO COM VENDA DIRETA%' then 'venda_direta'
              when p_plano ilike 'RECUPERACAO%' then 'outros'
              else 'clientes' end
$$;

create or replace function interno.categoria_pagar(p_tipo text, p_plano text) returns text
language sql immutable set search_path to '' as $$
  select case when p_tipo = 'Pre' then 'antecipado'
              when p_tipo = 'Cre' then 'credito'
              when p_plano ilike 'EMPRESTIMO%' or p_plano ilike 'CONSORCIO%' then 'emprestimos'
              when p_plano ~* '(ICMS|SIMPLES|COFINS|^PIS$|IMPOSTO|INSS|ISSQN|IRRF|FGTS|TAXAS MUNICIPAIS|DIFAL)' then 'impostos'
              when p_plano ilike 'FORNECEDORES%' or p_plano ilike 'FRETE%' or p_plano ilike 'DESPESAS EXTRAS DE COMPRAS%' then 'fornecedores'
              else 'despesas' end
$$;

create or replace function interno.e_revestimento(p_marca text) returns boolean
language sql immutable set search_path to '' as $$ select upper(coalesce(p_marca,'')) in ('PORTINARI','CEUSA','DURAFLOOR','CASTELATTO') $$;

-- ======================= DIREÇÃO =======================
create or replace function public.painel_direcao(p_loja smallint, p_mes date) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; ini date := date_trunc('month', coalesce(p_mes, current_date))::date; fim date; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if not interno.ve_todas_lojas() then raise exception 'só a direção vê este painel'; end if;
  lojas := interno.lojas_tela(p_loja); fim := (ini + interval '1 month')::date;
  with
  vp as (select * from interno.vendas_periodo(lojas, ini, fim)),
  pag as (select * from interno.pagamento_pedidos()),
  vm as (select v.loja_id, v.numero, v.vlr_liquido, v.data_fechamento::date df, coalesce(p.pago,0) pago, coalesce(p.aberto,0) aberto
         from public.vendas_santri v left join pag p on p.numero = v.numero
         where v.tipo = 'PED' and not v.venda_direta and v.loja_id = any(lojas) and v.data_fechamento >= ini and v.data_fechamento < fim),
  v26 as (select v.loja_id, v.numero, v.vlr_liquido, v.data_fechamento::date df, coalesce(p.pago,0) pago
          from public.vendas_santri v left join pag p on p.numero = v.numero
          where v.tipo = 'PED' and not v.venda_direta and v.loja_id = any(lojas) and v.data_fechamento >= date_trunc('year', ini)),
  orc as (select * from public.orcamentos_santri where loja_id = any(lojas)),
  cp as (select * from public.compras_santri where loja_id = any(lojas)),
  en as (select * from public.entradas_santri where loja_id = any(lojas)),
  eg as (select * from public.entregas_santri where loja_id = any(lojas) and ativo),
  ult_ent as (select max(i.id) id from public.importacoes i where i.status = 'aplicada' and i.tipo = 'entregas'),
  ep as (select p.* from public.entregas_pendentes p, ult_ent u where p.importacao_id = u.id and p.loja_id = any(lojas)),
  ef as (select f.* from public.estoque_foto f where f.loja_id = any(lojas)
         and f.importacao_id = interno.estoque_ultima_importacao(f.loja_id)),
  tit as (select t.*, case when t.lado = 'receber' then interno.categoria_receber(t.tipo, t.plano_nome) else interno.categoria_pagar(t.tipo, t.plano_nome) end cat
          from public.titulos_santri t where t.loja_id = any(lojas) and t.situacao = 'Aberto'
            and t.ultima_importacao_id = interno.titulos_ultima_importacao(t.lado)),
  dre as (select d.* from public.dre_santri d where d.loja_id = any(lojas) and d.ano = extract(year from ini)::int
          and d.importacao_id = (select max(x.importacao_id) from public.dre_santri x where x.loja_id = d.loja_id and x.ano = d.ano)),
  dmes as (select mes, sum(valor) filter (where chave = 'A') receita, sum(valor) filter (where chave = '=margem de contribuicao') mc,
                  sum(valor) filter (where chave = '=resultado liquido') resultado, sum(valor) filter (where chave = 'B.001.003') icms
           from dre group by mes)
  select jsonb_build_object(
    'mes', ini, 'lojas', lojas,
    'comercial', jsonb_build_object(
      'faturamento', (select coalesce(sum(receita),0) from vp), 'mc', (select coalesce(sum(mc),0) from vp),
      'pedidos', (select count(*) from vp where tipo = 'PED'),
      'meta_fat', (select sum(m.faturamento) from public.metas m where m.loja_id = any(lojas) and m.usuario_id is null and m.mes = ini),
      'meta_mc', (select sum(m.mc) from public.metas m where m.loja_id = any(lojas) and m.usuario_id is null and m.mes = ini),
      'pe', (select sum(pl.pe_mc_mensal) from public.parametros_loja pl where pl.loja_id = any(lojas)),
      'parciais', (select count(*) from vp where tipo = 'PED' and not completo)),
    'atendimento', jsonb_build_object(
      'capas_novas', (select count(*) from public.capas c where c.loja_id = any(lojas) and c.data_abertura >= ini and c.data_abertura < fim),
      'contatos', (select count(*) from public.atividades a where a.loja_id = any(lojas) and a.data >= ini and a.data < fim and a.tipo <> 'Orçamento enviado'),
      'capas_abertas', (select count(*) from public.capas c where c.loja_id = any(lojas) and c.status in ('Aberta','Em orçamento'))),
    'orcamentos', jsonb_build_object(
      'abertos', (select count(*) from orc where status = 'Orçamento'),
      'abertos_valor', (select coalesce(sum(vlr_liquido),0) from orc where status = 'Orçamento'),
      'abertos_30', (select count(*) from orc where status = 'Orçamento' and data_estimada < hoje - 30),
      'abertos_30_valor', (select coalesce(sum(vlr_liquido),0) from orc where status = 'Orçamento' and data_estimada < hoje - 30),
      'cancelados', (select count(*) from orc where status = 'Cancelado'),
      'cancelados_valor', (select coalesce(sum(vlr_liquido),0) from orc where status = 'Cancelado'),
      'vendedores_que_cancelam', (select count(distinct vendedor_santri) from orc where status = 'Cancelado'),
      'atualizado', (select max(atualizado_em) from orc)),
    'recebimento', jsonb_build_object(
      'vendas', (select count(*) from vm), 'valor', (select coalesce(sum(vlr_liquido),0) from vm),
      'pagas', (select count(*) from vm where pago >= 0.98 * vlr_liquido),
      'parciais', (select count(*) from vm where pago > 0 and pago < 0.98 * vlr_liquido),
      'sem_pagamento', (select count(*) from vm where pago = 0),
      'recebido', (select coalesce(sum(least(pago, vlr_liquido)),0) from vm),
      'sem_pagamento_7d_ano', (select count(*) from v26 where pago = 0 and df < hoje - 7),
      'sem_pagamento_7d_ano_valor', (select coalesce(sum(vlr_liquido),0) from v26 where pago = 0 and df < hoje - 7),
      'receber_clientes', (select coalesce(sum(saldo),0) from tit where lado = 'receber' and cat = 'clientes'),
      'receber_clientes_vencido', (select coalesce(sum(saldo),0) from tit where lado = 'receber' and cat = 'clientes' and vencimento < hoje)),
    'compras', jsonb_build_object(
      'abertas', (select count(*) from cp where status = 'Aberto'),
      'pendente', (select coalesce(sum(valor_pendencias),0) from cp where status = 'Aberto'),
      'paradas_60', (select count(*) from cp where status = 'Aberto' and data_cadastro < hoje - 60 and not exists (select 1 from public.compras_santri_itens i where i.compra_id = cp.id and i.ativo and coalesce(i.em_entrada,0) > 0)),
      'paradas_60_valor', (select coalesce(sum(valor_pendencias),0) from cp where status = 'Aberto' and data_cadastro < hoje - 60 and not exists (select 1 from public.compras_santri_itens i where i.compra_id = cp.id and i.ativo and coalesce(i.em_entrada,0) > 0)),
      'no_mes', (select count(*) from cp where status <> 'Cancelado' and data_cadastro >= ini and data_cadastro < fim),
      'no_mes_valor', (select coalesce(sum(valor_pedido),0) from cp where status <> 'Cancelado' and data_cadastro >= ini and data_cadastro < fim)),
    'chegada', jsonb_build_object(
      'abertas', (select count(*) from en where status = 'Aberta'),
      'abertas_15', (select count(*) from en where status = 'Aberta' and data_cadastro < hoje - 15),
      'abertas_15_valor', (select coalesce(sum(valor_nota),0) from en where status = 'Aberta' and data_cadastro < hoje - 15),
      'notas_mes', (select count(*) from en where tipo = 'revenda' and data_entrada >= ini and data_entrada < fim and status <> 'Aberta'),
      'frete_mes', (select coalesce(sum(frete_conhec),0) from en where data_entrada >= ini and data_entrada < fim and status <> 'Aberta'),
      'revest_sem_cte_90', (select count(*) from en where tipo = 'revenda' and status <> 'Aberta' and coalesce(frete_conhec,0) = 0 and data_entrada >= hoje - 90
                             and exists (select 1 from public.entradas_santri_itens i join public.produtos p on p.id = i.produto_id
                                         where i.entrada_id = en.id and i.ativo and upper(p.marca) in ('PORTINARI','CEUSA')))),
    'entrega', jsonb_build_object(
      'aguardando', (select count(*) from eg where status_manifesto = 'Aguardando Carregamento'),
      'aguardando_valor', (select coalesce(sum(valor),0) from eg where status_manifesto = 'Aguardando Carregamento'),
      'aguardando_30', (select count(*) from eg where status_manifesto = 'Aguardando Carregamento' and data_cadastro < hoje - 30),
      'aguardando_30_valor', (select coalesce(sum(valor),0) from eg where status_manifesto = 'Aguardando Carregamento' and data_cadastro < hoje - 30),
      'concluidas_mes', (select count(*) from eg where status_entrega = 'Entrega total' and data_cadastro >= ini and data_cadastro < fim),
      'pendentes', (select count(*) from ep where secao = 'pendente'), 'pendentes_valor', (select coalesce(sum(valor),0) from ep where secao = 'pendente'),
      'pendentes_vencidas', (select count(*) from ep where secao = 'pendente' and prev_maior < hoje),
      'sem_agendamento', (select count(*) from ep where secao = 'sem_agendamento'), 'sem_agendamento_valor', (select coalesce(sum(valor),0) from ep where secao = 'sem_agendamento'),
      'foto_em', (select i.criado_em from public.importacoes i, ult_ent u where i.id = u.id)),
    'estoque', jsonb_build_object(
      'valor', (select coalesce(sum(valor),0) from ef),
      'valor_sem_suspeitos', (select coalesce(sum(valor),0) from ef where coalesce(custo,0) < 50000),
      'suspeitos', (select coalesce(jsonb_agg(distinct jsonb_build_object('codigo', codigo, 'nome', nome, 'custo', custo)), '[]'::jsonb) from ef where custo >= 50000),
      'sem_custo', (select count(distinct (loja_id, codigo)) from ef where coalesce(custo,0) = 0),
      'por_local', (select coalesce(jsonb_object_agg(local, v), '{}'::jsonb) from (select local, round(sum(valor) filter (where coalesce(custo,0) < 50000)) v from ef group by local) x),
      'foto_em', (select min(data_foto) from ef)),
    'financeiro', jsonb_build_object(
      'dre', (select coalesce(jsonb_agg(jsonb_build_object('mes', mes, 'receita', receita, 'mc', mc, 'resultado', resultado, 'icms', icms) order by mes), '[]'::jsonb) from dmes where coalesce(receita,0) <> 0),
      'pagar_aberto', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat not in ('antecipado','credito')),
      'pagar_vencido', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat not in ('antecipado','credito') and vencimento < hoje),
      'pagar_30', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat not in ('antecipado','credito') and vencimento between hoje and hoje + 30),
      'antecipado', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat = 'antecipado'),
      'antecipado_90', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat = 'antecipado' and emissao < hoje - 90),
      'creditos', (select coalesce(sum(saldo),0) from tit where lado = 'pagar' and cat = 'credito'),
      'credito_fornecedor', (select coalesce(sum(saldo),0) from tit where lado = 'receber' and cat = 'credito_fornecedor'),
      'sem_plano', (select count(*) from tit where coalesce(plano_nome,'SEM PLANO') = 'SEM PLANO' and lado = 'pagar'),
      'sem_plano_valor', (select coalesce(sum(saldo),0) from tit where coalesce(plano_nome,'SEM PLANO') = 'SEM PLANO' and lado = 'pagar'),
      'foto_em', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo in ('pagar','receber'))),
    'relatorios', (select coalesce(jsonb_agg(jsonb_build_object('tipo', r.tipo, 'nome', r.nome, 'ultima_em', r.ultima_em, 'atrasado', r.atrasado) order by r.ordem), '[]'::jsonb) from public.status_relatorios() r)
  ) into res;
  return res;
end $$;

-- ======================= ORÇAMENTOS =======================
create or replace function public.tela_orcamentos(p_loja smallint) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date; n0 bigint; so_meu text;
begin
  lojas := interno.lojas_tela(p_loja);
  if interno.meu_papel() not in ('admin','direcao','gerente','vendedor') then raise exception 'sem acesso aos orçamentos'; end if;
  if interno.meu_papel() = 'vendedor' then so_meu := (select upper(trim(nome_santri)) from public.usuarios where id = (select auth.uid())); so_meu := coalesce(so_meu, '#'); end if;
  select min(numero::bigint) into n0 from public.orcamentos_santri where numero ~ '^\d+$' and loja_id = any(lojas);
  with
  o as (select * from public.orcamentos_santri where loja_id = any(lojas) and (so_meu is null or upper(trim(vendedor_santri)) = so_meu)),
  v as (select * from public.vendas_santri where tipo = 'PED' and loja_id = any(lojas) and numero ~ '^\d+$' and numero::bigint >= coalesce(n0, 0)
          and (so_meu is null or upper(trim(vendedor_santri)) = so_meu)),
  vend as (select initcap(lower(coalesce(x.vendedor_santri,'?'))) nome, x.loja_id,
             count(*) filter (where x.k = 'O') abertos, sum(x.vl) filter (where x.k = 'O') abertos_valor,
             count(*) filter (where x.k = 'O' and x.de < hoje - 30) a30, count(*) filter (where x.k = 'O' and x.de < hoje - 90) a90,
             count(*) filter (where x.k = 'C') cancelados, sum(x.vl) filter (where x.k = 'C') cancelados_valor,
             count(*) filter (where x.k = 'V') vendidos, sum(x.vl) filter (where x.k = 'V') vendidos_valor
           from (select vendedor_santri, loja_id, case when status = 'Cancelado' then 'C' else 'O' end k, vlr_liquido vl, data_estimada de from o
                 union all select vendedor_santri, loja_id, 'V', vlr_liquido, data_fechamento::date from v) x group by 1, 2),
  capa as (select distinct on (o2.numero_santri) o2.numero_santri, c.id capa_id from public.orcamentos o2 join public.capas c on c.id = o2.capa_id order by o2.numero_santri, o2.criado_em desc)
  select jsonb_build_object(
    'desde_numero', n0,
    'resumo', jsonb_build_object(
      'abertos', (select count(*) from o where status = 'Orçamento'), 'abertos_valor', (select coalesce(sum(vlr_liquido),0) from o where status = 'Orçamento'),
      'cancelados', (select count(*) from o where status = 'Cancelado'), 'cancelados_valor', (select coalesce(sum(vlr_liquido),0) from o where status = 'Cancelado'),
      'vendidos', (select count(*) from v), 'vendidos_valor', (select coalesce(sum(vlr_liquido),0) from v),
      'atualizado', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo like 'orcamentos_%')),
    'idade', (select jsonb_agg(jsonb_build_object('faixa', f, 'qtd', n, 'valor', vl) order by ord) from (
        select case when hoje - data_estimada <= 30 then 'até 30 dias' when hoje - data_estimada <= 90 then '31 a 90 dias' when hoje - data_estimada <= 180 then '91 a 180 dias' else 'mais de 180 dias' end f,
               min(case when hoje - data_estimada <= 30 then 1 when hoje - data_estimada <= 90 then 2 when hoje - data_estimada <= 180 then 3 else 4 end) ord,
               count(*) n, round(sum(vlr_liquido)) vl from o where status = 'Orçamento' group by 1) z),
    'vendedores', (select coalesce(jsonb_agg(to_jsonb(vend) order by coalesce(abertos_valor,0) desc), '[]'::jsonb) from vend),
    'marcas', (select coalesce(jsonb_agg(jsonb_build_object('marca', marca, 'qtd', n, 'valor', vl) order by vl desc), '[]'::jsonb) from (
        select coalesce(i.marca,'?') marca, count(distinct o.id) n, round(sum(i.total_liquido)) vl from o join public.orcamentos_santri_itens i on i.orcamento_id = o.id and i.ativo
        where o.status = 'Orçamento' group by 1 order by 3 desc limit 15) z),
    'abertos', (select coalesce(jsonb_agg(jsonb_build_object('numero', o.numero, 'loja', o.loja_id, 'vendedor', initcap(lower(o.vendedor_santri)), 'cliente', o.cliente_nome,
        'telefone', o.cliente_telefone, 'valor', o.vlr_liquido, 'data', o.data_estimada, 'dias', hoje - o.data_estimada, 'capa_id', capa.capa_id,
        'itens', (select count(*) from public.orcamentos_santri_itens i where i.orcamento_id = o.id and i.ativo)) order by o.vlr_liquido desc), '[]'::jsonb)
        from (select * from o where status = 'Orçamento' order by vlr_liquido desc limit 400) o left join capa on capa.numero_santri = o.numero),
    'cancelados_lista', (select coalesce(jsonb_agg(jsonb_build_object('numero', o.numero, 'loja', o.loja_id, 'vendedor', initcap(lower(o.vendedor_santri)), 'cliente', o.cliente_nome,
        'valor', o.vlr_liquido, 'data', o.data_estimada, 'cancelado_em', o.status_em) order by o.vlr_liquido desc), '[]'::jsonb)
        from (select * from o where status = 'Cancelado' order by vlr_liquido desc limit 200) o)
  ) into res;
  return res;
end $$;

-- ======================= RECEBIMENTOS =======================
create or replace function public.tela_recebimentos(p_loja smallint, p_mes date) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; ini date := date_trunc('month', coalesce(p_mes, current_date))::date; fim date; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if interno.meu_papel() not in ('admin','direcao','gerente','financeiro') then raise exception 'sem acesso aos recebimentos'; end if;
  lojas := interno.lojas_tela(p_loja); fim := (ini + interval '1 month')::date;
  with
  pag as (select * from interno.pagamento_pedidos()),
  v as (select v.loja_id, v.numero, initcap(lower(v.vendedor_santri)) vendedor, v.cliente_nome cliente, v.vlr_liquido valor, v.data_fechamento::date df,
               coalesce(p.pago,0) pago, coalesce(p.aberto,0) aberto, p.primeiro, p.formas
        from public.vendas_santri v left join pag p on p.numero = v.numero
        where v.tipo = 'PED' and not v.venda_direta and v.loja_id = any(lojas) and v.data_fechamento >= date_trunc('year', ini)),
  vm as (select * from v where df >= ini and df < fim),
  bx as (select b.*, f.forma, f.valor fv from public.baixas_santri b join public.baixas_santri_formas f on f.baixa_id = b.id and f.ativo
         where b.lado = 'receber' and b.ativo and b.loja_id = any(lojas) and b.data_recebimento >= ini and b.data_recebimento < fim),
  tr as (select t.*, interno.categoria_receber(t.tipo, t.plano_nome) cat from public.titulos_santri t
         where t.lado = 'receber' and t.situacao = 'Aberto' and t.loja_id = any(lojas) and t.ultima_importacao_id = interno.titulos_ultima_importacao('receber'))
  select jsonb_build_object(
    'mes', ini,
    'resumo', jsonb_build_object('vendas', (select count(*) from vm), 'valor', (select coalesce(sum(valor),0) from vm),
       'pagas', (select count(*) from vm where pago >= 0.98*valor), 'parciais', (select count(*) from vm where pago > 0 and pago < 0.98*valor),
       'sem_pagamento', (select count(*) from vm where pago = 0), 'recebido', (select coalesce(sum(least(pago,valor)),0) from vm),
       'a_receber_programado', (select coalesce(sum(aberto),0) from vm),
       'dias_mediana', (select percentile_cont(0.5) within group (order by primeiro - df) from vm where primeiro is not null),
       'baixas_em', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo = 'receber_baixas')),
    'formas_mes', (select coalesce(jsonb_agg(jsonb_build_object('forma', forma, 'valor', vl, 'qtd', n) order by vl desc), '[]'::jsonb)
                   from (select coalesce(forma,'?') forma, round(sum(fv),2) vl, count(distinct id) n from bx group by 1) z),
    'tipos_mes', (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo_baixa, 'valor', vl) order by vl desc), '[]'::jsonb)
                   from (select coalesce(tipo_baixa,'?') tipo_baixa, round(sum(fv),2) vl from bx group by 1) z),
    'vendas_mes', (select coalesce(jsonb_agg(to_jsonb(vm) order by df desc, numero desc), '[]'::jsonb) from vm),
    'sem_pagamento_ano', (select coalesce(jsonb_agg(to_jsonb(v) order by df), '[]'::jsonb) from (select * from v where pago = 0 and df < hoje - 7 order by df limit 300) v),
    'receber', jsonb_build_object(
       'composicao', (select coalesce(jsonb_object_agg(cat, jsonb_build_object('saldo', s, 'vencido', vc, 'qtd', n)), '{}'::jsonb)
                      from (select cat, round(sum(saldo),2) s, round(sum(saldo) filter (where vencimento < hoje),2) vc, count(*) n from tr group by cat) z),
       'aging_clientes', (select jsonb_agg(jsonb_build_object('faixa', f, 'valor', vl, 'qtd', n) order by ord) from (
           select case when vencimento >= hoje then 'a vencer' when hoje - vencimento <= 30 then 'vencido até 30 dias' when hoje - vencimento <= 90 then '31 a 90 dias' else 'mais de 90 dias' end f,
                  min(case when vencimento >= hoje then 1 when hoje - vencimento <= 30 then 2 when hoje - vencimento <= 90 then 3 else 4 end) ord,
                  round(sum(saldo),2) vl, count(*) n from tr where cat = 'clientes' group by 1) z),
       'clientes_vencidos', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'documento', documento, 'pedido', pedido_numero, 'loja', loja_id, 'vencimento', vencimento,
           'dias', hoje - vencimento, 'saldo', saldo, 'tipo', tipo, 'telefone', telefone) order by saldo desc), '[]'::jsonb)
           from (select * from tr where cat = 'clientes' and vencimento < hoje order by saldo desc limit 150) z),
       'foto_em', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo = 'receber'))
  ) into res;
  return res;
end $$;

-- ======================= CHEGADA (notas de entrada) =======================
create or replace function public.tela_chegada(p_loja smallint) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if not interno.pode_ver_compras() then raise exception 'sem acesso às entradas'; end if;
  lojas := interno.lojas_tela(p_loja);
  with
  en as (select e.*, (select string_agg(c.compra_numero, ', ') from public.entradas_santri_compras c where c.entrada_id = e.id and c.ativo) compras,
                (select bool_or(upper(p.marca) in ('PORTINARI','CEUSA')) from public.entradas_santri_itens i join public.produtos p on p.id = i.produto_id where i.entrada_id = e.id and i.ativo) revest,
                (select string_agg(distinct upper(p.marca), ', ') from public.entradas_santri_itens i join public.produtos p on p.id = i.produto_id where i.entrada_id = e.id and i.ativo) marcas
         from public.entradas_santri e where e.loja_id = any(lojas) and e.data_cadastro >= hoje - 400),
  lt as (select e.id, e.fornecedor_nome, e.loja_id, e.transportadora_nome, e.valor_produtos, e.peso_total, e.frete_conhec, e.data_emissao, e.data_cadastro, e.data_entrada,
                (select min(c.data_compra) from public.entradas_santri_compras c where c.entrada_id = e.id and c.ativo) dc
         from en e where e.tipo = 'revenda' and e.status <> 'Aberta' and e.data_entrada >= hoje - 180),
  linha as (select e.entrada, e.loja_id loja, e.fornecedor_nome fornecedor, e.nr_nota, e.data_emissao emissao, e.data_cadastro cadastro, e.data_entrada entrada_em,
                   hoje - e.data_cadastro dias, e.valor_nota valor, e.compras, e.cte_numero cte, e.transportadora_nome transportadora, e.frete_conhec frete, e.marcas, e.peso_total peso, e.observacao
            from en e)
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'abertas', (select count(*) from en where status = 'Aberta'), 'abertas_valor', (select coalesce(sum(valor_nota),0) from en where status = 'Aberta'),
      'abertas_15', (select count(*) from en where status = 'Aberta' and data_cadastro < hoje - 15),
      'revest_sem_cte', (select count(*) from en where tipo = 'revenda' and status <> 'Aberta' and revest and coalesce(frete_conhec,0) = 0 and data_entrada >= hoje - 180),
      'revest_sem_compra', (select count(*) from en where tipo = 'revenda' and revest and compras is null and data_cadastro >= hoje - 180),
      'sem_peso', (select count(*) from en where tipo = 'revenda' and coalesce(peso_total,0) = 0 and data_cadastro >= hoje - 180),
      'atualizado', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo = 'entradas')),
    'abertas', (select coalesce(jsonb_agg(to_jsonb(l) order by l.dias desc), '[]'::jsonb) from linha l join en e on e.entrada = l.entrada and e.loja_id = l.loja where e.status = 'Aberta'),
    'revest_sem_cte', (select coalesce(jsonb_agg(to_jsonb(l) order by l.entrada_em desc), '[]'::jsonb) from linha l join en e on e.entrada = l.entrada and e.loja_id = l.loja
                        where e.tipo = 'revenda' and e.status <> 'Aberta' and e.revest and coalesce(e.frete_conhec,0) = 0 and e.data_entrada >= hoje - 180),
    'revest_sem_compra', (select coalesce(jsonb_agg(to_jsonb(l) order by l.cadastro desc), '[]'::jsonb) from linha l join en e on e.entrada = l.entrada and e.loja_id = l.loja
                        where e.tipo = 'revenda' and e.revest and e.compras is null and e.data_cadastro >= hoje - 180),
    'fornecedores', (select coalesce(jsonb_agg(to_jsonb(z) order by z.valor desc), '[]'::jsonb) from (
        select fornecedor_nome fornecedor, loja_id loja, count(*) notas, round(sum(valor_produtos)) valor,
               percentile_cont(0.5) within group (order by data_emissao - dc) filter (where dc is not null) compra_nf,
               percentile_cont(0.5) within group (order by data_entrada - data_cadastro) nf_chegada,
               round(100 * sum(frete_conhec) / nullif(sum(valor_produtos) filter (where frete_conhec > 0),0), 1) frete_pct,
               round(1000 * sum(frete_conhec) / nullif(sum(peso_total) filter (where frete_conhec > 0),0)) frete_t,
               count(*) filter (where frete_conhec > 0) com_cte
        from lt group by 1, 2 having count(*) >= 3 order by 4 desc limit 30) z),
    'transportadoras', (select coalesce(jsonb_agg(to_jsonb(z) order by z.frete desc), '[]'::jsonb) from (
        select transportadora_nome transportadora, loja_id loja, count(*) notas, round(sum(frete_conhec)) frete,
               round(100 * sum(frete_conhec) / nullif(sum(valor_produtos),0), 1) frete_pct, round(1000 * sum(frete_conhec) / nullif(sum(peso_total),0)) frete_t
        from lt where frete_conhec > 0 and transportadora_nome is not null group by 1, 2 order by 4 desc limit 15) z)
  ) into res;
  return res;
end $$;

-- ======================= ENTREGAS =======================
create or replace function public.tela_entregas(p_loja smallint) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date; ult bigint;
begin
  if not interno.pode_ver_compras() then raise exception 'sem acesso às entregas'; end if;
  lojas := interno.lojas_tela(p_loja);
  select max(i.id) into ult from public.importacoes i where i.status = 'aplicada' and i.tipo = 'entregas';
  with
  pag as (select * from interno.pagamento_pedidos()),
  ven as (select v.numero, v.vlr_liquido, initcap(lower(v.vendedor_santri)) vendedor, v.data_fechamento::date df from public.vendas_santri v where v.tipo = 'PED'),
  eg as (select e.*, hoje - e.data_cadastro dias, ven.vendedor, ven.df, ven.vlr_liquido venda_valor, coalesce(p.pago,0) pago
         from public.entregas_santri e left join ven on ven.numero = e.pedido left join pag p on p.numero = e.pedido
         where e.loja_id = any(lojas) and e.ativo),
  ag as (select * from eg where status_manifesto = 'Aguardando Carregamento'),
  ep as (select p.*, ven.vendedor, ven.df, coalesce(pg.pago,0) pago, ven.vlr_liquido venda_valor from public.entregas_pendentes p
         left join ven on ven.numero = p.pedido left join pag pg on pg.numero = p.pedido where p.importacao_id = ult and p.loja_id = any(lojas)),
  lin as (select pedido, entrega, loja_id loja, cliente_nome cliente, telefone, local, valor, peso, data_cadastro cadastro, dias, status_separacao separacao,
                 status_manifesto manifesto, status_entrega situacao, cidade, bairro, vendedor, df fechamento, prev_maior previsao,
                 case when venda_valor > 0 then round(100 * least(pago, venda_valor) / venda_valor) end pago_pct from eg)
  select jsonb_build_object(
    'foto_em', (select criado_em from public.importacoes where id = ult),
    'resumo', jsonb_build_object(
      'aguardando', (select count(*) from ag), 'aguardando_valor', (select coalesce(sum(valor),0) from ag), 'aguardando_peso', (select coalesce(sum(peso),0) from ag),
      'aguardando_30', (select count(*) from ag where dias > 30), 'aguardando_30_valor', (select coalesce(sum(valor),0) from ag where dias > 30),
      'aguardando_mediana', (select percentile_cont(0.5) within group (order by dias) from ag),
      'concluidas', (select count(*) from eg where status_entrega = 'Entrega total'), 'parciais', (select count(*) from eg where status_entrega = 'Entrega parcial'),
      'pendentes', (select count(*) from ep where secao = 'pendente'), 'pendentes_valor', (select coalesce(sum(valor),0) from ep where secao = 'pendente'),
      'pendentes_vencidas', (select count(*) from ep where secao = 'pendente' and prev_maior < hoje),
      'sem_agendamento', (select count(*) from ep where secao = 'sem_agendamento'), 'sem_agendamento_valor', (select coalesce(sum(valor),0) from ep where secao = 'sem_agendamento'),
      'pagas_aguardando', (select count(*) from ag where venda_valor > 0 and pago >= 0.98 * venda_valor),
      'pagas_aguardando_valor', (select coalesce(sum(valor),0) from ag where venda_valor > 0 and pago >= 0.98 * venda_valor)),
    'por_local', (select coalesce(jsonb_agg(jsonb_build_object('local', coalesce(local,'?'), 'loja', loja_id, 'qtd', n, 'valor', vl, 'mediana', md) order by loja_id, local), '[]'::jsonb) from (
        select local, loja_id, count(*) n, round(sum(valor)) vl, percentile_cont(0.5) within group (order by dias) md from ag group by 1, 2) z),
    'idade', (select jsonb_agg(jsonb_build_object('faixa', f, 'qtd', n, 'valor', vl) order by ord) from (
        select case when dias <= 30 then 'até 30 dias' when dias <= 90 then '31 a 90 dias' when dias <= 180 then '91 a 180 dias' else 'mais de 180 dias' end f,
               min(case when dias <= 30 then 1 when dias <= 90 then 2 when dias <= 180 then 3 else 4 end) ord, count(*) n, round(sum(valor)) vl from ag group by 1) z),
    'aguardando', (select coalesce(jsonb_agg(to_jsonb(l) order by l.dias desc), '[]'::jsonb) from (select * from lin where manifesto = 'Aguardando Carregamento' order by dias desc limit 500) l),
    'pendentes', (select coalesce(jsonb_agg(jsonb_build_object('secao', secao, 'pedido', pedido, 'loja', loja_id, 'cliente', cliente_nome, 'telefone', telefone, 'valor', valor,
        'cadastro', data_cadastro, 'previsao', prev_maior, 'atraso', case when prev_maior < hoje then hoje - prev_maior end, 'vendedor', vendedor, 'cidade', cidade,
        'itens', jsonb_array_length(coalesce(itens,'[]'::jsonb)),
        'pago_pct', case when venda_valor > 0 then round(100 * least(pago, venda_valor) / venda_valor) end) order by secao, prev_maior nulls last), '[]'::jsonb) from ep)
  ) into res;
  return res;
end $$;

-- ======================= ESTOQUE =======================
create or replace function public.tela_estoque(p_loja smallint) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if not interno.pode_ver_compras() then raise exception 'sem acesso ao estoque'; end if;
  lojas := interno.lojas_tela(p_loja);
  with
  ef as (select f.* from public.estoque_foto f where f.loja_id = any(lojas) and f.importacao_id = interno.estoque_ultima_importacao(f.loja_id)),
  ult as (select e.loja_id, it.codigo, max(e.data_entrada) ult from public.entradas_santri_itens it join public.entradas_santri e on e.id = it.entrada_id
          where e.loja_id = any(lojas) and e.status <> 'Aberta' and it.ativo group by 1, 2),
  vd as (select v.loja_id, i.codigo, max(v.data_fechamento)::date ult_venda from public.vendas_santri_itens i join public.vendas_santri v on v.id = i.venda_id
         where v.loja_id = any(lojas) and v.tipo = 'PED' group by 1, 2),
  p as (select ef.loja_id, ef.codigo, max(ef.nome) nome, max(ef.marca) marca, max(ef.unidade) unidade, max(ef.custo) custo, sum(ef.quantidade) qtd, sum(ef.valor) valor,
               string_agg(ef.local || ': ' || trim(to_char(ef.quantidade, 'FM999G999D00')), ' · ' order by ef.local) locais
        from ef group by 1, 2),
  pp as (select p.*, ult.ult ultima_entrada, vd.ult_venda, coalesce(p.custo,0) >= 50000 suspeito from p left join ult on ult.loja_id = p.loja_id and ult.codigo = p.codigo
         left join vd on vd.loja_id = p.loja_id and vd.codigo = p.codigo)
  select jsonb_build_object(
    'fotos', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja_id, 'data', d)), '[]'::jsonb) from (select loja_id, min(data_foto) d from ef group by 1) z),
    'resumo', jsonb_build_object('produtos', (select count(*) from pp), 'valor', (select coalesce(sum(valor),0) from pp where not suspeito),
       'valor_suspeitos', (select coalesce(sum(valor),0) from pp where suspeito), 'sem_custo', (select count(*) from pp where coalesce(custo,0) = 0),
       'sem_entrada_2026', (select count(*) from pp where not suspeito and (ultima_entrada is null or ultima_entrada < date '2026-01-01')),
       'sem_entrada_2026_valor', (select coalesce(sum(valor),0) from pp where not suspeito and (ultima_entrada is null or ultima_entrada < date '2026-01-01')),
       'entrada_180', (select coalesce(sum(valor),0) from pp where not suspeito and ultima_entrada < hoje - 180 and ultima_entrada >= date '2026-01-01')),
    'por_local', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja_id, 'local', local, 'produtos', n, 'valor', vl) order by loja_id, local), '[]'::jsonb) from (
        select loja_id, local, count(*) n, round(sum(valor) filter (where coalesce(custo,0) < 50000)) vl from ef group by 1, 2) z),
    'por_marca', (select coalesce(jsonb_agg(to_jsonb(z) order by z.valor desc), '[]'::jsonb) from (
        select coalesce(marca,'?') marca, count(*) produtos, round(sum(valor)) valor,
               round(sum(valor) filter (where ultima_entrada is null or ultima_entrada < date '2026-01-01')) parado
        from pp where not suspeito group by 1 order by 3 desc limit 20) z),
    'suspeitos', (select coalesce(jsonb_agg(to_jsonb(pp)), '[]'::jsonb) from pp where suspeito),
    'parados', (select coalesce(jsonb_agg(to_jsonb(z) order by z.valor desc), '[]'::jsonb) from (
        select loja_id loja, codigo, nome, marca, unidade, qtd, valor, custo, locais, ultima_entrada, ult_venda from pp
        where not suspeito and (ultima_entrada is null or ultima_entrada < date '2026-01-01') order by valor desc limit 300) z),
    'sem_custo_lista', (select coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) from (
        select loja_id loja, codigo, nome, marca, unidade, qtd, locais, ultima_entrada from pp where coalesce(custo,0) = 0 order by qtd desc limit 200) z)
  ) into res;
  return res;
end $$;

-- ======================= FINANCEIRO =======================
create or replace function public.tela_financeiro(p_loja smallint, p_ano int) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '60s' as $$
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date; v_ano int := coalesce(p_ano, extract(year from current_date)::int);
begin
  if not interno.pode_ver_financeiro() then raise exception 'sem acesso ao financeiro'; end if;
  lojas := interno.lojas_tela(p_loja);
  with
  dre as (select d.* from public.dre_santri d where d.loja_id = any(lojas) and d.ano = v_ano
          and d.importacao_id = (select max(x.importacao_id) from public.dre_santri x where x.loja_id = d.loja_id and x.ano = d.ano)),
  linhas as (select chave, min(codigo) codigo, min(descricao) descricao, min(nivel) nivel, min(ordem) ordem,
                    jsonb_object_agg(mes, v) meses, sum(v) total
             from (select chave, codigo, descricao, nivel, ordem, mes, sum(valor) v from dre group by 1,2,3,4,5,6) z group by chave),
  tit as (select t.*, case when t.lado = 'receber' then interno.categoria_receber(t.tipo, t.plano_nome) else interno.categoria_pagar(t.tipo, t.plano_nome) end cat
          from public.titulos_santri t where t.loja_id = any(lojas) and t.situacao = 'Aberto' and t.ultima_importacao_id = interno.titulos_ultima_importacao(t.lado)),
  pg as (select * from tit where lado = 'pagar')
  select jsonb_build_object(
    'ano', v_ano,
    'dre', (select coalesce(jsonb_agg(to_jsonb(linhas) order by ordem), '[]'::jsonb) from linhas),
    'dre_em', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo like 'dre_%'),
    'meses_sem_icms', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja_id, 'mes', mes) order by loja_id, mes), '[]'::jsonb) from (
        select loja_id, mes from dre group by 1, 2 having sum(valor) filter (where chave = 'A') > 0 and coalesce(sum(valor) filter (where chave = 'B.001.003'),0) = 0) z),
    'pagar', jsonb_build_object(
      'por_categoria', (select coalesce(jsonb_object_agg(cat, jsonb_build_object('saldo', s, 'vencido', vc, 'qtd', n)), '{}'::jsonb)
                        from (select cat, round(sum(saldo),2) s, round(sum(saldo) filter (where vencimento < hoje),2) vc, count(*) n from pg group by 1) z),
      'agenda', (select jsonb_agg(jsonb_build_object('faixa', f, 'valor', vl, 'qtd', n) order by ord) from (
          select case when vencimento < hoje - 90 then 'vencido há mais de 90 dias' when vencimento < hoje then 'vencido até 90 dias'
                      when vencimento <= hoje + 7 then 'próximos 7 dias' when vencimento <= hoje + 30 then '8 a 30 dias' else 'mais de 30 dias' end f,
                 min(case when vencimento < hoje - 90 then 1 when vencimento < hoje then 2 when vencimento <= hoje + 7 then 3 when vencimento <= hoje + 30 then 4 else 5 end) ord,
                 round(sum(saldo),2) vl, count(*) n from pg where cat not in ('antecipado','credito') group by 1) z),
      'proximos', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'documento', documento, 'vencimento', vencimento, 'saldo', saldo, 'plano', plano_nome, 'loja', loja_id, 'tipo', tipo) order by vencimento), '[]'::jsonb)
                   from (select * from pg where cat not in ('antecipado','credito') and vencimento between hoje and hoje + 15 order by vencimento limit 150) z),
      'vencidos', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'documento', documento, 'vencimento', vencimento, 'dias', hoje - vencimento, 'saldo', saldo, 'plano', plano_nome, 'loja', loja_id) order by saldo desc), '[]'::jsonb)
                   from (select * from pg where cat not in ('antecipado','credito') and vencimento < hoje order by saldo desc limit 150) z)),
    'antecipados', (select coalesce(jsonb_agg(to_jsonb(z) order by z.saldo desc), '[]'::jsonb) from (
        select nome fornecedor, loja_id loja, count(*) qtd, round(sum(saldo),2) saldo, min(emissao) mais_antigo, round(sum(saldo) filter (where emissao < hoje - 90),2) mais_90
        from pg where cat = 'antecipado' group by 1, 2) z),
    'creditos', (select coalesce(jsonb_agg(to_jsonb(z) order by z.saldo desc), '[]'::jsonb) from (
        select case when upper(documento) ~ '^T[RE]?[AN]+B?S?A?N?S?F' or upper(documento) like 'TRAN%' or upper(documento) like 'TREA%' or upper(documento) like 'TRAB%' then 'Transferência entre lojas'
                    when upper(documento) like 'DEV%' then 'Devolução de cliente' when upper(documento) like 'ORC%' then 'Sobra de pedido' else 'Outros' end origem,
               loja_id loja, count(*) qtd, round(sum(saldo),2) saldo from pg where cat = 'credito' group by 1, 2) z),
    'credito_fornecedor', (select coalesce(jsonb_agg(to_jsonb(z) order by z.saldo desc), '[]'::jsonb) from (
        select nome fornecedor, loja_id loja, count(*) qtd, round(sum(saldo),2) saldo, round(sum(saldo) filter (where emissao < hoje - 90),2) mais_90
        from tit where lado = 'receber' and cat = 'credito_fornecedor' group by 1, 2 order by 4 desc limit 30) z),
    'receber', (select coalesce(jsonb_object_agg(cat, jsonb_build_object('saldo', s, 'vencido', vc, 'qtd', n)), '{}'::jsonb)
                from (select cat, round(sum(saldo),2) s, round(sum(saldo) filter (where vencimento < hoje),2) vc, count(*) n from tit where lado = 'receber' group by 1) z),
    'sem_plano', (select coalesce(jsonb_agg(to_jsonb(z) order by z.saldo desc), '[]'::jsonb) from (
        select nome, documento, tipo, loja_id loja, saldo, vencimento from pg where coalesce(plano_nome,'SEM PLANO') = 'SEM PLANO' order by saldo desc limit 100) z),
    'foto_em', (select max(i.criado_em) from public.importacoes i where i.status = 'aplicada' and i.tipo in ('pagar','receber'))
  ) into res;
  return res;
end $$;

-- situação do pedido pelos relatórios do Santri (pago e entregue), para a capa e a lista de pedidos
create or replace function public.situacao_santri_pedidos(p_numeros text[]) returns jsonb
language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_object_agg(n.numero, jsonb_build_object(
    'valor', v.vlr_liquido, 'pago', coalesce(p.pago,0), 'aberto', coalesce(p.aberto,0), 'primeiro_pagamento', p.primeiro, 'formas', p.formas,
    'entregas', (select count(*) from public.entregas_santri e where e.pedido = n.numero and e.ativo),
    'entregues', (select count(*) from public.entregas_santri e where e.pedido = n.numero and e.ativo and e.status_entrega = 'Entrega total'),
    'entregue_em', (select max(e.concluida_em) from public.entregas_santri e where e.pedido = n.numero and e.ativo and e.status_entrega = 'Entrega total'),
    'aguardando', (select count(*) from public.entregas_santri e where e.pedido = n.numero and e.ativo and e.status_manifesto = 'Aguardando Carregamento'),
    'local', (select string_agg(distinct e.local, ', ') from public.entregas_santri e where e.pedido = n.numero and e.ativo and e.status_entrega is distinct from 'Entrega total'))), '{}'::jsonb)
  from unnest(p_numeros) n(numero)
  left join public.vendas_santri v on v.tipo = 'PED' and v.numero = n.numero
  left join interno.pagamento_pedidos() p on p.numero = n.numero
  where (select interno.e_ativo()) and (v.id is null or (select interno.le_todas_lojas()) or v.loja_id = (select interno.minha_loja()))
$$;
