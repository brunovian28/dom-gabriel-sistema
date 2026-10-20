-- Migration 39 (20/10/2026): tela do setor de Compras
-- Fila de compra (vendas pagas sem compra encontrada), prazo pago -> compra, comprado x vendido,
-- mercadoria em trânsito (fábrica / faturada / depósito), compra antes do pagamento e caixa para comprar.
-- Regra do Bruno (20/10): a compra é liberada quando o cliente paga a 1ª parcela (cartão antecipado = quase à vista).

-- Saldo em conta informado pelo financeiro (o Santri não traz o saldo bancário)
create table if not exists public.caixa_saldo (
  id bigint generated always as identity primary key,
  loja_id smallint not null references public.lojas(id),
  data date not null,
  saldo numeric not null,
  observacao text,
  informado_por uuid default auth.uid(),
  criado_em timestamptz not null default now());
create index if not exists caixa_saldo_loja_idx on public.caixa_saldo (loja_id, criado_em desc);
alter table public.caixa_saldo enable row level security;
create policy caixa_saldo_le on public.caixa_saldo for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

-- Marcação de compras na fila (item já comprado, saiu do estoque, venda direta, não comprar)
create table if not exists public.fila_compra_marcas (
  loja_id smallint not null,
  pedido text not null,
  codigo text not null,
  situacao text,
  observacao text,
  por uuid,
  em timestamptz not null default now(),
  primary key (loja_id, pedido, codigo),
  constraint fila_compra_marcas_sit check (situacao is null or situacao in ('comprado','estoque','venda_direta','nao_comprar')));
alter table public.fila_compra_marcas enable row level security;
create policy fila_compra_marcas_le on public.fila_compra_marcas for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

create index if not exists compras_santri_itens_codigo_idx on public.compras_santri_itens (codigo);

-- Família do produto (revestimento): o texto antes do primeiro número, ex. "DOWNTOWN SGR NAT".
-- A fábrica troca o código quando muda a espessura; a venda sai com o código antigo e a compra com o novo.
create or replace function interno.familia_produto(p_marca text, p_nome text)
returns text language sql immutable set search_path = '' as $$
  select case when interno.e_revestimento(p_marca)
              then nullif(trim(substring(upper(coalesce(p_nome,'')) from '^[^0-9]*')), '') end
$$;

-- Marcas compradas para estoque (argamassas): não entram na fila de compra
create or replace function interno.e_marca_estoque(p_marca text)
returns boolean language sql immutable set search_path = '' as $$
  select upper(coalesce(p_marca,'')) in ('PORTOKOLL','CERAMFIX','SIKA')
$$;

