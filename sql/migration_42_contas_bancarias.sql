-- Migration 42: contas bancárias, saldo por conta e caixa mínimo por loja (F2 Caixa)

create table if not exists public.contas_bancarias (
  id bigint generated always as identity primary key,
  loja_id smallint not null references public.lojas(id),
  banco text not null,
  nome text not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
alter table public.contas_bancarias enable row level security;
create policy contas_bancarias_le on public.contas_bancarias for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

create table if not exists public.caixa_parametros (
  loja_id smallint primary key references public.lojas(id),
  caixa_minimo numeric not null default 0,
  atualizado_por uuid,
  atualizado_em timestamptz default now()
);
alter table public.caixa_parametros enable row level security;
create policy caixa_parametros_le on public.caixa_parametros for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

alter table public.caixa_saldo add column if not exists conta_id bigint references public.contas_bancarias(id);
create index if not exists caixa_saldo_conta_idx on public.caixa_saldo (conta_id, criado_em desc);

-- Conta "Geral" por loja: recebe os saldos que já existiam e o que a tela de Compras informar
insert into public.contas_bancarias (loja_id, banco, nome)
select l.id, '—', 'Geral' from public.lojas l
where not exists (select 1 from public.contas_bancarias c where c.loja_id = l.id and c.nome = 'Geral');
update public.caixa_saldo s set conta_id = (select c.id from public.contas_bancarias c where c.loja_id = s.loja_id and c.nome = 'Geral' order by c.id limit 1)
where s.conta_id is null;

-- Último saldo de cada conta ativa (conta sem saldo volta com saldo e data nulos)
create or replace function interno.saldo_caixa(p_lojas smallint[])
returns table(loja_id smallint, conta_id bigint, banco text, nome text, saldo numeric, data date, em timestamptz)
language sql stable security definer set search_path to '' as $$
  select c.loja_id, c.id, c.banco, c.nome, s.saldo, s.data, s.criado_em
  from public.contas_bancarias c
  left join lateral (select x.saldo, x.data, x.criado_em from public.caixa_saldo x
                     where x.conta_id = c.id order by x.criado_em desc, x.id desc limit 1) s on true
  where c.ativo and c.loja_id = any(p_lojas)
  order by c.loja_id, c.id
$$;

create or replace function public.salvar_conta_bancaria(p_id bigint, p_loja smallint, p_banco text, p_nome text, p_ativo boolean)
returns bigint language plpgsql security definer set search_path to '' as $$
declare v_id bigint; v_loja smallint;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção cadastram contas'; end if;
  if coalesce(p_loja,0) = 0 or not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  if nullif(trim(p_banco),'') is null or nullif(trim(p_nome),'') is null then raise exception 'Informe o banco e o nome da conta'; end if;
  if p_id is null then
    insert into public.contas_bancarias (loja_id, banco, nome, ativo)
    values (p_loja, trim(p_banco), trim(p_nome), coalesce(p_ativo,true)) returning id into v_id;
  else
    select loja_id into v_loja from public.contas_bancarias where id = p_id;
    if v_loja is null then raise exception 'Conta não encontrada'; end if;
    if v_loja <> p_loja then raise exception 'A conta pertence a outra loja'; end if;
    update public.contas_bancarias set banco = trim(p_banco), nome = trim(p_nome), ativo = coalesce(p_ativo,true) where id = p_id;
    v_id := p_id;
  end if;
  return v_id;
end $$;

create or replace function public.informar_saldo_conta(p_conta bigint, p_saldo numeric, p_obs text default null)
returns void language plpgsql security definer set search_path to '' as $$
declare v_loja smallint; v_ativo boolean;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção informam o saldo'; end if;
  select loja_id, ativo into v_loja, v_ativo from public.contas_bancarias where id = p_conta;
  if v_loja is null then raise exception 'Conta não encontrada'; end if;
  if not v_ativo then raise exception 'Conta desativada'; end if;
  if not (v_loja = any(interno.lojas_tela(v_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  if p_saldo is null then raise exception 'Informe o saldo'; end if;
  insert into public.caixa_saldo (loja_id, conta_id, data, saldo, observacao, informado_por)
  values (v_loja, p_conta, (now() at time zone 'America/Cuiaba')::date, p_saldo, nullif(trim(p_obs),''), auth.uid());
end $$;

create or replace function public.salvar_parametros_caixa(p_loja smallint, p_caixa_minimo numeric)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção definem o caixa mínimo'; end if;
  if coalesce(p_loja,0) = 0 or not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  if p_caixa_minimo is null or p_caixa_minimo < 0 then raise exception 'Caixa mínimo inválido'; end if;
  insert into public.caixa_parametros (loja_id, caixa_minimo, atualizado_por, atualizado_em)
  values (p_loja, p_caixa_minimo, auth.uid(), now())
  on conflict (loja_id) do update set caixa_minimo = excluded.caixa_minimo, atualizado_por = auth.uid(), atualizado_em = now();
end $$;

-- A tela de Compras continua informando o saldo por loja: vai para a conta Geral (reativa ou cria)
create or replace function public.informar_saldo_caixa(p_loja smallint, p_saldo numeric, p_obs text default null)
returns void language plpgsql security definer set search_path to '' as $$
declare v_conta bigint;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção informam o saldo'; end if;
  if coalesce(p_loja,0) = 0 then raise exception 'Escolha a loja'; end if;
  if not (p_loja = any(interno.lojas_tela(p_loja))) then raise exception 'Sem acesso a esta loja'; end if;
  select id into v_conta from public.contas_bancarias where loja_id = p_loja and nome = 'Geral' order by id limit 1;
  if v_conta is null then
    insert into public.contas_bancarias (loja_id, banco, nome) values (p_loja, '—', 'Geral') returning id into v_conta;
  else
    update public.contas_bancarias set ativo = true where id = v_conta and not ativo;
  end if;
  insert into public.caixa_saldo (loja_id, conta_id, data, saldo, observacao, informado_por)
  values (p_loja, v_conta, (now() at time zone 'America/Cuiaba')::date, p_saldo, nullif(trim(p_obs),''), auth.uid());
end $$;

grant execute on function public.salvar_conta_bancaria(bigint, smallint, text, text, boolean) to authenticated;
grant execute on function public.informar_saldo_conta(bigint, numeric, text) to authenticated;
grant execute on function public.salvar_parametros_caixa(smallint, numeric) to authenticated;

-- tela_compras: o saldo de cada loja passa a ser a soma do último saldo das contas ativas (mesmo formato de antes)
do $mig$
declare d text; d2 text; novo text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'tela_compras' and p.pronamespace = 'public'::regnamespace;
  novo := '(select case when count(x.saldo) = 0 then null else jsonb_build_object(''saldo'', sum(x.saldo), ''data'', min(x.data), ''em'', max(x.em), ''obs'', null) end from interno.saldo_caixa(array[l.id]) x) saldo,';
  d2 := regexp_replace(d, '\(select jsonb_build_object\(''saldo'', s\.saldo.*?limit 1\) saldo,', novo);
  if d2 = d then raise exception 'tela_compras: trecho do saldo nao encontrado'; end if;
  execute d2;
end $mig$;
