-- Migration 27 · Compras do Santri (Relação de Compras - Analítico)
-- Tabelas, segurança, histórico de mudanças, importação (prévia + aplicar) e anotação de compras.

-- ---------- quem vê compras ----------
create or replace function interno.pode_ver_compras() returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce((select ativo and papel in ('admin','direcao','gerente','compras','financeiro','logistica')
                   from public.usuarios where id = (select auth.uid())), false)
$$;

-- ---------- tabelas ----------
create table if not exists public.compras_santri (
  id bigserial primary key,
  loja_id smallint not null references public.lojas(id),
  numero text not null,
  fornecedor_codigo text,
  fornecedor_nome text,
  status text,
  tipo_compra text,
  comprador text,
  data_cadastro date,
  data_fatura date,
  prev_entrega date,
  data_baixa date,
  media_prazo numeric,
  xml_pendente boolean not null default false,
  entrada_realizada boolean not null default false,
  bloqueada boolean not null default false,
  confirmada boolean not null default false,
  conf_gerencia boolean not null default false,
  ped_venda_vinculado boolean not null default false,
  pedidos_venda text,                -- número(s) do pedido de venda, quando o Santri trouxer
  total_bruto numeric, desconto_comercial numeric, desconto numeric, total_st numeric, outras_despesas numeric,
  total_frete numeric, total_ipi numeric, valor_pedido numeric, total_peso numeric,
  qtd_produtos numeric, qtd_itens numeric, qtd_itens_pendentes numeric, valor_pendencias numeric,
  fornecedor_integracao text, enviada_integradora boolean not null default false,
  nr_pedido_fornecedor text,
  assinatura text,
  anotacao text, anotacao_por uuid references public.usuarios(id), anotacao_em timestamptz,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (loja_id, numero)
);
create index if not exists compras_santri_status_idx on public.compras_santri (loja_id, status, data_cadastro);

create table if not exists public.compras_santri_itens (
  compra_id bigint not null references public.compras_santri(id) on delete cascade,
  ordem int not null,
  produto_id bigint,
  codigo text, nome text, unidade text,
  prev_entrega date,
  quantidade numeric, em_analise_xml numeric, em_entrada numeric, entregues numeric, canceladas numeric, saldo_pendente numeric,
  preco numeric, total_bruto numeric, pct_desc numeric, outras_despesas numeric, total_liquido numeric,
  cod_original text, marca text, valor_st numeric,
  ativo boolean not null default true,
  primary key (compra_id, ordem)
);
create index if not exists compras_santri_itens_prod_idx on public.compras_santri_itens (produto_id);

-- histórico: o que mudou entre uma importação e outra (status, entrada, saldo, datas…)
create table if not exists public.compras_santri_eventos (
  id bigserial primary key,
  compra_id bigint not null references public.compras_santri(id) on delete cascade,
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null,
  de text,
  para text
);
create index if not exists compras_santri_eventos_idx on public.compras_santri_eventos (compra_id, em);

create table if not exists public.compras_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

-- ---------- segurança (RLS) ----------
alter table public.compras_santri enable row level security;
alter table public.compras_santri_itens enable row level security;
alter table public.compras_santri_eventos enable row level security;
alter table public.compras_staging enable row level security;

drop policy if exists cs_ler on public.compras_santri;
create policy cs_ler on public.compras_santri for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
drop policy if exists cs_ins on public.compras_santri;
create policy cs_ins on public.compras_santri for insert to authenticated with check ((select interno.ve_todas_lojas()));
drop policy if exists cs_upd on public.compras_santri;
create policy cs_upd on public.compras_santri for update to authenticated
  using ((select interno.ve_todas_lojas())) with check ((select interno.ve_todas_lojas()));

drop policy if exists csi_ler on public.compras_santri_itens;
create policy csi_ler on public.compras_santri_itens for select to authenticated
  using (exists (select 1 from public.compras_santri c where c.id = compras_santri_itens.compra_id));
drop policy if exists csi_ins on public.compras_santri_itens;
create policy csi_ins on public.compras_santri_itens for insert to authenticated with check ((select interno.ve_todas_lojas()));
drop policy if exists csi_upd on public.compras_santri_itens;
create policy csi_upd on public.compras_santri_itens for update to authenticated
  using ((select interno.ve_todas_lojas())) with check ((select interno.ve_todas_lojas()));