create or replace function public.informar_saldo_caixa(p_loja smallint, p_saldo numeric, p_obs text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção informam o saldo'; end if;
  if coalesce(p_loja,0) = 0 then raise exception 'Escolha a loja'; end if;
  if not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  insert into public.caixa_saldo (loja_id, data, saldo, observacao, informado_por)
  values (p_loja, (now() at time zone 'America/Cuiaba')::date, p_saldo, nullif(trim(p_obs),''), auth.uid());
end $$;

create or replace function public.marcar_fila_compra(p_loja smallint, p_pedido text, p_codigo text, p_situacao text, p_obs text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not (interno.pode_ver_compras() and interno.meu_papel() in ('admin','direcao','gerente','compras')) then
    raise exception 'Sem permissão para marcar a fila de compra';
  end if;
  if not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  insert into public.fila_compra_marcas (loja_id, pedido, codigo, situacao, observacao, por, em)
  values (p_loja, p_pedido, p_codigo, nullif(p_situacao,''), nullif(trim(p_obs),''), auth.uid(), now())
  on conflict (loja_id, pedido, codigo) do update
    set situacao = excluded.situacao, observacao = excluded.observacao, por = excluded.por, em = excluded.em;
end $$;

create or replace function public.tela_compras(p_loja smallint)
returns jsonb language plpgsql stable security definer set search_path = '' set statement_timeout = '60s' as $$
#variable_conflict use_column
declare lojas smallint[]; res jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date; fin boolean;
        imp_pagar bigint; imp_receber bigint;
begin
  if not interno.pode_ver_compras() then raise exception 'sem acesso a compras'; end if;
  lojas := interno.lojas_tela(p_loja);
  fin := interno.pode_ver_financeiro();
  imp_pagar := interno.titulos_ultima_importacao('pagar');
  imp_receber := interno.titulos_ultima_importacao('receber');
  with
  pg as materialized (select * from interno.pagamento_pedidos()),
  vd as materialized (
    select v.id, v.loja_id, v.numero, v.data_fechamento::date f, v.cliente_nome, v.vendedor_santri, v.vlr_liquido,
           coalesce(pg.pago,0) pago, pg.primeiro
    from public.vendas_santri v left join pg on pg.numero = v.numero
    where v.tipo = 'PED' and not coalesce(v.venda_direta,false) and v.loja_id = any(lojas) and v.data_fechamento >= hoje - 180),
  vi as materialized (
    select vd.*, i.ordem, i.codigo, i.descricao, upper(coalesce(i.marca,'')) marca, i.quantidade, i.total_liquido,
           coalesce(i.custo_compra_santri,0) custo, interno.familia_produto(i.marca, i.descricao) fam
    from vd join public.vendas_santri_itens i on i.venda_id = vd.id),
  ci as materialized (
    select c.loja_id, c.numero, c.data_cadastro d, it.codigo, upper(coalesce(it.marca,'')) marca, interno.familia_produto(it.marca, it.nome) fam
    from public.compras_santri c join public.compras_santri_itens it on it.compra_id = c.id
    where c.status <> 'Cancelado' and it.ativo and c.loja_id = any(lojas) and c.data_cadastro >= hoje - 400),
  lig as materialized (
    select vi.*, l.numero compra, l.d compra_em, m.situacao marca_sit, m.observacao marca_obs
    from vi
    left join lateral (select ci.numero, ci.d from ci
                       where ci.loja_id = vi.loja_id and ci.d between vi.f - 3 and vi.f + 150
                         and (ci.codigo = vi.codigo or (vi.fam is not null and ci.fam = vi.fam and ci.marca = vi.marca))
                       order by (ci.codigo = vi.codigo) desc, ci.d limit 1) l on true
    left join public.fila_compra_marcas m on m.loja_id = vi.loja_id and m.pedido = vi.numero and m.codigo = vi.codigo and m.situacao is not null),
  st as materialized (
    select lig.*,
           case when compra is not null or marca_sit = 'comprado' then 'comprado'
                when marca_sit in ('venda_direta','nao_comprar') then 'ignorado'
                when marca_sit = 'estoque' or interno.e_marca_estoque(marca) then 'estoque'
                else 'falta' end sit,
           case when pago > 0 then greatest(f, coalesce(primeiro, f)) end liberado
    from lig),
  ef as (select distinct on (loja_id) loja_id, importacao_id from public.estoque_foto
         where loja_id = any(lojas) order by loja_id, data_foto desc, importacao_id desc),
  est as (select e.loja_id, e.codigo, sum(e.quantidade) q from public.estoque_foto e join ef on ef.loja_id = e.loja_id and ef.importacao_id = e.importacao_id
          group by 1, 2),
  falta_it as (select st.*, hoje - st.liberado dias, est.q estoque_q, coalesce(est.q,0) >= st.quantidade com_estoque
               from st left join est on est.loja_id = st.loja_id and est.codigo = st.codigo
               where st.sit = 'falta' and st.pago > 0),
  fila_g as (
    select loja_id loja, numero pedido, com_estoque, min(cliente_nome) cliente, min(vendedor_santri) vendedor, min(f) fechamento, min(liberado) liberado,
           max(dias) dias, max(pago) pago, max(vlr_liquido) valor_venda, round(sum(custo),2) custo, count(*) itens,
           string_agg(distinct marca, ', ') marcas, bool_or(coalesce(estoque_q,0) > 0) algum_estoque,
           jsonb_agg(jsonb_build_object('codigo',codigo,'nome',descricao,'marca',marca,'qtd',quantidade,'custo',round(custo,2),
                                        'venda',round(total_liquido,2),'estoque',estoque_q) order by custo desc) lista,
           (min(f) >= hoje - 60) recente
    from falta_it group by loja_id, numero, com_estoque),
  aguard as (select count(distinct numero) n, coalesce(sum(custo),0) custo from st
             where sit = 'falta' and pago = 0 and f >= hoje - 60),
  prazo as (select loja_id, greatest(0, compra_em - liberado) d from st
            where compra is not null and liberado is not null and f >= hoje - 90),
  antes as (
    select st.loja_id loja, st.compra, min(st.compra_em) compra_em, st.numero pedido, min(st.cliente_nome) cliente, min(st.primeiro) primeiro_pagamento,
           max(st.pago) pago, max(st.vlr_liquido) valor_venda, round(sum(st.custo),2) custo, string_agg(distinct st.marca, ', ') marcas
    from st where st.compra is not null and st.compra_em >= hoje - 90 and (st.pago = 0 or st.primeiro > st.compra_em + 3)
    group by st.loja_id, st.compra, st.numero),
  meses as (select generate_series(date_trunc('month', hoje) - interval '5 month', date_trunc('month', hoje), interval '1 month')::date m),
  cm as (select date_trunc('month', data_cadastro)::date m, loja_id, sum(valor_pedido) v, count(*) n from public.compras_santri
         where status <> 'Cancelado' and loja_id = any(lojas) and data_cadastro >= (select min(m) from meses) group by 1, 2),
  vm as (select date_trunc('month', v.data_fechamento)::date m, v.loja_id,
                sum(case when v.tipo = 'DEV' then -1 else 1 end * coalesce(i.custo_compra_santri,0)) custo,
                sum(case when v.tipo = 'DEV' then -1 else 1 end * coalesce(i.total_liquido,0)) venda
         from public.vendas_santri v join public.vendas_santri_itens i on i.venda_id = v.id
         where v.tipo in ('PED','DEV') and not coalesce(v.venda_direta,false) and v.loja_id = any(lojas)
           and v.data_fechamento >= (select min(m) from meses) group by 1, 2),
  ca as (select c.id, c.loja_id, c.numero, c.fornecedor_nome, c.comprador, c.data_cadastro, hoje - c.data_cadastro dias, c.valor_pendencias, c.nr_pedido_fornecedor, c.anotacao,
                exists (select 1 from public.entradas_santri_compras ec join public.entradas_santri e on e.id = ec.entrada_id
                        where ec.ativo and e.loja_id = c.loja_id and ec.compra_numero = c.numero) tem_nota,
                coalesce((select bool_or(coalesce(it.entregues,0) > 0 or coalesce(it.em_entrada,0) > 0)
                          from public.compras_santri_itens it where it.compra_id = c.id and it.ativo), false) alguma_entrada
         from public.compras_santri c where c.status = 'Aberto' and c.loja_id = any(lojas)),
  fab as (select * from ca where not tem_nota and not alguma_entrada and coalesce(valor_pendencias,0) > 0),
  ep as (select pedido, secao, prev_maior from public.entregas_pendentes
         where importacao_id = (select max(importacao_id) from public.entregas_pendentes)),
  eg as (select pedido, bool_or(status_manifesto ilike 'Aguardando%') aguardando, bool_or(status_entrega ilike 'Entrega total') entregue
         from public.entregas_santri where ativo group by pedido),
  ped_cli as (
    select p.numero pedido, p.cliente_nome cliente,
           case when (select bool_or(entregue) from eg where eg.pedido = p.numero) then 'entregue'
                when exists (select 1 from ep where ep.pedido = p.numero and ep.secao = 'pendente') then 'pendente'
                when exists (select 1 from ep where ep.pedido = p.numero and ep.secao = 'sem_agendamento') then 'sem_agendamento'
                when (select bool_or(aguardando) from eg where eg.pedido = p.numero) then 'gerada'
                else 'sem_info' end situacao,
           (select max(prev_maior) from ep where ep.pedido = p.numero) previsao
    from vd p),
  compra_ped as (select loja_id, compra, array_agg(distinct numero) pedidos from st where compra is not null group by 1, 2),
  nf as (select e.id, e.loja_id loja, e.entrada, e.nr_nota, e.fornecedor_nome fornecedor, e.data_emissao emissao, e.data_cadastro cadastro,
                hoje - e.data_cadastro dias, e.valor_nota valor, e.transportadora_nome transportadora, e.cte_numero cte,
                (select array_agg(ec.compra_numero) from public.entradas_santri_compras ec where ec.entrada_id = e.id and ec.ativo) compras
         from public.entradas_santri e where e.status = 'Aberta' and e.tipo = 'revenda' and e.loja_id = any(lojas)),
  nf_l as (
    select nf.*, (select jsonb_agg(to_jsonb(pc) order by pc.previsao nulls last) from ped_cli pc
                  where pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = nf.loja and cp.compra = any(nf.compras))) pedidos
    from nf),
  fab_l as (
    select fab.*, (select jsonb_agg(to_jsonb(pc) order by pc.previsao nulls last) from ped_cli pc
                   where pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = fab.loja_id and cp.compra = fab.numero)) pedidos
    from fab),
  dep as (select count(*) n, coalesce(sum(valor),0) valor, percentile_cont(0.5) within group (order by hoje - data_cadastro) mediana,
                 count(*) filter (where data_cadastro < hoje - 30) n30, coalesce(sum(valor) filter (where data_cadastro < hoje - 30),0) valor30
          from public.entregas_santri where ativo and status_manifesto = 'Aguardando Carregamento' and loja_id = any(lojas) and upper(coalesce(local,'')) <> 'LOJA'),
  tit as (select t.loja_id, t.lado, t.vencimento, t.saldo,
                 case when t.lado = 'pagar' then interno.categoria_pagar(t.tipo, t.plano_nome) else interno.categoria_receber(t.tipo, t.plano_nome) end cat
          from public.titulos_santri t
          where fin and t.situacao = 'Aberto' and t.loja_id = any(lojas)
            and t.ultima_importacao_id = case when t.lado = 'pagar' then imp_pagar else imp_receber end),
  sem as (select k, hoje + 7*k ini, case when k = 3 then hoje + 29 else hoje + 7*k + 6 end fim from generate_series(0,3) k),
  caixa as (
    select l.id loja,
           (select jsonb_build_object('saldo', s.saldo, 'data', s.data, 'em', s.criado_em, 'obs', s.observacao)
              from public.caixa_saldo s where s.loja_id = l.id order by s.criado_em desc limit 1) saldo,
           (select jsonb_agg(jsonb_build_object('k', sem.k, 'ini', sem.ini, 'fim', sem.fim,
                     'receber', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'receber' and cat in ('clientes','venda_direta') and vencimento between sem.ini and sem.fim),0),
                     'fornecedores', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'fornecedores' and vencimento between sem.ini and sem.fim),0),
                     'despesas', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'despesas' and vencimento between sem.ini and sem.fim),0),
                     'impostos', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'impostos' and vencimento between sem.ini and sem.fim),0),
                     'emprestimos', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'emprestimos' and vencimento between sem.ini and sem.fim),0)
                   ) order by sem.k) from sem) semanas,
           jsonb_build_object(
             'fornecedores', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'fornecedores' and vencimento < hoje),0),
             'despesas', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'despesas' and vencimento < hoje),0),
             'impostos', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'impostos' and vencimento < hoje),0),
             'emprestimos', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'pagar' and cat = 'emprestimos' and vencimento < hoje),0),
             'receber', coalesce((select sum(saldo) from tit where tit.loja_id = l.id and lado = 'receber' and cat in ('clientes','venda_direta') and vencimento < hoje),0)) vencidos,
           coalesce((select sum(custo) from fila_g where fila_g.loja = l.id and fila_g.recente and not fila_g.com_estoque),0) fila_custo
    from public.lojas l where fin and l.id = any(lojas))
  select jsonb_build_object(
    'hoje', hoje, 'financeiro', fin,
    'atualizado', jsonb_build_object(
       'vendas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'vendas'),
       'compras', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'compras'),
       'baixas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'receber_baixas'),
       'entradas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'entradas'),
       'entregas', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo = 'entregas'),
       'titulos', (select max(criado_em) from public.importacoes where status = 'aplicada' and tipo in ('pagar','receber'))),
    'fila', jsonb_build_object(
       'pedidos', (select count(*) from fila_g where recente and not com_estoque), 'custo', (select coalesce(sum(custo),0) from fila_g where recente and not com_estoque),
       'venda', (select coalesce(sum(valor_venda),0) from fila_g where recente and not com_estoque), 'max_dias', (select max(dias) from fila_g where recente and not com_estoque),
       'atrasados', (select count(*) from fila_g where recente and not com_estoque and dias > 7), 'atrasados_custo', (select coalesce(sum(custo),0) from fila_g where recente and not com_estoque and dias > 7),
       'com_estoque', (select count(*) from fila_g where recente and com_estoque), 'com_estoque_custo', (select coalesce(sum(custo),0) from fila_g where recente and com_estoque),
       'aguardando_pagamento', (select n from aguard), 'aguardando_pagamento_custo', (select custo from aguard)),
    'fila_lista', (select coalesce(jsonb_agg(to_jsonb(f) - 'recente' order by f.dias desc, f.custo desc), '[]'::jsonb) from fila_g f where f.recente and not f.com_estoque),
    'fila_estoque', (select coalesce(jsonb_agg(to_jsonb(f) - 'recente' order by f.dias desc, f.custo desc), '[]'::jsonb) from fila_g f where f.recente and f.com_estoque),
    'fila_antiga', (select coalesce(jsonb_agg(to_jsonb(f) - 'recente' - 'lista' order by f.custo desc), '[]'::jsonb) from fila_g f where not f.recente and not f.com_estoque),
    'prazo', jsonb_build_object(
       'mediana', (select percentile_cont(0.5) within group (order by d) from prazo),
       'ate7', (select round(100.0 * count(*) filter (where d <= 7) / nullif(count(*),0)) from prazo),
       'itens', (select count(*) from prazo),
       'por_loja', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja_id, 'mediana', md, 'ate7', a7, 'itens', n)), '[]'::jsonb) from (
           select loja_id, percentile_cont(0.5) within group (order by d) md, round(100.0 * count(*) filter (where d <= 7) / count(*)) a7, count(*) n
           from prazo group by 1) z)),
    'mes', (select coalesce(jsonb_agg(jsonb_build_object('mes', z.m, 'loja', z.loja_id, 'comprado', coalesce(cm.v,0), 'compras', coalesce(cm.n,0),
                                                          'vendido_custo', coalesce(vm.custo,0), 'vendido', coalesce(vm.venda,0)) order by z.m, z.loja_id), '[]'::jsonb)
            from (select meses.m, l loja_id from meses, unnest(lojas) l) z
            left join cm on cm.m = z.m and cm.loja_id = z.loja_id left join vm on vm.m = z.m and vm.loja_id = z.loja_id),
    'transito', jsonb_build_object(
       'fabrica', (select count(*) from fab), 'fabrica_valor', (select coalesce(sum(valor_pendencias),0) from fab),
       'fabrica_60', (select count(*) from fab where dias > 60), 'fabrica_60_valor', (select coalesce(sum(valor_pendencias),0) from fab where dias > 60),
       'faturada', (select count(*) from nf), 'faturada_valor', (select coalesce(sum(valor),0) from nf),
       'faturada_15', (select count(*) from nf where dias > 15),
       'faturada_sem_data', (select count(*) from nf_l where pedidos is not null and not exists (
            select 1 from jsonb_array_elements(nf_l.pedidos) x where x->>'situacao' in ('pendente','gerada'))),
       'deposito', (select n from dep), 'deposito_valor', (select valor from dep), 'deposito_mediana', (select mediana from dep),
       'deposito_30', (select n30 from dep), 'deposito_30_valor', (select valor30 from dep)),
    'fabrica_lista', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja_id, 'compra', numero, 'fornecedor', fornecedor_nome, 'comprador', comprador,
                         'cadastro', data_cadastro, 'dias', dias, 'pendente', valor_pendencias, 'nr_fornecedor', nr_pedido_fornecedor, 'anotacao', anotacao,
                         'pedidos', pedidos) order by dias desc), '[]'::jsonb) from fab_l),
    'faturada_lista', (select coalesce(jsonb_agg(jsonb_build_object('loja', loja, 'nota', nr_nota, 'entrada', entrada, 'fornecedor', fornecedor, 'emissao', emissao,
                         'cadastro', cadastro, 'dias', dias, 'valor', valor, 'transportadora', transportadora, 'cte', cte,
                         'compras', array_to_string(compras, ', '), 'pedidos', pedidos) order by dias desc), '[]'::jsonb) from nf_l),
    'antes_pagamento', (select coalesce(jsonb_agg(to_jsonb(a) order by a.compra_em desc), '[]'::jsonb) from antes a),
    'caixa', (select coalesce(jsonb_agg(to_jsonb(c) order by c.loja), '[]'::jsonb) from caixa c)
  ) into res;
  return res;
end $$;

grant execute on function public.tela_compras(smallint) to authenticated;
grant execute on function public.informar_saldo_caixa(smallint, numeric, text) to authenticated;
grant execute on function public.marcar_fila_compra(smallint, text, text, text, text) to authenticated;
