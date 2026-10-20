-- Migration 34 · Contas a pagar e a receber do Santri (Relação de Contas a Pagar / a Receber – Analítico) — foto do dia
-- Um título por lado + Código do Santri. Cada importação marca ultima_importacao_id; a foto atual = títulos da última importação do lado.
-- Histórico: situação, saldo, vencimento e data de pagamento que mudaram entre importações.
-- Pagar: Tipo "Pre" = pagamento antecipado (Dexco) que nunca baixa; "Cre" = crédito (devolução, sobra, transferência entre lojas).

create table if not exists public.titulos_santri (
  id bigserial primary key,
  lado text not null check (lado in ('receber','pagar')),
  loja_id smallint not null references public.lojas(id),
  codigo text not null,
  cadastro_codigo text, nome text, doc text,
  situacao text, documento text, nr_nota text,
  vencimento date, pagamento date, emissao date,
  valor_documento numeric, valor_adiantado numeric, saldo numeric, valor_liquido numeric, juros numeric, multa numeric, desconto numeric,
  tipo text, portador text, plano_codigo text, plano_nome text, centro_custos text, observacao text,
  cidade text, telefone text, usuario text, pedido_numero text,
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  ultima_importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (lado, codigo)
);
create index if not exists titulos_santri_ult_idx on public.titulos_santri (lado, ultima_importacao_id);
create index if not exists titulos_santri_ped_idx on public.titulos_santri (pedido_numero) where pedido_numero is not null;

create table if not exists public.titulos_santri_eventos (
  id bigserial primary key,
  titulo_id bigint not null references public.titulos_santri(id),
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null, de text, para text
);

create table if not exists public.titulos_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.titulos_santri enable row level security;
alter table public.titulos_santri_eventos enable row level security;
alter table public.titulos_staging enable row level security;

create policy ti_ler on public.titulos_santri for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy tie_ler on public.titulos_santri_eventos for select to authenticated
  using (exists (select 1 from public.titulos_santri t where t.id = titulos_santri_eventos.titulo_id));
create policy tistg_dono on public.titulos_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = titulos_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = titulos_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

create or replace function interno.titulos_ultima_importacao(p_lado text) returns bigint
language sql stable security definer set search_path to '' as $$
  select i.id from public.importacoes i where i.status = 'aplicada' and i.tipo = p_lado order by i.criado_em desc limit 1
$$;

create or replace function interno.assinatura_titulo(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'situacao', d->'saldo', d->'vencimento', d->'pagamento', d->'valor_documento', d->'valor_adiantado',
    d->'tipo', d->'plano_codigo', d->'documento', d->'nr_nota', d->'portador', d->'observacao', d->'juros', d->'desconto')::text)
$$;

