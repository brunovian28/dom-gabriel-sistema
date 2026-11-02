-- Migration 43: triagem dos títulos atrasados (a pagar) e cobrança (a receber), com histórico (F2 Caixa)

create table if not exists public.titulos_tratativa (
  titulo_id bigint primary key references public.titulos_santri(id),
  decisao text not null check (decisao in ('pagar_em','renegociado','em_disputa','nao_e_divida','para_diretoria','prometeu','negociando','perdido')),
  nova_data date,
  responsavel text,
  nota text,
  por uuid,
  em timestamptz not null default now()
);
alter table public.titulos_tratativa enable row level security;
create policy titulos_tratativa_le on public.titulos_tratativa for select to authenticated
  using ((select interno.pode_ver_financeiro()) and exists (
    select 1 from public.titulos_santri t where t.id = titulo_id
      and ((select interno.le_todas_lojas()) or t.loja_id = (select interno.minha_loja()))));

create table if not exists public.titulos_tratativa_eventos (
  id bigint generated always as identity primary key,
  titulo_id bigint not null references public.titulos_santri(id),
  decisao text not null,
  nova_data date,
  nota text,
  por uuid,
  em timestamptz not null default now()
);
create index if not exists titulos_tratativa_eventos_idx on public.titulos_tratativa_eventos (titulo_id, em desc);
alter table public.titulos_tratativa_eventos enable row level security;
create policy titulos_tratativa_eventos_le on public.titulos_tratativa_eventos for select to authenticated
  using ((select interno.pode_ver_financeiro()) and exists (
    select 1 from public.titulos_santri t where t.id = titulo_id
      and ((select interno.le_todas_lojas()) or t.loja_id = (select interno.minha_loja()))));

-- Grava a mesma decisão em um ou vários títulos. Devolve quantos foram gravados.
create or replace function public.tratar_titulos(p_ids bigint[], p_decisao text, p_nova_data date, p_nota text)
returns int language plpgsql security definer set search_path to '' as $$
declare v_ids bigint[]; v_achados int; v_lado text; v_n int;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção tratam títulos'; end if;
  select array_agg(distinct x) into v_ids from unnest(p_ids) x where x is not null;
  if v_ids is null then raise exception 'Escolha ao menos um título'; end if;
  if p_decisao is null or p_decisao not in ('pagar_em','renegociado','em_disputa','nao_e_divida','para_diretoria','prometeu','negociando','perdido') then
    raise exception 'Decisão inválida';
  end if;
  select count(*) into v_achados from public.titulos_santri t
   where t.id = any(v_ids) and t.loja_id = any(interno.lojas_tela(0::smallint));
  if v_achados <> array_length(v_ids, 1) then raise exception 'Título não encontrado ou de outra loja'; end if;
  for v_lado in select distinct t.lado from public.titulos_santri t where t.id = any(v_ids) loop
    if v_lado = 'pagar' and p_decisao not in ('pagar_em','renegociado','em_disputa','nao_e_divida','para_diretoria') then
      raise exception 'Decisão não vale para contas a pagar';
    end if;
    if v_lado = 'receber' and p_decisao not in ('prometeu','negociando','perdido') then
      raise exception 'Decisão não vale para contas a receber';
    end if;
  end loop;
  if p_decisao in ('pagar_em','renegociado','prometeu') and p_nova_data is null then raise exception 'Informe a data'; end if;

  insert into public.titulos_tratativa (titulo_id, decisao, nova_data, nota, por, em)
  select x, p_decisao, p_nova_data, nullif(trim(p_nota),''), auth.uid(), now() from unnest(v_ids) x
  on conflict (titulo_id) do update
    set decisao = excluded.decisao, nova_data = excluded.nova_data, nota = excluded.nota, por = excluded.por, em = excluded.em;
  get diagnostics v_n = row_count;
  insert into public.titulos_tratativa_eventos (titulo_id, decisao, nova_data, nota, por)
  select x, p_decisao, p_nova_data, nullif(trim(p_nota),''), auth.uid() from unnest(v_ids) x;
  return v_n;
end $$;

grant execute on function public.tratar_titulos(bigint[], text, date, text) to authenticated;