drop policy if exists csi_del on public.compras_santri_itens;
create policy csi_del on public.compras_santri_itens for delete to authenticated using ((select interno.ve_todas_lojas()));

drop policy if exists cse_ler on public.compras_santri_eventos;
create policy cse_ler on public.compras_santri_eventos for select to authenticated
  using (exists (select 1 from public.compras_santri c where c.id = compras_santri_eventos.compra_id));
drop policy if exists cse_ins on public.compras_santri_eventos;
create policy cse_ins on public.compras_santri_eventos for insert to authenticated with check ((select interno.ve_todas_lojas()));

drop policy if exists cstg_all on public.compras_staging;
create policy cstg_all on public.compras_staging for all to authenticated
  using ((select interno.ve_todas_lojas())) with check ((select interno.ve_todas_lojas()));

-- ---------- assinatura (decide se a compra mudou) ----------
create or replace function interno.assinatura_compra(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'status', d->'data_fatura', d->'prev_entrega', d->'data_baixa', d->'valor_pedido',
    d->'valor_pendencias', d->'qtd_itens_pendentes', d->'nr_pedido_fornecedor', d->'ped_venda_vinculado', d->'pedidos_venda',
    d->'entrada_realizada', d->'confirmada', d->'conf_gerencia', d->'bloqueada', d->'fornecedor_nome', d->'comprador',
    (select coalesce(jsonb_agg(jsonb_build_array(i->'codigo', i->'quantidade', i->'entregues', i->'em_entrada', i->'canceladas',
        i->'saldo_pendente', i->'preco', i->'prev_entrega') order by (i->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i))::text)
$$;

-- ---------- prévia ----------
create or replace function public.previa_importacao_compras(p_importacao bigint) returns jsonb
language plpgsql set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.ve_todas_lojas() then raise exception 'Sem permissão'; end if;
  with s as (
    select (d->>'loja_id')::smallint loja_id, d->>'numero' numero, d->>'status' status,
           (d->>'data_cadastro')::date dc, coalesce((d->>'valor_pedido')::numeric,0) vp,
           coalesce((d->>'valor_pendencias')::numeric,0) vpend, interno.assinatura_compra(d) sig, d
    from (select dados d from public.compras_staging where importacao_id = p_importacao) z),
  j as (select s.*, c.id cid, c.assinatura csig, c.status cstatus from s
        left join public.compras_santri c on c.loja_id = s.loja_id and c.numero = s.numero),
  it as (select distinct i->>'codigo' cod from s, jsonb_array_elements(coalesce(s.d->'itens','[]'::jsonb)) i)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'itens', (select count(*) from s, jsonb_array_elements(coalesce(s.d->'itens','[]'::jsonb))),
    'valor_pedidos', (select coalesce(sum(vp),0) from s where status <> 'Cancelado'),
    'abertas', (select count(*) from s where status = 'Aberto'),
    'valor_pendente', (select coalesce(sum(vpend),0) from s where status = 'Aberto'),
    'baixadas', (select count(*) from s where status = 'Baixado'),
    'canceladas', (select count(*) from s where status = 'Cancelado'),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(dc) from s), 'ate', (select max(dc) from s),
    'novos', (select count(*) from j where cid is null),
    'alterados', (select count(*) from j where cid is not null and csig is distinct from sig),
    'iguais', (select count(*) from j where cid is not null and csig = sig),
    'mudaram_status', (select count(*) from j where cid is not null and cstatus is distinct from status),
    'produtos_sem_cadastro', (select count(*) from it where cod !~ '^\d+$' or not exists (select 1 from public.produtos p where p.id = it.cod::bigint))
  ) into r;
  return r;
end $$;

-- ---------- aplicar ----------
create or replace function public.aplicar_importacao_compras(p_importacao bigint) returns jsonb
language plpgsql set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; d jsonb; cid bigint; sig text; old public.compras_santri%rowtype;
  o_ent numeric; o_saldo numeric; n_ent numeric; n_saldo numeric;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0;
