-- Migration 30 · (disponivel = true na migration 36) Orçamentos do Santri (Vendas e devoluções – Analítico, status Orçamento e Cancelado)
-- Um arquivo com os abertos (Status "Orçamento") e outro com os cancelados (Status "Cancelado"), período pela data de cadastro do orçamento.
-- O relatório não traz a data do orçamento: o sistema estima pela numeração (o nº do orçamento é sequencial e
-- é o mesmo do pedido) = menor data de fechamento entre os pedidos de número maior ou igual. Sem pedido depois: data em que apareceu pela 1ª vez.

create table if not exists public.orcamentos_santri (
  id bigserial primary key,
  loja_id smallint not null references public.lojas(id),
  numero text not null,
  status text not null,                        -- Orçamento | Cancelado
  vendedor_santri text, usuario_insercao text,
  cliente_codigo text, cliente_nome text, cliente_doc text, cliente_telefone text, cliente_email text,
  vlr_produtos numeric, frete numeric, outras_desp numeric, desconto numeric, vlr_liquido numeric,
  custo_santri numeric, custo_compra_santri numeric,
  data_estimada date,                          -- data provável do orçamento (pela numeração)
  primeira_vez_em date not null default current_date,
  status_em date,                              -- quando o status atual apareceu (cancelado em ~)
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (loja_id, numero)
);
create index if not exists orcamentos_santri_status_idx on public.orcamentos_santri (loja_id, status);

create table if not exists public.orcamentos_santri_itens (
  orcamento_id bigint not null references public.orcamentos_santri(id),
  ordem int not null,
  produto_id bigint, codigo text, descricao text, marca text, promocao boolean,
  quantidade numeric, preco_unitario numeric, total_bruto numeric, total_liquido numeric, custo numeric, custo_compra numeric,
  ativo boolean not null default true,
  primary key (orcamento_id, ordem)
);

create table if not exists public.orcamentos_santri_eventos (
  id bigserial primary key,
  orcamento_id bigint not null references public.orcamentos_santri(id),
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null, de text, para text
);
create index if not exists orcamentos_santri_eventos_idx on public.orcamentos_santri_eventos (orcamento_id, em);

create table if not exists public.orcamentos_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.orcamentos_santri enable row level security;
alter table public.orcamentos_santri_itens enable row level security;
alter table public.orcamentos_santri_eventos enable row level security;
alter table public.orcamentos_staging enable row level security;

