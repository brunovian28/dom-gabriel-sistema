-- Migration 33 · Estoque por local do Santri (Relação de Estoque por Local, custo da última entrada) — foto por dia e loja
-- Cada importação grava uma foto (uma linha por produto e local com quantidade). Vale a última importação do dia de cada loja.
-- Um arquivo por loja (PVA_ / RV_ no nome); tipo da importação estoque_PVA / estoque_RV.

create table if not exists public.estoque_foto (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  loja_id smallint not null references public.lojas(id),
  data_foto date not null,
  produto_id bigint, codigo text, nome text, marca text, cod_original text, unidade text,
  custo numeric, local text, quantidade numeric, valor numeric
);
create index if not exists estoque_foto_imp_idx on public.estoque_foto (importacao_id);
create index if not exists estoque_foto_loja_idx on public.estoque_foto (loja_id, data_foto);

create table if not exists public.estoque_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.estoque_foto enable row level security;
alter table public.estoque_staging enable row level security;

create policy ef_ler on public.estoque_foto for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy efstg_dono on public.estoque_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = estoque_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = estoque_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

-- última foto de cada loja (a importação aplicada mais recente)
create or replace function interno.estoque_ultima_importacao(p_loja smallint) returns bigint
language sql stable security definer set search_path to '' as $$
  select i.id from public.importacoes i where i.status = 'aplicada' and i.tipo = 'estoque_' || (select codigo from public.lojas where id = p_loja)
  order by i.criado_em desc limit 1
$$;

create or replace function public.previa_importacao_estoque(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb; t text; lj smallint; ant bigint;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('estoque_PVA','estoque_RV') or not interno.pode_importar('estoque') then raise exception 'Sem permissão para importar estoque'; end if;
  lj := case when t = 'estoque_PVA' then 1 else 2 end;
  ant := interno.estoque_ultima_importacao(lj);
  with s as (
    select d->>'codigo' codigo, d->>'local' local, coalesce((d->>'quantidade')::numeric,0) q, coalesce((d->>'valor')::numeric,0) v, (d->>'custo')::numeric custo, d->>'nome' nome
    from (select dados d from public.estoque_staging where importacao_id = p_importacao) z),
  p as (select codigo, max(nome) nome, max(custo) custo, sum(v) v, sum(q) q from s group by codigo),
  ult as (select it.codigo, max(e.data_entrada) ult from public.entradas_santri_itens it join public.entradas_santri e on e.id = it.entrada_id
          where e.loja_id = lj and e.status <> 'Aberta' and it.ativo group by it.codigo)
  select jsonb_build_object(
    'loja_id', lj,
    'produtos', (select count(*) from p),
    'linhas', (select count(*) from s),
    'valor', (select coalesce(sum(v),0) from s),
    'por_local', (select coalesce(jsonb_object_agg(local, jsonb_build_object('produtos', n, 'valor', round(vv,2))), '{}'::jsonb)
                  from (select local, count(*) n, sum(v) vv from s group by local) x),
    'sem_custo', (select count(*) from p where coalesce(custo,0) = 0),
    'custo_suspeito', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'custo', custo, 'valor', round(v,2)) order by v desc), '[]'::jsonb)
                       from p where v > 0.2 * (select sum(v) from p) and (select count(*) from p) > 20),
    'sem_entrada_2026', (select count(*) from p where not exists (select 1 from ult where ult.codigo = p.codigo and ult.ult >= date '2026-01-01')),
    'sem_entrada_2026_valor', (select coalesce(sum(v),0) from p where not exists (select 1 from ult where ult.codigo = p.codigo and ult.ult >= date '2026-01-01')),
    'foto_anterior', (select jsonb_build_object('em', i.criado_em, 'valor', (select sum(valor) from public.estoque_foto f where f.importacao_id = ant)) from public.importacoes i where i.id = ant)
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_estoque(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; t text; lj smallint; dia date; n int;
begin
  select tipo, (criado_em at time zone 'America/Cuiaba')::date into t, dia from public.importacoes where id = p_importacao;
  if t not in ('estoque_PVA','estoque_RV') or not interno.pode_importar('estoque') then raise exception 'Sem permissão para importar estoque'; end if;
  lj := case when t = 'estoque_PVA' then 1 else 2 end;
  if exists (select 1 from public.estoque_foto where importacao_id = p_importacao) then raise exception 'Esta importação já foi gravada'; end if;
  res := public.previa_importacao_estoque(p_importacao);
  insert into public.estoque_foto (importacao_id, loja_id, data_foto, produto_id, codigo, nome, marca, cod_original, unidade, custo, local, quantidade, valor)
  select p_importacao, lj, dia, (select p.id from public.produtos p where (d->>'codigo') ~ '^\d+$' and p.id = (d->>'codigo')::bigint),
    d->>'codigo', d->>'nome', d->>'marca', d->>'cod_original', d->>'unidade', (d->>'custo')::numeric, d->>'local',
    (d->>'quantidade')::numeric, (d->>'valor')::numeric
  from (select dados d from public.estoque_staging where importacao_id = p_importacao) z;
  get diagnostics n = row_count;
  res := res || jsonb_build_object('novos', n, 'alterados', 0, 'iguais', 0, 'no_arquivo', n);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = n where id = p_importacao;
  return res;
end $$;
