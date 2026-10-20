-- Migration 28c · Entradas do Santri (Relação de Entradas – Analítico): notas de entrada, itens, compras ligadas, histórico

create table if not exists public.entradas_santri (
  id bigserial primary key,
  loja_id smallint not null references public.lojas(id),
  entrada text not null,                 -- nº da entrada no Santri
  fornecedor_codigo text, fornecedor_nome text,
  nr_nota text, serie text, chave_nfe text,
  data_emissao date, data_cadastro date, data_entrada date, data_vencimento1 date,
  tipo_custo text, status text, cfop text,
  tipo text,                              -- revenda | uso_consumo | amostra_bonificacao | outras (pelo CFOP)
  valor_nota numeric, valor_produtos numeric, valor_desconto numeric, total_frete_nf numeric, outras_desp numeric,
  peso_total numeric, qtd_itens numeric, prazo_medio numeric,
  total_ipi numeric, base_icms numeric, total_icms numeric, base_st numeric, total_st numeric, dare_guia numeric,
  frete_conhec numeric,
  cte_numero text, cte_chave text, transportadora_codigo text, transportadora_nome text,
  cte_emissao date, cte_entrada date, cte_valor numeric,
  observacao text,
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (loja_id, entrada)
);
create index if not exists entradas_santri_datas_idx on public.entradas_santri (loja_id, status, data_cadastro);

create table if not exists public.entradas_santri_itens (
  entrada_id bigint not null references public.entradas_santri(id),
  ordem int not null,
  produto_id bigint, codigo text, nome text, cod_original text,
  quantidade numeric, preco numeric, total numeric, pct_icms numeric, pct_ipi numeric, total_com_ipi numeric,
  cfop text, lote text, qtd_lote numeric,
  ativo boolean not null default true,
  primary key (entrada_id, ordem)
);
create index if not exists entradas_santri_itens_prod_idx on public.entradas_santri_itens (produto_id);

create table if not exists public.entradas_santri_compras (
  entrada_id bigint not null references public.entradas_santri(id),
  compra_numero text not null,
  data_compra date,
  ativo boolean not null default true,
  primary key (entrada_id, compra_numero)
);
create index if not exists entradas_santri_compras_num_idx on public.entradas_santri_compras (compra_numero);

create table if not exists public.entradas_santri_eventos (
  id bigserial primary key,
  entrada_id bigint not null references public.entradas_santri(id),
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null, de text, para text
);
create index if not exists entradas_santri_eventos_idx on public.entradas_santri_eventos (entrada_id, em);

create table if not exists public.entradas_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.entradas_santri enable row level security;
alter table public.entradas_santri_itens enable row level security;
alter table public.entradas_santri_compras enable row level security;
alter table public.entradas_santri_eventos enable row level security;
alter table public.entradas_staging enable row level security;

create policy es_ler on public.entradas_santri for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy esi_ler on public.entradas_santri_itens for select to authenticated
  using (exists (select 1 from public.entradas_santri e where e.id = entradas_santri_itens.entrada_id));
create policy esc_ler on public.entradas_santri_compras for select to authenticated
  using (exists (select 1 from public.entradas_santri e where e.id = entradas_santri_compras.entrada_id));
create policy ese_ler on public.entradas_santri_eventos for select to authenticated
  using (exists (select 1 from public.entradas_santri e where e.id = entradas_santri_eventos.entrada_id));
create policy estg_dono on public.entradas_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = entradas_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = entradas_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

-- tipo da nota pelo CFOP
create or replace function interno.tipo_entrada(p_cfop text) returns text
language sql immutable set search_path to '' as $$
  select case
    when p_cfop ~ '^\d\.(102|403|405)' then 'revenda'
    when p_cfop ~ '^\d\.(556|407|551|406)' then 'uso_consumo'
    when p_cfop ~ '^\d\.(910|911)' then 'amostra_bonificacao'
    else 'outras' end
$$;

