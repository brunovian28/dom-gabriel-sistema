-- Migration 63 · Notas fiscais de saída (Santri: Relação de Notas Fiscais, sintético)
-- Uma linha por nota (loja + Cód.nota), com histórico em notas_saida_eventos. A remessa (Entregas / Entregas agrupadas)
-- é a prova de que a mercadoria saiu: cod_movimento = nº da entrega (entregas_santri.entrega). Pedido = faturamento (vendas_santri.numero).
-- Período do arquivo = menor e maior emissão DO ARQUIVO, POR LOJA: nota ativa nesse período e loja que não veio vira ativo=false (evento sumiu).
-- Mesmo padrão da migration 32 (entregas): staging → prévia → aplicar, sem DELETE. A Importadora limpa a staging depois.

create table if not exists public.notas_saida (
  id bigint generated always as identity primary key,
  loja_id smallint not null references public.lojas(id),
  cod_nota text not null,
  nr_nota text, serie text, emissao date, tipo_doc text,
  cliente_codigo text, cliente_nome text, valor_total numeric, cfop text,
  tipo_movimento text, cod_movimento text, chave_nfe text, peso numeric, usuario text, observacao text,
  ativo boolean not null default true,
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (loja_id, cod_nota)
);
create index if not exists notas_saida_mov_idx on public.notas_saida (loja_id, tipo_movimento, cod_movimento) where ativo;
create index if not exists notas_saida_emissao_idx on public.notas_saida (loja_id, emissao) where ativo;

create table if not exists public.notas_saida_eventos (
  id bigint generated always as identity primary key,
  nota_id bigint not null references public.notas_saida(id),
  importacao_id bigint references public.importacoes(id),
  evento text not null check (evento in ('novo','alterou','sumiu','voltou')),
  antes jsonb,
  em timestamptz not null default now()
);
create index if not exists notas_saida_eventos_nota_idx on public.notas_saida_eventos (nota_id);
create index if not exists notas_saida_eventos_imp_idx on public.notas_saida_eventos (importacao_id);

create table if not exists public.notas_saida_staging (
  id bigint generated always as identity primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);
create index if not exists notas_saida_staging_imp_idx on public.notas_saida_staging (importacao_id);

alter table public.notas_saida enable row level security;
alter table public.notas_saida_eventos enable row level security;
alter table public.notas_saida_staging enable row level security;

create policy ns_ler on public.notas_saida for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy nse_ler on public.notas_saida_eventos for select to authenticated
  using (exists (select 1 from public.notas_saida n where n.id = notas_saida_eventos.nota_id));
create policy nsstg_dono on public.notas_saida_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = notas_saida_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = notas_saida_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

-- Catálogo da rotina (também dá a permissão de importar: setores = logistica, mais direção e "importa tudo")
insert into public.relatorios_rotina (tipo, nome, ordem, menu_santri, filtros, dicas, setores, prazo_dias, tipos_importacao, disponivel, ativo)
values ('notas_saida', 'Notas fiscais emitidas', 120,
  'Relação de Notas Fiscais, botão Planilha, versão sintética',
  'Data de emissão: da última importação até hoje (primeira vez: desde 01/01/2026) · Empresa: as duas · Tipo de movimento: todos',
  'Mostra as notas que saíram de verdade, inclusive a remessa de cada entrega.',
  array['logistica'], 7, array['notas_saida'], true, true)
on conflict (tipo) do update set nome = excluded.nome, menu_santri = excluded.menu_santri, filtros = excluded.filtros, dicas = excluded.dicas,
  setores = excluded.setores, prazo_dias = excluded.prazo_dias, tipos_importacao = excluded.tipos_importacao, disponivel = excluded.disponivel;

create or replace function interno.assinatura_nota_saida(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'nr_nota', d->'serie', d->'emissao', d->'tipo_doc', d->'cliente_codigo', d->'cliente_nome', d->'valor_total',
    d->'cfop', d->'tipo_movimento', d->'cod_movimento', d->'chave_nfe', d->'peso', d->'usuario', d->'observacao')::text)
$$;
revoke execute on function interno.assinatura_nota_saida(jsonb) from anon, public;
grant execute on function interno.assinatura_nota_saida(jsonb) to authenticated;

