-- Migration 41: base comum do Controller (F1 + F2)
-- Classificação do plano de contas (grupo do caixa) e status único do título.

create table if not exists public.plano_contas_classe (
  plano_codigo text primary key,
  plano_nome text,
  grupo_caixa text not null check (grupo_caixa in ('fornecedor','pessoal','impostos','comissoes_rt','divida','fixo','outros','fora')),
  fixa boolean not null default false,
  linha_dre text,
  regra_mes text check (regra_mes in ('anterior_vencimento','emissao')),
  linha_mercado text,
  revisado boolean not null default false,
  atualizado_por uuid,
  atualizado_em timestamptz default now()
);
alter table public.plano_contas_classe enable row level security;
create policy pcc_ler on public.plano_contas_classe for select to authenticated
  using ((select interno.pode_ver_financeiro()));

create or replace function interno.grupo_caixa_padrao(p_plano_nome text)
returns text language sql immutable set search_path to '' as $$
  select case
    when upper(coalesce(p_plano_nome,'')) ~ 'PARCELAMENTO|^SIMPLES$|EMPRESTIMO|FINANCIAMENTO|CONSORCIO' then 'divida'
    when upper(coalesce(p_plano_nome,'')) ~ 'FORNECEDOR|FRETE|DESPESAS EXTRAS DE COMPRAS' then 'fornecedor'
    when upper(coalesce(p_plano_nome,'')) ~ 'COMISS|REFLEXOS? DE COMISS' then 'comissoes_rt'
    when upper(coalesce(p_plano_nome,'')) ~ 'SALARIO|FERIAS|13|RESCIS|INSS|FGTS|VALE TRANSPORTE|PRO.?LABORE|ENCARGO|PLANO DE SAUDE|ALIMENTA' then 'pessoal'
    when upper(coalesce(p_plano_nome,'')) ~ 'ICMS|COFINS|^PIS$|IMPOSTO|ISSQN|IRRF|DIFAL|TAXAS MUNICIPAIS' then 'impostos'
    else 'fixo' end
$$;

create or replace function interno.grupo_caixa(p_plano_codigo text, p_plano_nome text)
returns text language sql stable security definer set search_path to '' as $$
  select coalesce(
    (select c.grupo_caixa from public.plano_contas_classe c where c.plano_codigo = p_plano_codigo),
    interno.grupo_caixa_padrao(p_plano_nome))
$$;

create or replace function interno.status_titulo(p_situacao text, p_vencimento date, p_pago_por_baixa boolean, p_hoje date)
returns text language sql immutable set search_path to '' as $$
  select case
    when lower(coalesce(p_situacao,'')) = 'baixado' or coalesce(p_pago_por_baixa,false) then 'pago'
    when p_vencimento is not null and p_vencimento < p_hoje then 'vencido'
    else 'aberto' end
$$;

create or replace function interno.titulos_status(p_lado text, p_hoje date)
returns table(titulo_id bigint, loja_id smallint, status text, dias_atraso int)
language sql stable security definer set search_path to '' as $$
  with b as (
    select bs.lado, bt.cod_financeiro, sum(bt.valor_baixado) pago
    from public.baixas_santri bs
    join public.baixas_santri_titulos bt on bt.baixa_id = bs.id and bt.ativo
    where bs.ativo and bs.lado = p_lado
    group by bs.lado, bt.cod_financeiro
  ), t as (
    select t.id, t.loja_id, t.situacao, t.vencimento,
           (coalesce(t.saldo,0) > 0 and coalesce(b.pago,0) >= t.saldo) pago_baixa
    from public.titulos_santri t
    left join b on b.cod_financeiro = t.codigo and b.lado = t.lado
    where t.lado = p_lado and t.ultima_importacao_id = interno.titulos_ultima_importacao(p_lado)
  )
  select t.id, t.loja_id,
         interno.status_titulo(t.situacao, t.vencimento, t.pago_baixa, p_hoje),
         case when interno.status_titulo(t.situacao, t.vencimento, t.pago_baixa, p_hoje) = 'vencido'
              then greatest(p_hoje - t.vencimento, 0) else 0 end
  from t
$$;

create or replace function public.salvar_classe_conta(p_codigo text, p_grupo text, p_fixa boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not interno.ve_todas_lojas() then raise exception 'acesso negado'; end if;
  if p_grupo is null or p_grupo not in ('fornecedor','pessoal','impostos','comissoes_rt','divida','fixo','outros','fora') then
    raise exception 'Grupo invalido';
  end if;
  update public.plano_contas_classe
     set grupo_caixa = p_grupo, fixa = coalesce(p_fixa,false), revisado = true,
         atualizado_por = auth.uid(), atualizado_em = now()
   where plano_codigo = p_codigo;
  if not found then
    insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa, fixa, revisado, atualizado_por)
    select p_codigo,
           (select t.plano_nome from public.titulos_santri t where t.lado = 'pagar' and t.plano_codigo = p_codigo order by t.atualizado_em desc limit 1),
           p_grupo, coalesce(p_fixa,false), true, auth.uid();
  end if;
end $$;

create or replace function public.lista_plano_contas()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb; hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if not interno.pode_ver_financeiro() then raise exception 'acesso negado'; end if;
  with t as (
    select t.plano_codigo, (array_agg(t.plano_nome order by t.atualizado_em desc))[1] nome,
           count(*) filter (where t.emissao >= hoje - 365) n12
    from public.titulos_santri t
    where t.lado = 'pagar' and t.plano_codigo is not null
    group by t.plano_codigo
  ), x as (
    select coalesce(c.plano_codigo, t.plano_codigo) plano_codigo,
           coalesce(c.plano_nome, t.nome) plano_nome,
           coalesce(c.grupo_caixa, interno.grupo_caixa_padrao(t.nome)) grupo_caixa,
           coalesce(c.fixa, interno.grupo_caixa_padrao(t.nome) in ('pessoal','fixo')) fixa,
           coalesce(c.revisado, false) revisado,
           coalesce(t.n12, 0)::int titulos_12m
    from public.plano_contas_classe c
    full join t on t.plano_codigo = c.plano_codigo
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.titulos_12m desc, x.plano_codigo), '[]'::jsonb) into r from x;
  return r;
end $$;

grant execute on function public.salvar_classe_conta(text,text,boolean) to authenticated;
grant execute on function public.lista_plano_contas() to authenticated;

-- Carga inicial (rascunho para revisão): nomes vêm do próprio banco
insert into public.plano_contas_classe (plano_codigo, plano_nome, grupo_caixa, fixa)
select distinct on (plano_codigo) plano_codigo, plano_nome, interno.grupo_caixa_padrao(plano_nome),
       interno.grupo_caixa_padrao(plano_nome) in ('pessoal','fixo')
from public.titulos_santri
where lado = 'pagar' and plano_codigo is not null
order by plano_codigo, atualizado_em desc
on conflict do nothing;
