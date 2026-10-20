-- Migration 31 · Baixas de contas a receber e a pagar do Santri (Relação de Baixas – Analítico)
-- Mesmo layout nos dois lados: baixa + formas de pagamento + títulos baixados. lado = receber | pagar.
-- Receber: o Documento do título traz o nº do pedido (13152/1-3, CAR…-ORC13152/1-2) → "cliente pagou".
-- Reimportar não duplica (assinatura); baixa que sumiu do Santri dentro do período do arquivo fica ativo = false (estornada).

create or replace function interno.pode_ver_financeiro() returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce((select ativo and papel in ('admin','direcao','financeiro') from public.usuarios where id = (select auth.uid())), false)
$$;

create table if not exists public.baixas_santri (
  id bigserial primary key,
  lado text not null check (lado in ('receber','pagar')),
  loja_id smallint not null references public.lojas(id),
  baixa text not null,
  data_baixa date, tipo_baixa text,
  cadastro_codigo text, cadastro_nome text,
  data_recebimento date, complemento text, data_media date, usuario text,
  valor_formas numeric, valor_titulos numeric,
  ativo boolean not null default true,
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (lado, loja_id, baixa)
);
create index if not exists baixas_santri_data_idx on public.baixas_santri (lado, loja_id, data_baixa);

create table if not exists public.baixas_santri_formas (
  baixa_id bigint not null references public.baixas_santri(id),
  ordem int not null,
  forma text, conta text, valor numeric, data_recebimento date, conciliado boolean,
  ativo boolean not null default true,
  primary key (baixa_id, ordem)
);

create table if not exists public.baixas_santri_titulos (
  baixa_id bigint not null references public.baixas_santri(id),
  ordem int not null,
  cod_financeiro text, nome text, doc text, tipo text, vencimento date, nr_nota text,
  valor_documento numeric, juros numeric, multa numeric, desconto numeric, valor_adiantado numeric, valor_baixado numeric,
  emissao date, documento text, pedido_numero text, portador text,
  ativo boolean not null default true,
  primary key (baixa_id, ordem)
);
create index if not exists baixas_santri_titulos_ped_idx on public.baixas_santri_titulos (pedido_numero) where pedido_numero is not null;

create table if not exists public.baixas_santri_eventos (
  id bigserial primary key,
  baixa_id bigint not null references public.baixas_santri(id),
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null, de text, para text
);

create table if not exists public.baixas_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.baixas_santri enable row level security;
alter table public.baixas_santri_formas enable row level security;
alter table public.baixas_santri_titulos enable row level security;
alter table public.baixas_santri_eventos enable row level security;
alter table public.baixas_staging enable row level security;