create or replace function interno.assinatura_entrada(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'status', d->'data_entrada', d->'valor_nota', d->'frete_conhec', d->'cte_numero', d->'cte_entrada',
    d->'peso_total', d->'observacao', d->'fornecedor_codigo', d->'cfop', d->'total_st', d->'dare_guia',
    (select coalesce(jsonb_agg(jsonb_build_array(i->'codigo', i->'quantidade', i->'preco', i->'total', i->'pct_ipi', i->'lote') order by (i->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i),
    (select coalesce(jsonb_agg(c->'numero' order by c->>'numero'), '[]'::jsonb) from jsonb_array_elements(coalesce(d->'compras','[]'::jsonb)) c))::text)
$$;

create or replace function public.previa_importacao_entradas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.pode_importar('entradas') then raise exception 'Sem permissão para importar entradas'; end if;
  with s as (
    select (d->>'loja_id')::smallint loja_id, d->>'entrada' entrada, d->>'status' status, interno.tipo_entrada(d->>'cfop') tipo,
           (d->>'data_cadastro')::date dc, coalesce((d->>'valor_nota')::numeric,0) vn, coalesce((d->>'frete_conhec')::numeric,0) fr,
           jsonb_array_length(coalesce(d->'compras','[]'::jsonb)) ncompras, jsonb_array_length(coalesce(d->'itens','[]'::jsonb)) nitens,
           nullif(d->>'cte_numero','') cte, interno.assinatura_entrada(d) sig, d
    from (select dados d from public.entradas_staging where importacao_id = p_importacao) z),
  j as (select s.*, e.id eid, e.assinatura esig, e.status estatus from s
        left join public.entradas_santri e on e.loja_id = s.loja_id and e.entrada = s.entrada),
  cmp as (select s.loja_id, c->>'numero' numero from s, jsonb_array_elements(coalesce(s.d->'compras','[]'::jsonb)) c)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'itens', (select coalesce(sum(nitens),0) from s),
    'valor_notas', (select coalesce(sum(vn),0) from s),
    'frete_cte', (select coalesce(sum(fr),0) from s),
    'revenda', (select count(*) from s where tipo = 'revenda'),
    'uso_consumo', (select count(*) from s where tipo = 'uso_consumo'),
    'amostra_bonificacao', (select count(*) from s where tipo = 'amostra_bonificacao'),
    'outras', (select count(*) from s where tipo = 'outras'),
    'abertas', (select count(*) from s where status = 'Aberta'),
    'baixadas', (select count(*) from s where status = 'Baixada'),
    'revenda_sem_compra', (select count(*) from s where tipo = 'revenda' and nitens > 0 and ncompras = 0),
    'revenda_sem_compra_valor', (select coalesce(sum(vn),0) from s where tipo = 'revenda' and nitens > 0 and ncompras = 0),
    'compras_ligadas', (select count(distinct (loja_id, numero)) from cmp),
    'compras_fora_do_sistema', (select count(distinct (cmp.loja_id, cmp.numero)) from cmp where not exists
        (select 1 from public.compras_santri c where c.loja_id = cmp.loja_id and c.numero = cmp.numero)),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(dc) from s), 'ate', (select max(dc) from s),
    'novos', (select count(*) from j where eid is null),
    'alterados', (select count(*) from j where eid is not null and esig is distinct from sig),
    'iguais', (select count(*) from j where eid is not null and esig = sig),
    'baixadas_agora', (select count(*) from j where eid is not null and estatus is distinct from status and status = 'Baixada')
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_entradas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; d jsonb; eid bigint; sig text; old public.entradas_santri%rowtype;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0;
begin
  if not interno.pode_importar('entradas') then raise exception 'Sem permissão para importar entradas'; end if;
  res := public.previa_importacao_entradas(p_importacao);
  for d in select dados from public.entradas_staging where importacao_id = p_importacao order by id loop
    sig := interno.assinatura_entrada(d); old := null;
    select * into old from public.entradas_santri where loja_id = (d->>'loja_id')::smallint and entrada = d->>'entrada';
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.entradas_santri as e (loja_id, entrada, fornecedor_codigo, fornecedor_nome, nr_nota, serie, chave_nfe,
      data_emissao, data_cadastro, data_entrada, data_vencimento1, tipo_custo, status, cfop, tipo,
      valor_nota, valor_produtos, valor_desconto, total_frete_nf, outras_desp, peso_total, qtd_itens, prazo_medio,
      total_ipi, base_icms, total_icms, base_st, total_st, dare_guia, frete_conhec,
      cte_numero, cte_chave, transportadora_codigo, transportadora_nome, cte_emissao, cte_entrada, cte_valor,
      observacao, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'entrada', d->>'fornecedor_codigo', d->>'fornecedor_nome', d->>'nr_nota', d->>'serie',
      nullif(d->>'chave_nfe',''), (d->>'data_emissao')::date, (d->>'data_cadastro')::date, (d->>'data_entrada')::date,
      (d->>'data_vencimento1')::date, d->>'tipo_custo', d->>'status', d->>'cfop', interno.tipo_entrada(d->>'cfop'),
      (d->>'valor_nota')::numeric, (d->>'valor_produtos')::numeric, (d->>'valor_desconto')::numeric, (d->>'total_frete_nf')::numeric,
      (d->>'outras_desp')::numeric, (d->>'peso_total')::numeric, (d->>'qtd_itens')::numeric, (d->>'prazo_medio')::numeric,
      (d->>'total_ipi')::numeric, (d->>'base_icms')::numeric, (d->>'total_icms')::numeric, (d->>'base_st')::numeric,
      (d->>'total_st')::numeric, (d->>'dare_guia')::numeric, (d->>'frete_conhec')::numeric,
      nullif(d->>'cte_numero',''), nullif(d->>'cte_chave',''), nullif(d->>'transportadora_codigo',''), nullif(d->>'transportadora_nome',''),
      (d->>'cte_emissao')::date, (d->>'cte_entrada')::date, (d->>'cte_valor')::numeric,
      nullif(d->>'observacao',''), sig, p_importacao, p_importacao)
    on conflict (loja_id, entrada) do update set
      fornecedor_codigo = excluded.fornecedor_codigo, fornecedor_nome = excluded.fornecedor_nome, nr_nota = excluded.nr_nota,
      serie = excluded.serie, chave_nfe = excluded.chave_nfe, data_emissao = excluded.data_emissao,
      data_cadastro = excluded.data_cadastro, data_entrada = excluded.data_entrada, data_vencimento1 = excluded.data_vencimento1,
      tipo_custo = excluded.tipo_custo, status = excluded.status, cfop = excluded.cfop, tipo = excluded.tipo,
      valor_nota = excluded.valor_nota, valor_produtos = excluded.valor_produtos, valor_desconto = excluded.valor_desconto,
      total_frete_nf = excluded.total_frete_nf, outras_desp = excluded.outras_desp, peso_total = excluded.peso_total,
      qtd_itens = excluded.qtd_itens, prazo_medio = excluded.prazo_medio, total_ipi = excluded.total_ipi,
      base_icms = excluded.base_icms, total_icms = excluded.total_icms, base_st = excluded.base_st, total_st = excluded.total_st,
      dare_guia = excluded.dare_guia, frete_conhec = excluded.frete_conhec, cte_numero = excluded.cte_numero,
      cte_chave = excluded.cte_chave, transportadora_codigo = excluded.transportadora_codigo,
      transportadora_nome = excluded.transportadora_nome, cte_emissao = excluded.cte_emissao, cte_entrada = excluded.cte_entrada,
      cte_valor = excluded.cte_valor, observacao = excluded.observacao, assinatura = excluded.assinatura,
      importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into eid;

    insert into public.entradas_santri_itens as t (entrada_id, ordem, produto_id, codigo, nome, cod_original, quantidade, preco,
      total, pct_icms, pct_ipi, total_com_ipi, cfop, lote, qtd_lote, ativo)
    select eid, (i->>'ordem')::int,
      (select p.id from public.produtos p where (i->>'codigo') ~ '^\d+$' and p.id = (i->>'codigo')::bigint),
      i->>'codigo', i->>'nome', i->>'cod_original', (i->>'quantidade')::numeric, (i->>'preco')::numeric, (i->>'total')::numeric,
      (i->>'pct_icms')::numeric, (i->>'pct_ipi')::numeric,
      round((i->>'total')::numeric * (1 + coalesce((i->>'pct_ipi')::numeric,0)/100), 2),
      i->>'cfop', nullif(i->>'lote',''), (i->>'qtd_lote')::numeric, true
    from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i
    on conflict (entrada_id, ordem) do update set
      produto_id = excluded.produto_id, codigo = excluded.codigo, nome = excluded.nome, cod_original = excluded.cod_original,
      quantidade = excluded.quantidade, preco = excluded.preco, total = excluded.total, pct_icms = excluded.pct_icms,
      pct_ipi = excluded.pct_ipi, total_com_ipi = excluded.total_com_ipi, cfop = excluded.cfop, lote = excluded.lote,
      qtd_lote = excluded.qtd_lote, ativo = true;
    update public.entradas_santri_itens set ativo = false
     where entrada_id = eid and ativo and ordem > jsonb_array_length(coalesce(d->'itens','[]'::jsonb));

    insert into public.entradas_santri_compras as c (entrada_id, compra_numero, data_compra, ativo)
    select eid, x->>'numero', (x->>'data')::date, true
    from jsonb_array_elements(coalesce(d->'compras','[]'::jsonb)) x where coalesce(x->>'numero','') <> ''
    on conflict (entrada_id, compra_numero) do update set data_compra = excluded.data_compra, ativo = true;
    update public.entradas_santri_compras set ativo = false
     where entrada_id = eid and ativo and compra_numero not in
       (select x->>'numero' from jsonb_array_elements(coalesce(d->'compras','[]'::jsonb)) x where coalesce(x->>'numero','') <> '');

    if old.id is null then
      insert into public.entradas_santri_eventos (entrada_id, importacao_id, campo, de, para)
      values (eid, p_importacao, 'status', null, d->>'status');
    else
      insert into public.entradas_santri_eventos (entrada_id, importacao_id, campo, de, para)
      select eid, p_importacao, x.campo, x.de, x.para from (values
        ('status', old.status, d->>'status'),
        ('data_entrada', old.data_entrada::text, d->>'data_entrada'),
        ('cte_numero', old.cte_numero, nullif(d->>'cte_numero','')),
        ('valor_nota', old.valor_nota::text, (d->>'valor_nota')::numeric::text),
        ('frete_conhec', old.frete_conhec::text, (d->>'frete_conhec')::numeric::text)
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;
  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;