create or replace function public.previa_importacao_notas_saida(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
#variable_conflict use_column
declare r jsonb;
begin
  if not interno.pode_importar('notas_saida') then raise exception 'Sem permissão para importar notas fiscais de saída'; end if;
  with s as (
    select distinct on (loja_id, cod_nota) loja_id, cod_nota, emissao, tipo, cod_mov, sig from (
      select (d->>'loja_id')::smallint loja_id, d->>'cod_nota' cod_nota, (d->>'emissao')::date emissao, d->>'tipo_movimento' tipo,
             d->>'cod_movimento' cod_mov, interno.assinatura_nota_saida(d) sig, id
      from public.notas_saida_staging, lateral (select dados d) z where importacao_id = p_importacao) q
    order by loja_id, cod_nota, id desc),
  g as (select s.*, n.id nid, n.assinatura nsig, n.ativo nativo from s left join public.notas_saida n on n.loja_id = s.loja_id and n.cod_nota = s.cod_nota),
  per as (select loja_id, min(emissao) de, max(emissao) ate from s group by 1)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(emissao) from s), 'ate', (select max(emissao) from s),
    'por_tipo', coalesce((select jsonb_object_agg(tipo, n) from (select coalesce(tipo, '') tipo, count(*) n from s group by 1) t), '{}'::jsonb),
    'novos', (select count(*) from g where nid is null),
    'alterados', (select count(*) from g where nid is not null and (nsig is distinct from sig or not nativo)),
    'iguais', (select count(*) from g where nid is not null and nsig = sig and nativo),
    'sumiram', (select count(*) from public.notas_saida n join per on per.loja_id = n.loja_id
                where n.ativo and n.emissao between per.de and per.ate
                  and not exists (select 1 from s where s.loja_id = n.loja_id and s.cod_nota = n.cod_nota)),
    'remessas', (select count(*) from s where tipo in ('Entregas','Entregas agrupadas')),
    'remessas_ligadas', (select count(*) from s where tipo in ('Entregas','Entregas agrupadas')
                         and exists (select 1 from public.entregas_santri e where e.loja_id = s.loja_id and e.entrega = s.cod_mov and e.ativo)),
    'pedidos_faturados', (select count(*) from s where tipo = 'Pedido'),
    'pedidos_no_sistema', (select count(*) from s where tipo = 'Pedido'
                           and exists (select 1 from public.vendas_santri v where v.loja_id = s.loja_id and v.tipo = 'PED' and v.numero = s.cod_mov))
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_notas_saida(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
#variable_conflict use_column
declare res jsonb; d jsonb; nid bigint; sig text; old public.notas_saida%rowtype;
begin
  if not interno.pode_importar('notas_saida') then raise exception 'Sem permissão para importar notas fiscais de saída'; end if;
  res := public.previa_importacao_notas_saida(p_importacao);
  for d in select dados from (
      select distinct on ((dados->>'loja_id'), (dados->>'cod_nota')) dados, id from public.notas_saida_staging
      where importacao_id = p_importacao order by (dados->>'loja_id'), (dados->>'cod_nota'), id desc) q order by id loop
    sig := interno.assinatura_nota_saida(d); old := null;
    select * into old from public.notas_saida where loja_id = (d->>'loja_id')::smallint and cod_nota = d->>'cod_nota';
    if old.id is not null and old.assinatura is not distinct from sig and old.ativo then continue; end if;

    insert into public.notas_saida as n (loja_id, cod_nota, nr_nota, serie, emissao, tipo_doc, cliente_codigo, cliente_nome, valor_total, cfop,
      tipo_movimento, cod_movimento, chave_nfe, peso, usuario, observacao, ativo, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'cod_nota', d->>'nr_nota', d->>'serie', (d->>'emissao')::date, d->>'tipo_doc', d->>'cliente_codigo',
      d->>'cliente_nome', (d->>'valor_total')::numeric, d->>'cfop', d->>'tipo_movimento', d->>'cod_movimento', d->>'chave_nfe',
      (d->>'peso')::numeric, d->>'usuario', d->>'observacao', true, sig, p_importacao, p_importacao)
    on conflict (loja_id, cod_nota) do update set
      nr_nota = excluded.nr_nota, serie = excluded.serie, emissao = excluded.emissao, tipo_doc = excluded.tipo_doc,
      cliente_codigo = excluded.cliente_codigo, cliente_nome = excluded.cliente_nome, valor_total = excluded.valor_total, cfop = excluded.cfop,
      tipo_movimento = excluded.tipo_movimento, cod_movimento = excluded.cod_movimento, chave_nfe = excluded.chave_nfe, peso = excluded.peso,
      usuario = excluded.usuario, observacao = excluded.observacao, ativo = true, assinatura = excluded.assinatura,
      importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into nid;

    insert into public.notas_saida_eventos (nota_id, importacao_id, evento, antes)
    values (nid, p_importacao,
      case when old.id is null then 'novo' when not old.ativo then 'voltou' else 'alterou' end,
      case when old.id is null then null else to_jsonb(old) end);
  end loop;

  -- notas ativas no período de emissão do arquivo (por loja) que não vieram mais: canceladas/excluídas no Santri
  with s as (select (dados->>'loja_id')::smallint loja_id, dados->>'cod_nota' cod_nota, (dados->>'emissao')::date emissao
             from public.notas_saida_staging where importacao_id = p_importacao),
       per as (select loja_id, min(emissao) de, max(emissao) ate from s group by 1),
       sai as (update public.notas_saida n set ativo = false, atualizado_em = now() from per
               where per.loja_id = n.loja_id and n.ativo and n.emissao between per.de and per.ate
                 and not exists (select 1 from s where s.loja_id = n.loja_id and s.cod_nota = n.cod_nota)
               returning n.id)
  insert into public.notas_saida_eventos (nota_id, importacao_id, evento, antes)
  select id, p_importacao, 'sumiu', jsonb_build_object('ativo', true) from sai;

  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;

revoke execute on function public.previa_importacao_notas_saida(bigint) from anon, public;
grant execute on function public.previa_importacao_notas_saida(bigint) to authenticated;
revoke execute on function public.aplicar_importacao_notas_saida(bigint) from anon, public;
grant execute on function public.aplicar_importacao_notas_saida(bigint) to authenticated;