create policy bx_ler on public.baixas_santri for select to authenticated
  using ((case when lado = 'receber' then (select interno.pode_ver_compras()) else (select interno.pode_ver_financeiro()) end)
         and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy bxf_ler on public.baixas_santri_formas for select to authenticated
  using (exists (select 1 from public.baixas_santri b where b.id = baixas_santri_formas.baixa_id));
create policy bxt_ler on public.baixas_santri_titulos for select to authenticated
  using (exists (select 1 from public.baixas_santri b where b.id = baixas_santri_titulos.baixa_id));
create policy bxe_ler on public.baixas_santri_eventos for select to authenticated
  using (exists (select 1 from public.baixas_santri b where b.id = baixas_santri_eventos.baixa_id));
create policy bxstg_dono on public.baixas_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = baixas_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = baixas_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

create or replace function interno.assinatura_baixa(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'data_baixa', d->'tipo_baixa', d->'cadastro_codigo', d->'data_recebimento', d->'complemento',
    (select coalesce(jsonb_agg(jsonb_build_array(f->'forma', f->'valor', f->'data_recebimento', f->'conciliado') order by (f->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'formas','[]'::jsonb)) f),
    (select coalesce(jsonb_agg(jsonb_build_array(t->'cod_financeiro', t->'valor_baixado', t->'documento') order by (t->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'titulos','[]'::jsonb)) t))::text)
$$;

-- tipo da importação → precisa ter permissão para ele (receber_baixas é do financeiro; pagar_baixas também)
create or replace function public.previa_importacao_baixas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb; t text;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('receber_baixas','pagar_baixas') or not interno.pode_importar(t) then raise exception 'Sem permissão para importar baixas'; end if;
  with s as (
    select d->>'lado' lado, (d->>'loja_id')::smallint loja_id, d->>'baixa' baixa, (d->>'data_baixa')::date db, d->>'tipo_baixa' tipo,
           (select coalesce(sum((f->>'valor')::numeric),0) from jsonb_array_elements(coalesce(d->'formas','[]'::jsonb)) f) vf,
           (select coalesce(sum((x->>'valor_baixado')::numeric),0) from jsonb_array_elements(coalesce(d->'titulos','[]'::jsonb)) x) vt,
           jsonb_array_length(coalesce(d->'titulos','[]'::jsonb)) nt, interno.assinatura_baixa(d) sig, d
    from (select dados d from public.baixas_staging where importacao_id = p_importacao) z),
  j as (select s.*, b.id bid, b.assinatura bsig from s left join public.baixas_santri b on b.lado = s.lado and b.loja_id = s.loja_id and b.baixa = s.baixa),
  tit as (select s.loja_id, x->>'pedido_numero' ped from s, jsonb_array_elements(coalesce(s.d->'titulos','[]'::jsonb)) x),
  per as (select lado, loja_id, min(db) de, max(db) ate from s group by 1,2)
  select jsonb_build_object(
    'lado', (select min(lado) from s),
    'no_arquivo', (select count(*) from s),
    'titulos', (select coalesce(sum(nt),0) from s),
    'valor_formas', (select coalesce(sum(vf),0) from s),
    'valor_titulos', (select coalesce(sum(vt),0) from s),
    'credito_gerado', (select coalesce(sum(vf),0) from s where tipo ilike 'cr%dito gerado'),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(db) from s), 'ate', (select max(db) from s),
    'por_tipo', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (select coalesce(tipo,'?') tipo, count(*) n from s group by 1) x),
    'com_pedido', (select count(*) from tit where ped is not null),
    'pedidos', (select count(distinct (loja_id, ped)) from tit where ped is not null),
    'pedidos_no_sistema', (select count(distinct (tit.loja_id, tit.ped)) from tit where ped is not null and exists
        (select 1 from public.vendas_santri v where v.tipo = 'PED' and v.numero = tit.ped)),
    'novos', (select count(*) from j where bid is null),
    'alterados', (select count(*) from j where bid is not null and bsig is distinct from sig),
    'iguais', (select count(*) from j where bid is not null and bsig = sig),
    'sumiram', (select count(*) from public.baixas_santri b join per on per.lado = b.lado and per.loja_id = b.loja_id
        where b.ativo and b.data_baixa between per.de and per.ate
          and not exists (select 1 from s where s.lado = b.lado and s.loja_id = b.loja_id and s.baixa = b.baixa))
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_baixas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
#variable_conflict use_column
declare res jsonb; d jsonb; bid bigint; sig text; old public.baixas_santri%rowtype; t text;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0; n_sum int := 0;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('receber_baixas','pagar_baixas') or not interno.pode_importar(t) then raise exception 'Sem permissão para importar baixas'; end if;
  res := public.previa_importacao_baixas(p_importacao);
  for d in select dados from public.baixas_staging where importacao_id = p_importacao order by id loop
    sig := interno.assinatura_baixa(d); old := null;
    select * into old from public.baixas_santri where lado = d->>'lado' and loja_id = (d->>'loja_id')::smallint and baixa = d->>'baixa';
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig or not old.ativo then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.baixas_santri as b (lado, loja_id, baixa, data_baixa, tipo_baixa, cadastro_codigo, cadastro_nome, data_recebimento,
      complemento, data_media, usuario, valor_formas, valor_titulos, ativo, assinatura, importacao_id, primeira_importacao_id)
    values (d->>'lado', (d->>'loja_id')::smallint, d->>'baixa', (d->>'data_baixa')::date, d->>'tipo_baixa', d->>'cadastro_codigo', d->>'cadastro_nome',
      (d->>'data_recebimento')::date, d->>'complemento', (d->>'data_media')::date, d->>'usuario',
      (select sum((f->>'valor')::numeric) from jsonb_array_elements(coalesce(d->'formas','[]'::jsonb)) f),
      (select sum((x->>'valor_baixado')::numeric) from jsonb_array_elements(coalesce(d->'titulos','[]'::jsonb)) x),
      true, sig, p_importacao, p_importacao)
    on conflict (lado, loja_id, baixa) do update set
      data_baixa = excluded.data_baixa, tipo_baixa = excluded.tipo_baixa, cadastro_codigo = excluded.cadastro_codigo,
      cadastro_nome = excluded.cadastro_nome, data_recebimento = excluded.data_recebimento, complemento = excluded.complemento,
      data_media = excluded.data_media, usuario = excluded.usuario, valor_formas = excluded.valor_formas, valor_titulos = excluded.valor_titulos,
      ativo = true, assinatura = excluded.assinatura, importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into bid;

    insert into public.baixas_santri_formas as f (baixa_id, ordem, forma, conta, valor, data_recebimento, conciliado, ativo)
    select bid, (x->>'ordem')::int, x->>'forma', x->>'conta', (x->>'valor')::numeric, (x->>'data_recebimento')::date, (x->>'conciliado')::boolean, true
    from jsonb_array_elements(coalesce(d->'formas','[]'::jsonb)) x
    on conflict (baixa_id, ordem) do update set forma = excluded.forma, conta = excluded.conta, valor = excluded.valor,
      data_recebimento = excluded.data_recebimento, conciliado = excluded.conciliado, ativo = true;
    update public.baixas_santri_formas set ativo = false where baixa_id = bid and ativo and ordem > jsonb_array_length(coalesce(d->'formas','[]'::jsonb));

    insert into public.baixas_santri_titulos as tt (baixa_id, ordem, cod_financeiro, nome, doc, tipo, vencimento, nr_nota, valor_documento, juros, multa,
      desconto, valor_adiantado, valor_baixado, emissao, documento, pedido_numero, portador, ativo)
    select bid, (x->>'ordem')::int, x->>'cod_financeiro', x->>'nome', x->>'doc', x->>'tipo', (x->>'vencimento')::date, x->>'nr_nota',
      (x->>'valor_documento')::numeric, (x->>'juros')::numeric, (x->>'multa')::numeric, (x->>'desconto')::numeric, (x->>'valor_adiantado')::numeric,
      (x->>'valor_baixado')::numeric, (x->>'emissao')::date, x->>'documento', nullif(x->>'pedido_numero',''), x->>'portador', true
    from jsonb_array_elements(coalesce(d->'titulos','[]'::jsonb)) x
    on conflict (baixa_id, ordem) do update set cod_financeiro = excluded.cod_financeiro, nome = excluded.nome, doc = excluded.doc,
      tipo = excluded.tipo, vencimento = excluded.vencimento, nr_nota = excluded.nr_nota, valor_documento = excluded.valor_documento,
      juros = excluded.juros, multa = excluded.multa, desconto = excluded.desconto, valor_adiantado = excluded.valor_adiantado,
      valor_baixado = excluded.valor_baixado, emissao = excluded.emissao, documento = excluded.documento,
      pedido_numero = excluded.pedido_numero, portador = excluded.portador, ativo = true;
    update public.baixas_santri_titulos set ativo = false where baixa_id = bid and ativo and ordem > jsonb_array_length(coalesce(d->'titulos','[]'::jsonb));

    if old.id is null then
      insert into public.baixas_santri_eventos (baixa_id, importacao_id, campo, de, para) values (bid, p_importacao, 'nova', null, d->>'data_baixa');
    else
      insert into public.baixas_santri_eventos (baixa_id, importacao_id, campo, de, para)
      select bid, p_importacao, x.campo, x.de, x.para from (values
        ('ativo', old.ativo::text, 'true'),
        ('valor_formas', old.valor_formas::text, (select sum((f->>'valor')::numeric) from jsonb_array_elements(coalesce(d->'formas','[]'::jsonb)) f)::text),
        ('data_baixa', old.data_baixa::text, d->>'data_baixa')
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;

  -- baixas que estavam no sistema, dentro do período e das lojas do arquivo, e não vieram: estornadas no Santri
  with s as (select d->>'lado' lado, (d->>'loja_id')::smallint loja_id, d->>'baixa' baixa, (d->>'data_baixa')::date db
             from (select dados d from public.baixas_staging where importacao_id = p_importacao) z),
       per as (select lado, loja_id, min(db) de, max(db) ate from s group by 1,2),
       sai as (update public.baixas_santri b set ativo = false, atualizado_em = now() from per
               where per.lado = b.lado and per.loja_id = b.loja_id and b.ativo and b.data_baixa between per.de and per.ate
                 and not exists (select 1 from s where s.lado = b.lado and s.loja_id = b.loja_id and s.baixa = b.baixa)
               returning b.id)
  insert into public.baixas_santri_eventos (baixa_id, importacao_id, campo, de, para)
  select id, p_importacao, 'ativo', 'true', 'false' from sai;
  get diagnostics n_sum = row_count;

  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais, 'inativados', n_sum);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;