create or replace function public.previa_importacao_titulos(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb; t text;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('pagar','receber') or not interno.pode_importar(t) then raise exception 'Sem permissão para importar contas a pagar/receber'; end if;
  with s as (
    select d->>'lado' lado, (d->>'loja_id')::smallint loja_id, d->>'codigo' codigo, d->>'situacao' sit, d->>'tipo' tipo,
           coalesce((d->>'saldo')::numeric,0) saldo, (d->>'vencimento')::date venc, d->>'plano_nome' plano, interno.assinatura_titulo(d) sig
    from (select dados d from public.titulos_staging where importacao_id = p_importacao) z),
  j as (select s.*, x.id tid, x.assinatura tsig, x.situacao tsit from s left join public.titulos_santri x on x.lado = s.lado and x.codigo = s.codigo)
  select jsonb_build_object(
    'lado', t,
    'no_arquivo', (select count(*) from s),
    'abertos', (select count(*) from s where sit = 'Aberto'),
    'saldo', (select coalesce(sum(saldo),0) from s),
    'saldo_vencido', (select coalesce(sum(saldo),0) from s where sit = 'Aberto' and venc < current_date),
    'saldo_antecipado', (select coalesce(sum(saldo),0) from s where sit = 'Aberto' and tipo = 'Pre'),
    'saldo_credito', (select coalesce(sum(saldo),0) from s where sit = 'Aberto' and tipo in ('Cre','Crédito')),
    'sem_plano', (select count(*) from s where coalesce(plano,'SEM PLANO') = 'SEM PLANO'),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'venc_de', (select min(venc) from s), 'venc_ate', (select max(venc) from s),
    'novos', (select count(*) from j where tid is null),
    'alterados', (select count(*) from j where tid is not null and tsig is distinct from sig),
    'iguais', (select count(*) from j where tid is not null and tsig = sig),
    'baixados_agora', (select count(*) from j where tid is not null and tsit = 'Aberto' and sit = 'Baixado'),
    'sumiram', (select count(*) from public.titulos_santri x where x.lado = t and x.ultima_importacao_id = interno.titulos_ultima_importacao(t)
                and not exists (select 1 from s where s.codigo = x.codigo))
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_titulos(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; t text; n_novos int; n_alt int; n_iguais int;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('pagar','receber') or not interno.pode_importar(t) then raise exception 'Sem permissão para importar contas a pagar/receber'; end if;
  res := public.previa_importacao_titulos(p_importacao);
  n_novos := (res->>'novos')::int; n_alt := (res->>'alterados')::int; n_iguais := (res->>'iguais')::int;

  with tmp_tit as (select distinct on (d->>'codigo') d->>'codigo' codigo, d, interno.assinatura_titulo(d) sig
    from (select dados d from public.titulos_staging where importacao_id = p_importacao) z order by d->>'codigo')
  insert into public.titulos_santri_eventos (titulo_id, importacao_id, campo, de, para)
  select x.id, p_importacao, v.campo, v.de, v.para
  from tmp_tit s join public.titulos_santri x on x.lado = t and x.codigo = s.codigo and x.assinatura is distinct from s.sig
  cross join lateral (values
    ('situacao', x.situacao, s.d->>'situacao'),
    ('saldo', x.saldo::text, (s.d->>'saldo')::numeric::text),
    ('vencimento', x.vencimento::text, s.d->>'vencimento'),
    ('pagamento', x.pagamento::text, s.d->>'pagamento')) v(campo, de, para)
  where v.de is distinct from v.para;

  with tmp_tit as (select distinct on (d->>'codigo') d->>'codigo' codigo, d, interno.assinatura_titulo(d) sig
    from (select dados d from public.titulos_staging where importacao_id = p_importacao) z order by d->>'codigo')
  insert into public.titulos_santri as x (lado, loja_id, codigo, cadastro_codigo, nome, doc, situacao, documento, nr_nota, vencimento, pagamento,
    emissao, valor_documento, valor_adiantado, saldo, valor_liquido, juros, multa, desconto, tipo, portador, plano_codigo, plano_nome,
    centro_custos, observacao, cidade, telefone, usuario, pedido_numero, assinatura, importacao_id, ultima_importacao_id, primeira_importacao_id)
  select t, (d->>'loja_id')::smallint, codigo, d->>'cadastro_codigo', d->>'nome', d->>'doc', d->>'situacao', d->>'documento', d->>'nr_nota',
    (d->>'vencimento')::date, (d->>'pagamento')::date, (d->>'emissao')::date, (d->>'valor_documento')::numeric, (d->>'valor_adiantado')::numeric,
    coalesce((d->>'saldo')::numeric,0), (d->>'valor_liquido')::numeric, (d->>'juros')::numeric, (d->>'multa')::numeric, (d->>'desconto')::numeric,
    d->>'tipo', d->>'portador', d->>'plano_codigo', d->>'plano_nome', d->>'centro_custos', d->>'observacao', d->>'cidade', d->>'telefone',
    d->>'usuario', nullif(d->>'pedido_numero',''), sig, p_importacao, p_importacao, p_importacao
  from tmp_tit
  on conflict (lado, codigo) do update set
    loja_id = excluded.loja_id, cadastro_codigo = excluded.cadastro_codigo, nome = excluded.nome, doc = excluded.doc,
    situacao = excluded.situacao, documento = excluded.documento, nr_nota = excluded.nr_nota, vencimento = excluded.vencimento,
    pagamento = excluded.pagamento, emissao = excluded.emissao, valor_documento = excluded.valor_documento,
    valor_adiantado = excluded.valor_adiantado, saldo = excluded.saldo, valor_liquido = excluded.valor_liquido, juros = excluded.juros,
    multa = excluded.multa, desconto = excluded.desconto, tipo = excluded.tipo, portador = excluded.portador,
    plano_codigo = excluded.plano_codigo, plano_nome = excluded.plano_nome, centro_custos = excluded.centro_custos,
    observacao = excluded.observacao, cidade = excluded.cidade, telefone = excluded.telefone, usuario = excluded.usuario,
    pedido_numero = excluded.pedido_numero, ultima_importacao_id = excluded.ultima_importacao_id,
    assinatura = excluded.assinatura,
    importacao_id = case when x.assinatura is distinct from excluded.assinatura then excluded.importacao_id else x.importacao_id end,
    atualizado_em = case when x.assinatura is distinct from excluded.assinatura then now() else x.atualizado_em end;

  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;
