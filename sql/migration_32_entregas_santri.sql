-- Migration 32 · Entregas do Santri (Gerenciamento de Entregas – Por Entregas – Analítico, "Não filtrar")
-- Entregas geradas: uma linha por entrega (loja + nº da entrega), com histórico do que mudou (separação, manifesto, situação, local).
-- Pendentes e sem agendamento não têm nº de entrega: ficam como foto de cada importação (vale a última).
-- Pedido = nº da venda do Santri. Atenção: "Data entrega" do Santri = dia em que a entrega foi gerada, não a entrega ao cliente.

create table if not exists public.entregas_santri (
  id bigserial primary key,
  loja_id smallint not null references public.lojas(id),
  entrega text not null,
  pedido text,
  cliente_codigo text, cliente_nome text, telefone text,
  data_cadastro date, data_entrega date, prev_menor date, prev_maior date,
  local text, tipo_controle text, status_separacao text, status_manifesto text, status_entrega text,
  valor numeric, peso numeric, bairro text, cidade text,
  previsao_inicio timestamp, duracao_horas numeric,
  concluida_em date,                          -- 1ª importação em que a situação apareceu como Total
  ativo boolean not null default true,
  assinatura text,
  importacao_id bigint references public.importacoes(id),
  primeira_importacao_id bigint references public.importacoes(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (loja_id, entrega)
);
create index if not exists entregas_santri_pedido_idx on public.entregas_santri (pedido);

create table if not exists public.entregas_santri_itens (
  entrega_id bigint not null references public.entregas_santri(id),
  ordem int not null,
  produto_id bigint, codigo text, nome text, marca text, lote text, unidade text, peso numeric, quantidade numeric,
  ativo boolean not null default true,
  primary key (entrega_id, ordem)
);

create table if not exists public.entregas_santri_eventos (
  id bigserial primary key,
  entrega_id bigint not null references public.entregas_santri(id),
  importacao_id bigint references public.importacoes(id),
  em timestamptz not null default now(),
  campo text not null, de text, para text
);

create table if not exists public.entregas_pendentes (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  loja_id smallint not null references public.lojas(id),
  secao text not null,                          -- pendente | sem_agendamento
  pedido text, cliente_codigo text, cliente_nome text, telefone text,
  data_cadastro date, prev_menor date, prev_maior date, status_separacao text,
  valor numeric, peso numeric, bairro text, cidade text,
  itens jsonb
);
create index if not exists entregas_pendentes_imp_idx on public.entregas_pendentes (importacao_id);

create table if not exists public.entregas_staging (
  id bigserial primary key,
  importacao_id bigint not null references public.importacoes(id),
  dados jsonb not null
);

alter table public.entregas_santri enable row level security;
alter table public.entregas_santri_itens enable row level security;
alter table public.entregas_santri_eventos enable row level security;
alter table public.entregas_pendentes enable row level security;
alter table public.entregas_staging enable row level security;

create policy en_ler on public.entregas_santri for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy eni_ler on public.entregas_santri_itens for select to authenticated
  using (exists (select 1 from public.entregas_santri e where e.id = entregas_santri_itens.entrega_id));
create policy ene_ler on public.entregas_santri_eventos for select to authenticated
  using (exists (select 1 from public.entregas_santri e where e.id = entregas_santri_eventos.entrega_id));
create policy enp_ler on public.entregas_pendentes for select to authenticated
  using ((select interno.pode_ver_compras()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy enstg_dono on public.entregas_staging for all to authenticated
  using ((select interno.ve_todas_lojas()) or exists (select 1 from public.importacoes i where i.id = entregas_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = entregas_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));

create or replace function interno.assinatura_entrega(d jsonb) returns text
language sql immutable set search_path to '' as $$
  select md5(jsonb_build_array(d->'pedido', d->'local', d->'status_separacao', d->'status_manifesto', d->'status_entrega', d->'valor', d->'peso',
    d->'prev_menor', d->'prev_maior', d->'tipo_controle',
    (select coalesce(jsonb_agg(jsonb_build_array(i->'codigo', i->'quantidade', i->'lote') order by (i->>'ordem')::int), '[]'::jsonb)
       from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i))::text)
$$;

create or replace function public.previa_importacao_entregas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.pode_importar('entregas') then raise exception 'Sem permissão para importar entregas'; end if;
  with s as (
    select d->>'secao' secao, (d->>'loja_id')::smallint loja_id, d->>'entrega' entrega, d->>'pedido' pedido, (d->>'data_cadastro')::date dc,
           coalesce((d->>'valor')::numeric,0) vl, d->>'status_manifesto' sm, d->>'status_entrega' se, (d->>'prev_maior')::date pm,
           interno.assinatura_entrega(d) sig
    from (select dados d from public.entregas_staging where importacao_id = p_importacao) z),
  g as (select s.*, e.id eid, e.assinatura esig, e.status_entrega ese from s left join public.entregas_santri e on e.loja_id = s.loja_id and e.entrega = s.entrega where s.secao = 'gerada')
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'geradas', (select count(*) from s where secao = 'gerada'),
    'pendentes', (select count(*) from s where secao = 'pendente'),
    'pendentes_valor', (select coalesce(sum(vl),0) from s where secao = 'pendente'),
    'pendentes_vencidas', (select count(*) from s where secao = 'pendente' and pm < current_date),
    'sem_agendamento', (select count(*) from s where secao = 'sem_agendamento'),
    'sem_agendamento_valor', (select coalesce(sum(vl),0) from s where secao = 'sem_agendamento'),
    'aguardando', (select count(*) from s where secao = 'gerada' and sm = 'Aguardando Carregamento'),
    'aguardando_valor', (select coalesce(sum(vl),0) from s where secao = 'gerada' and sm = 'Aguardando Carregamento'),
    'concluidas', (select count(*) from s where secao = 'gerada' and se = 'Entrega total'),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(dc) from s where secao = 'gerada'), 'ate', (select max(dc) from s where secao = 'gerada'),
    'pedidos_no_sistema', (select count(distinct pedido) from s where exists (select 1 from public.vendas_santri v where v.tipo = 'PED' and v.numero = s.pedido)),
    'pedidos', (select count(distinct pedido) from s),
    'novos', (select count(*) from g where eid is null),
    'alterados', (select count(*) from g where eid is not null and esig is distinct from sig),
    'iguais', (select count(*) from g where eid is not null and esig = sig),
    'concluidas_agora', (select count(*) from g where eid is not null and se = 'Entrega total' and ese is distinct from 'Entrega total')
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_entregas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
#variable_conflict use_column
declare res jsonb; d jsonb; eid bigint; sig text; old public.entregas_santri%rowtype; dia date;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0; n_sum int := 0;
begin
  if not interno.pode_importar('entregas') then raise exception 'Sem permissão para importar entregas'; end if;
  res := public.previa_importacao_entregas(p_importacao);
  select criado_em::date into dia from public.importacoes where id = p_importacao;
  for d in select dados from public.entregas_staging where importacao_id = p_importacao and dados->>'secao' = 'gerada' order by id loop
    sig := interno.assinatura_entrega(d); old := null;
    select * into old from public.entregas_santri where loja_id = (d->>'loja_id')::smallint and entrega = d->>'entrega';
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig or not old.ativo then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.entregas_santri as e (loja_id, entrega, pedido, cliente_codigo, cliente_nome, telefone, data_cadastro, data_entrega,
      prev_menor, prev_maior, local, tipo_controle, status_separacao, status_manifesto, status_entrega, valor, peso, bairro, cidade,
      previsao_inicio, duracao_horas, concluida_em, ativo, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'entrega', d->>'pedido', d->>'cliente_codigo', d->>'cliente_nome', d->>'telefone',
      (d->>'data_cadastro')::date, (d->>'data_entrega')::date, (d->>'prev_menor')::date, (d->>'prev_maior')::date, d->>'local',
      d->>'tipo_controle', d->>'status_separacao', d->>'status_manifesto', d->>'status_entrega', (d->>'valor')::numeric, (d->>'peso')::numeric,
      d->>'bairro', d->>'cidade', (d->>'previsao_inicio')::timestamp, (d->>'duracao_horas')::numeric,
      case when d->>'status_entrega' = 'Total' then dia end, true, sig, p_importacao, p_importacao)
    on conflict (loja_id, entrega) do update set
      pedido = excluded.pedido, cliente_codigo = excluded.cliente_codigo, cliente_nome = excluded.cliente_nome, telefone = excluded.telefone,
      data_cadastro = excluded.data_cadastro, data_entrega = excluded.data_entrega, prev_menor = excluded.prev_menor, prev_maior = excluded.prev_maior,
      local = excluded.local, tipo_controle = excluded.tipo_controle, status_separacao = excluded.status_separacao,
      status_manifesto = excluded.status_manifesto, status_entrega = excluded.status_entrega, valor = excluded.valor, peso = excluded.peso,
      bairro = excluded.bairro, cidade = excluded.cidade, previsao_inicio = excluded.previsao_inicio, duracao_horas = excluded.duracao_horas,
      concluida_em = case when excluded.status_entrega = 'Total' then coalesce(e.concluida_em, dia) else null end,
      ativo = true, assinatura = excluded.assinatura, importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into eid;

    insert into public.entregas_santri_itens as t (entrega_id, ordem, produto_id, codigo, nome, marca, lote, unidade, peso, quantidade, ativo)
    select eid, (i->>'ordem')::int, (select p.id from public.produtos p where (i->>'codigo') ~ '^\d+$' and p.id = (i->>'codigo')::bigint),
      i->>'codigo', i->>'nome', i->>'marca', nullif(i->>'lote',''), i->>'unidade', (i->>'peso')::numeric, (i->>'quantidade')::numeric, true
    from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i
    on conflict (entrega_id, ordem) do update set produto_id = excluded.produto_id, codigo = excluded.codigo, nome = excluded.nome,
      marca = excluded.marca, lote = excluded.lote, unidade = excluded.unidade, peso = excluded.peso, quantidade = excluded.quantidade, ativo = true;
    update public.entregas_santri_itens set ativo = false where entrega_id = eid and ativo and ordem > jsonb_array_length(coalesce(d->'itens','[]'::jsonb));

    if old.id is null then
      insert into public.entregas_santri_eventos (entrega_id, importacao_id, campo, de, para) values (eid, p_importacao, 'status_entrega', null, d->>'status_entrega');
    else
      insert into public.entregas_santri_eventos (entrega_id, importacao_id, campo, de, para)
      select eid, p_importacao, x.campo, x.de, x.para from (values
        ('status_separacao', old.status_separacao, d->>'status_separacao'),
        ('status_manifesto', old.status_manifesto, d->>'status_manifesto'),
        ('status_entrega', old.status_entrega, d->>'status_entrega'),
        ('local', old.local, d->>'local'),
        ('valor', old.valor::text, (d->>'valor')::numeric::text),
        ('ativo', old.ativo::text, 'true')
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;

  -- geradas dentro do período de cadastro e das lojas do arquivo que não vieram mais: excluídas no Santri
  with s as (select (d->>'loja_id')::smallint loja_id, d->>'entrega' entrega, (d->>'data_cadastro')::date dc
             from (select dados d from public.entregas_staging where importacao_id = p_importacao and dados->>'secao' = 'gerada') z),
       per as (select loja_id, min(dc) de, max(dc) ate from s group by 1),
       sai as (update public.entregas_santri e set ativo = false, atualizado_em = now() from per
               where per.loja_id = e.loja_id and e.ativo and e.data_cadastro between per.de and per.ate
                 and not exists (select 1 from s where s.loja_id = e.loja_id and s.entrega = e.entrega)
               returning e.id)
  insert into public.entregas_santri_eventos (entrega_id, importacao_id, campo, de, para) select id, p_importacao, 'ativo', 'true', 'false' from sai;
  get diagnostics n_sum = row_count;

  -- foto das pendentes e sem agendamento
  insert into public.entregas_pendentes (importacao_id, loja_id, secao, pedido, cliente_codigo, cliente_nome, telefone, data_cadastro,
    prev_menor, prev_maior, status_separacao, valor, peso, bairro, cidade, itens)
  select p_importacao, (d->>'loja_id')::smallint, d->>'secao', d->>'pedido', d->>'cliente_codigo', d->>'cliente_nome', d->>'telefone',
    (d->>'data_cadastro')::date, (d->>'prev_menor')::date, (d->>'prev_maior')::date, d->>'status_separacao', (d->>'valor')::numeric,
    (d->>'peso')::numeric, d->>'bairro', d->>'cidade', d->'itens'
  from (select dados d from public.entregas_staging where importacao_id = p_importacao and dados->>'secao' <> 'gerada') z;

  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais, 'inativados', n_sum);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;