create policy os_ler on public.orcamentos_santri for select to authenticated
  using ((select interno.e_ativo()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy osi_ler on public.orcamentos_santri_itens for select to authenticated
  using (exists (select 1 from public.orcamentos_santri o where o.id = orcamentos_santri_itens.orcamento_id));
create policy ose_ler on public.orcamentos_santri_eventos for select to authenticated
  using (exists (select 1 from public.orcamentos_santri o where o.id = orcamentos_santri_eventos.orcamento_id));
create policy ostg_dono on public.orcamentos_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = orcamentos_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = orcamentos_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

-- data provável de um nº de orçamento/pedido pela numeração (sequência única das duas lojas)
create or replace function interno.data_por_numero(p_numero text) returns date
language sql stable security definer set search_path to '' as $$
  select min(v.data_fechamento)::date from public.vendas_santri v
  where v.tipo = 'PED' and p_numero ~ '^\d+$' and v.numero ~ '^\d+$' and v.numero::bigint >= p_numero::bigint
$$;

create or replace function interno.assinatura_orcamento(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'status', d->'vendedor', d->'cliente_codigo', d->'vlr_liquido', d->'desconto', d->'custo',
    (select coalesce(jsonb_agg(jsonb_build_array(i->'codigo', i->'quantidade', i->'total_liquido', i->'custo') order by (i->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i))::text)
$$;

create or replace function public.previa_importacao_orcamentos(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.pode_importar('orcamentos') then raise exception 'Sem permissão para importar orçamentos'; end if;
  with s as (
    select (d->>'loja_id')::smallint loja_id, d->>'numero' numero, d->>'status' status, coalesce((d->>'vlr_liquido')::numeric,0) vl,
           d->>'vendedor' vendedor, jsonb_array_length(coalesce(d->'itens','[]'::jsonb)) nitens, interno.assinatura_orcamento(d) sig
    from (select dados d from public.orcamentos_staging where importacao_id = p_importacao) z),
  j as (select s.*, o.id orc_id, o.assinatura osig, o.status ostatus,
          exists (select 1 from public.vendas_santri v where v.tipo = 'PED' and v.loja_id = s.loja_id and v.numero = s.numero) virou_pedido
        from s left join public.orcamentos_santri o on o.loja_id = s.loja_id and o.numero = s.numero)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'status', (select min(status) from s),
    'valor', (select coalesce(sum(vl),0) from s),
    'itens', (select coalesce(sum(nitens),0) from s),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'valor_pva', (select coalesce(sum(vl),0) from s where loja_id = 1), 'valor_rv', (select coalesce(sum(vl),0) from s where loja_id = 2),
    'vendedores', (select coalesce(jsonb_agg(x order by (x->>'valor')::numeric desc), '[]'::jsonb) from
        (select jsonb_build_object('nome', initcap(lower(vendedor)), 'qtd', count(*), 'valor', round(sum(vl),2)) x from s group by vendedor order by sum(vl) desc) v),
    'novos', (select count(*) from j where orc_id is null),
    'alterados', (select count(*) from j where orc_id is not null and osig is distinct from sig),
    'iguais', (select count(*) from j where orc_id is not null and osig = sig),
    'mudaram_status', (select count(*) from j where orc_id is not null and ostatus is distinct from status),
    'viraram_pedido', (select count(*) from j where virou_pedido)
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_orcamentos(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; d jsonb; orc_id bigint; sig text; old public.orcamentos_santri%rowtype;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0; dia date;
begin
  if not interno.pode_importar('orcamentos') then raise exception 'Sem permissão para importar orçamentos'; end if;
  res := public.previa_importacao_orcamentos(p_importacao);
  select criado_em::date into dia from public.importacoes where id = p_importacao;
  for d in select dados from public.orcamentos_staging where importacao_id = p_importacao order by id loop
    sig := interno.assinatura_orcamento(d); old := null;
    select * into old from public.orcamentos_santri where loja_id = (d->>'loja_id')::smallint and numero = d->>'numero';
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.orcamentos_santri as o (loja_id, numero, status, vendedor_santri, usuario_insercao, cliente_codigo, cliente_nome,
      cliente_doc, cliente_telefone, cliente_email, vlr_produtos, frete, outras_desp, desconto, vlr_liquido, custo_santri, custo_compra_santri,
      data_estimada, primeira_vez_em, status_em, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'numero', d->>'status', d->>'vendedor', d->>'usuario_insercao', d->>'cliente_codigo', d->>'cliente_nome',
      d->>'cliente_doc', d->>'cliente_telefone', d->>'cliente_email', (d->>'vlr_produtos')::numeric, (d->>'frete')::numeric,
      (d->>'outras_desp')::numeric, (d->>'desconto')::numeric, (d->>'vlr_liquido')::numeric, (d->>'custo')::numeric, (d->>'custo_compra')::numeric,
      coalesce(interno.data_por_numero(d->>'numero'), dia), dia, dia, sig, p_importacao, p_importacao)
    on conflict (loja_id, numero) do update set
      status = excluded.status, vendedor_santri = excluded.vendedor_santri, usuario_insercao = excluded.usuario_insercao,
      cliente_codigo = excluded.cliente_codigo, cliente_nome = excluded.cliente_nome, cliente_doc = excluded.cliente_doc,
      cliente_telefone = excluded.cliente_telefone, cliente_email = excluded.cliente_email, vlr_produtos = excluded.vlr_produtos,
      frete = excluded.frete, outras_desp = excluded.outras_desp, desconto = excluded.desconto, vlr_liquido = excluded.vlr_liquido,
      custo_santri = excluded.custo_santri, custo_compra_santri = excluded.custo_compra_santri,
      data_estimada = least(o.data_estimada, excluded.data_estimada),
      status_em = case when o.status is distinct from excluded.status then dia else o.status_em end,
      assinatura = excluded.assinatura, importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into orc_id;

    insert into public.orcamentos_santri_itens as t (orcamento_id, ordem, produto_id, codigo, descricao, marca, promocao, quantidade,
      preco_unitario, total_bruto, total_liquido, custo, custo_compra, ativo)
    select orc_id, (i->>'ordem')::int,
      (select p.id from public.produtos p where (i->>'codigo') ~ '^\d+$' and p.id = (i->>'codigo')::bigint),
      i->>'codigo', i->>'descricao', i->>'marca', (i->>'promocao')::boolean, (i->>'quantidade')::numeric, (i->>'preco_unitario')::numeric,
      (i->>'total_bruto')::numeric, (i->>'total_liquido')::numeric, (i->>'custo')::numeric, (i->>'custo_compra')::numeric, true
    from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i
    on conflict (orcamento_id, ordem) do update set
      produto_id = excluded.produto_id, codigo = excluded.codigo, descricao = excluded.descricao, marca = excluded.marca,
      promocao = excluded.promocao, quantidade = excluded.quantidade, preco_unitario = excluded.preco_unitario,
      total_bruto = excluded.total_bruto, total_liquido = excluded.total_liquido, custo = excluded.custo,
      custo_compra = excluded.custo_compra, ativo = true;
    update public.orcamentos_santri_itens set ativo = false
     where orcamento_id = orc_id and ativo and ordem > jsonb_array_length(coalesce(d->'itens','[]'::jsonb));

    if old.id is null then
      insert into public.orcamentos_santri_eventos (orcamento_id, importacao_id, campo, de, para) values (orc_id, p_importacao, 'status', null, d->>'status');
    else
      insert into public.orcamentos_santri_eventos (orcamento_id, importacao_id, campo, de, para)
      select orc_id, p_importacao, x.campo, x.de, x.para from (values
        ('status', old.status, d->>'status'),
        ('vlr_liquido', old.vlr_liquido::text, (d->>'vlr_liquido')::numeric::text),
        ('vendedor', old.vendedor_santri, d->>'vendedor')
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;
  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;

update public.relatorios_rotina set
  tipos_importacao = array['orcamentos_abertos','orcamentos_cancelados'],
  menu_santri = 'Santri Relatórios → Vendas → Vendas e devoluções (Analítico, com itens) — o mesmo das vendas, exportado duas vezes',
  filtros = 'Empresa da venda: as duas lojas · Status: Orçamento (1º arquivo) e depois Cancelado (2º arquivo) · Tipo de custo: Custo comercial · Trazer itens: marcado · Período pela Data de cadastro do orçamento (desde 01/01/2026)',
  dicas = 'Importe os dois arquivos: o dos abertos (Orçamento) e o dos cancelados. O sistema reconhece qual é qual pelos filtros do rodapé. Orçamento que virou pedido é ligado sozinho pelo número.'
where tipo = 'orcamentos';
