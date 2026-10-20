-- Migration 35 · DRE do Santri (Demonstrativo de Resultado, competência, analítico) — uma loja por arquivo (dre_PVA / dre_RV)
-- Uma linha por loja + ano + mês + linha do plano (código; linhas calculadas como "Margem de contribuição" usam o nome).
-- Reimportar atualiza os valores e guarda no histórico o que mudou (mês já fechado que mudou de valor).
-- Atenção (achado de 14/10): os impostos da DRE vêm dos títulos lançados no financeiro, não da venda.

create table if not exists public.dre_santri (
  loja_id smallint not null references public.lojas(id),
  ano int not null, mes int not null,
  chave text not null,
  codigo text, descricao text, nivel int, ordem int,
  valor numeric,
  importacao_id bigint references public.importacoes(id),
  atualizado_em timestamptz not null default now(),
  primary key (loja_id, ano, mes, chave)
);

create table if not exists public.dre_santri_eventos (
  id bigserial primary key,
  loja_id smallint not null, ano int not null, mes int not null, chave text not null,
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  de numeric, para numeric
);

create table if not exists public.dre_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.dre_santri enable row level security;
alter table public.dre_santri_eventos enable row level security;
alter table public.dre_staging enable row level security;

create policy dre_ler on public.dre_santri for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy dree_ler on public.dre_santri_eventos for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy drestg_dono on public.dre_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = dre_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = dre_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

create or replace function public.previa_importacao_dre(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb; t text; lj smallint;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('dre_PVA','dre_RV') or not interno.pode_importar('dre') then raise exception 'Sem permissão para importar a DRE'; end if;
  lj := case when t = 'dre_PVA' then 1 else 2 end;
  with s as (select (d->>'ano')::int ano, (d->>'mes')::int mes, d->>'chave' chave, coalesce((d->>'valor')::numeric,0) v
             from (select dados d from public.dre_staging where importacao_id = p_importacao) z),
  j as (select s.*, x.valor xv, x.chave xc from s left join public.dre_santri x on x.loja_id = lj and x.ano = s.ano and x.mes = s.mes and x.chave = s.chave)
  select jsonb_build_object(
    'loja_id', lj,
    'no_arquivo', (select count(distinct chave) from s),
    'anos', (select jsonb_agg(distinct ano) from s),
    'meses', (select jsonb_agg(x order by (x->>'ano')::int, (x->>'mes')::int) from (select jsonb_build_object('ano', ano, 'mes', mes,
                 'receita', sum(v) filter (where chave = 'A'), 'mc', sum(v) filter (where chave = '=margem de contribuicao'),
                 'resultado', sum(v) filter (where chave = '=resultado liquido')) x
               from s group by ano, mes having sum(abs(v)) > 0) m),
    'novos', (select count(*) from j where xc is null and v <> 0),
    'alterados', (select count(*) from j where xc is not null and abs(coalesce(xv,0) - v) > 0.009),
    'iguais', (select count(*) from j where xc is not null and abs(coalesce(xv,0) - v) <= 0.009)
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_dre(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; t text; lj smallint;
begin
  select tipo into t from public.importacoes where id = p_importacao;
  if t not in ('dre_PVA','dre_RV') or not interno.pode_importar('dre') then raise exception 'Sem permissão para importar a DRE'; end if;
  lj := case when t = 'dre_PVA' then 1 else 2 end;
  res := public.previa_importacao_dre(p_importacao);

  insert into public.dre_santri_eventos (loja_id, ano, mes, chave, importacao_id, de, para)
  select lj, x.ano, x.mes, x.chave, p_importacao, x.valor, (d->>'valor')::numeric
  from (select dados d from public.dre_staging where importacao_id = p_importacao) z
  join public.dre_santri x on x.loja_id = lj and x.ano = (d->>'ano')::int and x.mes = (d->>'mes')::int and x.chave = d->>'chave'
  where abs(coalesce(x.valor,0) - coalesce((d->>'valor')::numeric,0)) > 0.009;

  insert into public.dre_santri as x (loja_id, ano, mes, chave, codigo, descricao, nivel, ordem, valor, importacao_id)
  select distinct on ((d->>'ano')::int, (d->>'mes')::int, d->>'chave') lj, (d->>'ano')::int, (d->>'mes')::int, d->>'chave', nullif(d->>'codigo',''),
    d->>'descricao', (d->>'nivel')::int, (d->>'ordem')::int, (d->>'valor')::numeric, p_importacao
  from (select dados d from public.dre_staging where importacao_id = p_importacao) z
  order by (d->>'ano')::int, (d->>'mes')::int, d->>'chave', (d->>'ordem')::int
  on conflict (loja_id, ano, mes, chave) do update set codigo = excluded.codigo, descricao = excluded.descricao, nivel = excluded.nivel,
    ordem = excluded.ordem, valor = excluded.valor, importacao_id = excluded.importacao_id, atualizado_em = now();

  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;
