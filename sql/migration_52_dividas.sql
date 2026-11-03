-- Migration 52: cadastro de dívidas (contratos, parcelas, ligação aos títulos do Santri) — F2 Caixa, plano 3

create table if not exists public.dividas (
  id bigint generated always as identity primary key,
  credor text not null,
  tipo text not null check (tipo in ('banco','imposto','socio','entre_lojas','chapadao','outro')),
  loja_id smallint not null references public.lojas(id),
  outra_loja smallint references public.lojas(id),
  valor_original numeric,
  saldo_informado numeric,
  saldo_data date,
  taxa_mes numeric,
  parcela numeric,
  primeiro_venc date,
  n_parcelas int,
  modo text not null check (modo in ('fixas','santri')),
  santri_cadastro text,
  santri_plano text,
  santri_doc_prefixo text,
  origem text not null default 'cadastro' check (origem in ('cadastro','renegociacao')),
  obs text,
  ativo boolean not null default true,
  atualizado_por uuid,
  atualizado_em timestamptz default now(),
  constraint dividas_entre_lojas_ck check ((tipo = 'entre_lojas') = (outra_loja is not null and outra_loja <> loja_id)),
  constraint dividas_santri_ck check (modo <> 'santri' or santri_cadastro is not null)
);
alter table public.dividas enable row level security;
create policy dividas_le on public.dividas for select to authenticated
  using ((select interno.pode_ver_financeiro()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

create table if not exists public.dividas_parcelas (
  id bigint generated always as identity primary key,
  divida_id bigint not null references public.dividas(id),
  numero int not null,
  vencimento date not null,
  valor numeric not null,
  ativo boolean not null default true,
  criado_em timestamptz default now()
);
create index if not exists dividas_parcelas_divida_idx on public.dividas_parcelas (divida_id) where ativo;
alter table public.dividas_parcelas enable row level security;
create policy dividas_parcelas_le on public.dividas_parcelas for select to authenticated
  using ((select interno.pode_ver_financeiro()) and exists (
    select 1 from public.dividas d where d.id = divida_id and ((select interno.le_todas_lojas()) or d.loja_id = (select interno.minha_loja()))));

create table if not exists public.dividas_eventos (
  id bigint generated always as identity primary key,
  divida_id bigint not null references public.dividas(id),
  acao text not null,
  dados jsonb,
  por uuid,
  em timestamptz default now()
);
alter table public.dividas_eventos enable row level security;
create policy dividas_eventos_le on public.dividas_eventos for select to authenticated
  using ((select interno.pode_ver_financeiro()) and exists (
    select 1 from public.dividas d where d.id = divida_id and ((select interno.le_todas_lojas()) or d.loja_id = (select interno.minha_loja()))));

-- Códigos do cadastro desta loja no Santri (quando ela aparece como cliente ou fornecedor da outra)
alter table public.caixa_parametros add column if not exists cadastros_santri text[] not null default '{}';

create or replace function interno.loja_do_cadastro(p_cadastro text)
returns smallint language sql stable security definer set search_path to '' as $$
  select cp.loja_id from public.caixa_parametros cp where p_cadastro = any(cp.cadastros_santri) order by cp.loja_id limit 1
$$;

-- Filtro do Santri de um contrato: mesma loja, a pagar, sem Pre/Cre/Adi, mesmo cadastro, plano e início do documento opcionais, fora do que foi renegociado
create or replace function interno.divida_casa(d public.dividas, t public.titulos_santri)
returns boolean language sql stable security definer set search_path to '' as $$
  select d.santri_cadastro is not null and t.lado = 'pagar' and t.loja_id = d.loja_id
     and coalesce(t.tipo, '') not in ('Pre','Cre','Adi')
     and t.cadastro_codigo = d.santri_cadastro
     and (d.santri_plano is null or t.plano_codigo = d.santri_plano)
     and (d.santri_doc_prefixo is null or left(coalesce(t.documento, ''), length(d.santri_doc_prefixo)) = d.santri_doc_prefixo)
     and not exists (select 1 from public.titulos_tratativa tr where tr.titulo_id = t.id and tr.decisao = 'renegociado')
$$;

-- Parcelas dos contratos ativos: as guardadas (modo fixas, com a ligação ao título do mesmo mês) e os títulos do Santri (modo santri)
create or replace function interno.dividas_parcelas_todas(p_lojas smallint[], p_hoje date)
returns table(divida_id bigint, loja_id smallint, numero int, n_total int, vencimento date, valor numeric, titulo_id bigint, no_santri boolean)
language sql stable security definer set search_path to '' as $$
  with ut as (
    select interno.titulos_ultima_importacao('pagar') id
  ), f as (
    select p.divida_id, d.loja_id, p.numero, (count(*) over (partition by p.divida_id))::int n_total, p.vencimento, p.valor,
           (select min(t.id) from public.titulos_santri t, ut
             where t.ultima_importacao_id = ut.id and t.lado = 'pagar' and t.loja_id = d.loja_id and t.cadastro_codigo = d.santri_cadastro
               and interno.divida_casa(d, t) and date_trunc('month', t.vencimento) = date_trunc('month', p.vencimento)) tid
    from public.dividas_parcelas p
    join public.dividas d on d.id = p.divida_id
    where p.ativo and d.ativo and d.modo = 'fixas' and d.loja_id = any(p_lojas)
  ), s as (
    select d.id divida_id, d.loja_id, (row_number() over (partition by d.id order by t.vencimento, t.id))::int numero,
           (count(*) over (partition by d.id))::int n_total, t.vencimento, a.saldo_aberto valor, t.id tid
    from public.dividas d
    join public.titulos_santri t on t.lado = 'pagar' and t.loja_id = d.loja_id and t.cadastro_codigo = d.santri_cadastro and interno.divida_casa(d, t)
    join interno.titulos_aberto('pagar', p_hoje) a on a.titulo_id = t.id
    where d.ativo and d.modo = 'santri' and d.loja_id = any(p_lojas) and a.saldo_aberto > 0 and a.status <> 'pago'
  )
  select f.divida_id, f.loja_id, f.numero, f.n_total, f.vencimento, f.valor, f.tid, f.tid is not null from f
  union all
  select s.divida_id, s.loja_id, s.numero, s.n_total, s.vencimento, s.valor, s.tid, true from s
$$;

-- Salva um contrato (p_id null = novo). Chaves de p_dados = colunas de dividas (menos id, origem e auditoria). Chave ausente mantém o valor atual.
create or replace function public.salvar_divida(p_id bigint, p_dados jsonb)
returns bigint language plpgsql security definer set search_path to '' as $$
declare
  cur public.dividas; v public.dividas; v_id bigint; v_regerar boolean := false;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Loja sem permissão'; end if;
  if p_id is not null then
    select * into cur from public.dividas where id = p_id;
    if not found then raise exception 'Contrato não encontrado'; end if;
  end if;
  v.credor := case when p_dados ? 'credor' then nullif(trim(p_dados->>'credor'), '') else cur.credor end;
  v.tipo := case when p_dados ? 'tipo' then p_dados->>'tipo' else cur.tipo end;
  v.loja_id := case when p_dados ? 'loja_id' then nullif(p_dados->>'loja_id', '')::smallint else cur.loja_id end;
  v.outra_loja := case when p_dados ? 'outra_loja' then nullif(p_dados->>'outra_loja', '')::smallint else cur.outra_loja end;
  v.valor_original := case when p_dados ? 'valor_original' then nullif(p_dados->>'valor_original', '')::numeric else cur.valor_original end;
  v.saldo_informado := case when p_dados ? 'saldo_informado' then nullif(p_dados->>'saldo_informado', '')::numeric else cur.saldo_informado end;
  v.saldo_data := case when p_dados ? 'saldo_data' then nullif(p_dados->>'saldo_data', '')::date else cur.saldo_data end;
  v.taxa_mes := case when p_dados ? 'taxa_mes' then nullif(p_dados->>'taxa_mes', '')::numeric else cur.taxa_mes end;
  v.parcela := case when p_dados ? 'parcela' then nullif(p_dados->>'parcela', '')::numeric else cur.parcela end;
  v.primeiro_venc := case when p_dados ? 'primeiro_venc' then nullif(p_dados->>'primeiro_venc', '')::date else cur.primeiro_venc end;
  v.n_parcelas := case when p_dados ? 'n_parcelas' then nullif(p_dados->>'n_parcelas', '')::int else cur.n_parcelas end;
  v.modo := case when p_dados ? 'modo' then p_dados->>'modo' else cur.modo end;
  v.santri_cadastro := case when p_dados ? 'santri_cadastro' then nullif(trim(p_dados->>'santri_cadastro'), '') else cur.santri_cadastro end;
  v.santri_plano := case when p_dados ? 'santri_plano' then nullif(trim(p_dados->>'santri_plano'), '') else cur.santri_plano end;
  v.santri_doc_prefixo := case when p_dados ? 'santri_doc_prefixo' then nullif(trim(p_dados->>'santri_doc_prefixo'), '') else cur.santri_doc_prefixo end;
  v.obs := case when p_dados ? 'obs' then nullif(trim(p_dados->>'obs'), '') else cur.obs end;
  v.ativo := case when p_dados ? 'ativo' then coalesce((p_dados->>'ativo')::boolean, true) else coalesce(cur.ativo, true) end;

  if v.credor is null then raise exception 'Informe o credor'; end if;
  if v.tipo is null or v.tipo not in ('banco','imposto','socio','entre_lojas','chapadao','outro') then raise exception 'Tipo inválido'; end if;
  if v.loja_id is null or not (v.loja_id = any(interno.lojas_tela(0::smallint))) then raise exception 'Loja sem permissão'; end if;
  if v.tipo = 'entre_lojas' then
    if v.outra_loja is null or v.outra_loja = v.loja_id then raise exception 'Entre lojas precisa da outra loja'; end if;
  else
    v.outra_loja := null;
  end if;
  if v.modo is null or v.modo not in ('fixas','santri') then raise exception 'Modo inválido'; end if;
  if v.modo = 'fixas' and (v.parcela is null or v.primeiro_venc is null or coalesce(v.n_parcelas, 0) < 1) then
    raise exception 'Informe parcela, 1º vencimento e número de parcelas';
  end if;
  if v.modo = 'santri' and v.santri_cadastro is null then raise exception 'Informe o código do credor no Santri'; end if;

  if p_id is null then
    insert into public.dividas (credor, tipo, loja_id, outra_loja, valor_original, saldo_informado, saldo_data, taxa_mes, parcela, primeiro_venc, n_parcelas,
                                modo, santri_cadastro, santri_plano, santri_doc_prefixo, obs, ativo, atualizado_por, atualizado_em)
    values (v.credor, v.tipo, v.loja_id, v.outra_loja, v.valor_original, v.saldo_informado, v.saldo_data, v.taxa_mes, v.parcela, v.primeiro_venc, v.n_parcelas,
            v.modo, v.santri_cadastro, v.santri_plano, v.santri_doc_prefixo, v.obs, v.ativo, auth.uid(), now())
    returning id into v_id;
    v_regerar := v.modo = 'fixas';
  else
    v_id := p_id;
    update public.dividas set credor = v.credor, tipo = v.tipo, loja_id = v.loja_id, outra_loja = v.outra_loja, valor_original = v.valor_original,
           saldo_informado = v.saldo_informado, saldo_data = v.saldo_data, taxa_mes = v.taxa_mes, parcela = v.parcela, primeiro_venc = v.primeiro_venc,
           n_parcelas = v.n_parcelas, modo = v.modo, santri_cadastro = v.santri_cadastro, santri_plano = v.santri_plano, santri_doc_prefixo = v.santri_doc_prefixo,
           obs = v.obs, ativo = v.ativo, atualizado_por = auth.uid(), atualizado_em = now()
     where id = p_id;
    v_regerar := v.modo = 'fixas' and (cur.modo is distinct from 'fixas' or cur.parcela is distinct from v.parcela
                 or cur.primeiro_venc is distinct from v.primeiro_venc or cur.n_parcelas is distinct from v.n_parcelas);
    if v.modo = 'santri' then
      update public.dividas_parcelas set ativo = false where divida_id = v_id and ativo;
    end if;
  end if;

  if v_regerar then
    update public.dividas_parcelas set ativo = false where divida_id = v_id and ativo;
    insert into public.dividas_parcelas (divida_id, numero, vencimento, valor)
    select v_id, g, (date_trunc('month', v.primeiro_venc) + make_interval(months => g - 1))::date
                    + least(extract(day from v.primeiro_venc)::int, extract(day from (date_trunc('month', v.primeiro_venc) + make_interval(months => g) - interval '1 day'))::int) - 1,
           v.parcela
    from generate_series(1, v.n_parcelas) g;
  end if;

  insert into public.dividas_eventos (divida_id, acao, dados, por) values (v_id, case when p_id is null then 'novo' else 'editar' end, p_dados, auth.uid());
  return v_id;
end $$;

create or replace function public.salvar_cadastros_loja(p_loja smallint, p_cadastros text[])
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not interno.ve_todas_lojas() then raise exception 'Só a direção define os códigos das lojas no Santri'; end if;
  if coalesce(p_loja, 0) = 0 then raise exception 'Escolha a loja'; end if;
  insert into public.caixa_parametros (loja_id, cadastros_santri, atualizado_por, atualizado_em)
  values (p_loja, array(select distinct trim(x) from unnest(coalesce(p_cadastros, '{}')) x where nullif(trim(x), '') is not null), auth.uid(), now())
  on conflict (loja_id) do update set cadastros_santri = excluded.cadastros_santri, atualizado_por = auth.uid(), atualizado_em = now();
end $$;

revoke execute on function interno.loja_do_cadastro(text) from anon, public;
grant execute on function interno.loja_do_cadastro(text) to authenticated;
revoke execute on function interno.divida_casa(public.dividas, public.titulos_santri) from anon, public;
grant execute on function interno.divida_casa(public.dividas, public.titulos_santri) to authenticated;
revoke execute on function interno.dividas_parcelas_todas(smallint[], date) from anon, public;
grant execute on function interno.dividas_parcelas_todas(smallint[], date) to authenticated;
revoke execute on function public.salvar_divida(bigint, jsonb) from anon, public;
grant execute on function public.salvar_divida(bigint, jsonb) to authenticated;
revoke execute on function public.salvar_cadastros_loja(smallint, text[]) from anon, public;
grant execute on function public.salvar_cadastros_loja(smallint, text[]) to authenticated;