begin
  if not interno.ve_todas_lojas() then raise exception 'Sem permissão'; end if;
  res := public.previa_importacao_compras(p_importacao);
  for d in select dados from public.compras_staging where importacao_id = p_importacao order by id loop
    sig := interno.assinatura_compra(d); old := null; o_ent := null; o_saldo := null;
    select * into old from public.compras_santri where loja_id = (d->>'loja_id')::smallint and numero = d->>'numero';
    if old.id is not null then
      select coalesce(sum(entregues),0), coalesce(sum(saldo_pendente),0) into o_ent, o_saldo
        from public.compras_santri_itens where compra_id = old.id and ativo;
    end if;
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.compras_santri as c (loja_id, numero, fornecedor_codigo, fornecedor_nome, status, tipo_compra, comprador,
      data_cadastro, data_fatura, prev_entrega, data_baixa, media_prazo, xml_pendente, entrada_realizada, bloqueada, confirmada,
      conf_gerencia, ped_venda_vinculado, pedidos_venda, total_bruto, desconto_comercial, desconto, total_st, outras_despesas,
      total_frete, total_ipi, valor_pedido, total_peso, qtd_produtos, qtd_itens, qtd_itens_pendentes, valor_pendencias,
      fornecedor_integracao, enviada_integradora, nr_pedido_fornecedor, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'numero', d->>'fornecedor_codigo', d->>'fornecedor_nome', d->>'status', d->>'tipo_compra',
      d->>'comprador', (d->>'data_cadastro')::date, (d->>'data_fatura')::date, (d->>'prev_entrega')::date, (d->>'data_baixa')::date,
      (d->>'media_prazo')::numeric, coalesce((d->>'xml_pendente')::boolean,false), coalesce((d->>'entrada_realizada')::boolean,false),
      coalesce((d->>'bloqueada')::boolean,false), coalesce((d->>'confirmada')::boolean,false), coalesce((d->>'conf_gerencia')::boolean,false),
      coalesce((d->>'ped_venda_vinculado')::boolean,false), nullif(d->>'pedidos_venda',''),
      (d->>'total_bruto')::numeric, (d->>'desconto_comercial')::numeric, (d->>'desconto')::numeric, (d->>'total_st')::numeric,
      (d->>'outras_despesas')::numeric, (d->>'total_frete')::numeric, (d->>'total_ipi')::numeric, (d->>'valor_pedido')::numeric,
      (d->>'total_peso')::numeric, (d->>'qtd_produtos')::numeric, (d->>'qtd_itens')::numeric, (d->>'qtd_itens_pendentes')::numeric,
      (d->>'valor_pendencias')::numeric, nullif(d->>'fornecedor_integracao',''), coalesce((d->>'enviada_integradora')::boolean,false),
      nullif(d->>'nr_pedido_fornecedor',''), sig, p_importacao, p_importacao)
    on conflict (loja_id, numero) do update set
      fornecedor_codigo = excluded.fornecedor_codigo, fornecedor_nome = excluded.fornecedor_nome, status = excluded.status,
      tipo_compra = excluded.tipo_compra, comprador = excluded.comprador, data_cadastro = excluded.data_cadastro,
      data_fatura = excluded.data_fatura, prev_entrega = excluded.prev_entrega, data_baixa = excluded.data_baixa,
      media_prazo = excluded.media_prazo, xml_pendente = excluded.xml_pendente, entrada_realizada = excluded.entrada_realizada,
      bloqueada = excluded.bloqueada, confirmada = excluded.confirmada, conf_gerencia = excluded.conf_gerencia,
      ped_venda_vinculado = excluded.ped_venda_vinculado, pedidos_venda = coalesce(excluded.pedidos_venda, c.pedidos_venda),
      total_bruto = excluded.total_bruto, desconto_comercial = excluded.desconto_comercial, desconto = excluded.desconto,
      total_st = excluded.total_st, outras_despesas = excluded.outras_despesas, total_frete = excluded.total_frete,
      total_ipi = excluded.total_ipi, valor_pedido = excluded.valor_pedido, total_peso = excluded.total_peso,
      qtd_produtos = excluded.qtd_produtos, qtd_itens = excluded.qtd_itens, qtd_itens_pendentes = excluded.qtd_itens_pendentes,
      valor_pendencias = excluded.valor_pendencias, fornecedor_integracao = excluded.fornecedor_integracao,
      enviada_integradora = excluded.enviada_integradora, nr_pedido_fornecedor = excluded.nr_pedido_fornecedor,
      assinatura = excluded.assinatura, importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into cid;

    insert into public.compras_santri_itens as t (compra_id, ordem, produto_id, codigo, nome, unidade, prev_entrega, quantidade,
      em_analise_xml, em_entrada, entregues, canceladas, saldo_pendente, preco, total_bruto, pct_desc, outras_despesas,
      total_liquido, cod_original, marca, valor_st, ativo)
    select cid, (i->>'ordem')::int,
      (select p.id from public.produtos p where (i->>'codigo') ~ '^\d+$' and p.id = (i->>'codigo')::bigint),
      i->>'codigo', i->>'nome', i->>'unidade', (i->>'prev_entrega')::date, (i->>'quantidade')::numeric,
      (i->>'em_analise_xml')::numeric, (i->>'em_entrada')::numeric, (i->>'entregues')::numeric, (i->>'canceladas')::numeric,
      (i->>'saldo_pendente')::numeric, (i->>'preco')::numeric, (i->>'total_bruto')::numeric, (i->>'pct_desc')::numeric,
      (i->>'outras_despesas')::numeric, (i->>'total_liquido')::numeric, i->>'cod_original', i->>'marca', (i->>'valor_st')::numeric, true
    from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i
    on conflict (compra_id, ordem) do update set
      produto_id = excluded.produto_id, codigo = excluded.codigo, nome = excluded.nome, unidade = excluded.unidade,
      prev_entrega = excluded.prev_entrega, quantidade = excluded.quantidade, em_analise_xml = excluded.em_analise_xml,
      em_entrada = excluded.em_entrada, entregues = excluded.entregues, canceladas = excluded.canceladas,
      saldo_pendente = excluded.saldo_pendente, preco = excluded.preco, total_bruto = excluded.total_bruto,
      pct_desc = excluded.pct_desc, outras_despesas = excluded.outras_despesas, total_liquido = excluded.total_liquido,
      cod_original = excluded.cod_original, marca = excluded.marca, valor_st = excluded.valor_st, ativo = true;
    -- item que saiu da compra no Santri fica guardado como inativo
    update public.compras_santri_itens set ativo = false
     where compra_id = cid and ativo and ordem > jsonb_array_length(coalesce(d->'itens','[]'::jsonb));

    -- histórico
    select coalesce(sum(entregues),0), coalesce(sum(saldo_pendente),0) into n_ent, n_saldo
      from public.compras_santri_itens where compra_id = cid and ativo;
    if old.id is null then
      insert into public.compras_santri_eventos (compra_id, importacao_id, campo, de, para)
      values (cid, p_importacao, 'status', null, d->>'status');
    else
      insert into public.compras_santri_eventos (compra_id, importacao_id, campo, de, para)
      select cid, p_importacao, x.campo, x.de, x.para from (values
        ('status', old.status, d->>'status'),
        ('data_baixa', old.data_baixa::text, d->>'data_baixa'),
        ('prev_entrega', old.prev_entrega::text, d->>'prev_entrega'),
        ('nr_pedido_fornecedor', old.nr_pedido_fornecedor, nullif(d->>'nr_pedido_fornecedor','')),
        ('valor_pedido', old.valor_pedido::text, (d->>'valor_pedido')::numeric::text),
        ('entregues', o_ent::text, n_ent::text),
        ('saldo_pendente', o_saldo::text, n_saldo::text)
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;
  -- a área de espera (compras_staging) é limpa pela Importadora depois de gravar
  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;

-- ---------- anotação de compras (fica guardada entre importações) ----------
create or replace function public.anotar_compra(p_compra bigint, p_texto text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if not (interno.pode_ver_compras() and interno.meu_papel() in ('admin','direcao','gerente','compras')) then
    raise exception 'Sem permissão para anotar compras';
  end if;
  if not exists (select 1 from public.compras_santri c where c.id = p_compra
                 and (interno.le_todas_lojas() or c.loja_id = interno.minha_loja())) then
    raise exception 'Compra não encontrada';
  end if;
  update public.compras_santri set anotacao = nullif(trim(p_texto),''), anotacao_por = auth.uid(), anotacao_em = now()
   where id = p_compra;
end $$;
