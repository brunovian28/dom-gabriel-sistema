-- Migration 59: datas do pedido no sistema (previsao de entrega e data que o cliente precisa), com historico.
-- Escrita so pelas RPCs. Plano: docs/superpowers/plans/2026-11-03-pedidos-automaticos.md

create table if not exists public.pedido_datas (
  loja_id smallint not null references public.lojas(id),
  numero text not null,
  previsao_entrega date,
  data_cliente_precisa date,
  atualizado_por uuid references public.usuarios(id),
  atualizado_em timestamptz not null default now(),
  primary key (loja_id, numero)
);

create table if not exists public.pedido_datas_eventos (
  id bigint generated always as identity primary key,
  loja_id smallint not null references public.lojas(id),
  numero text not null,
  campo text not null check (campo in ('previsao_entrega','data_cliente_precisa')),
  de date,
  para date,
  por uuid references public.usuarios(id),
  em timestamptz not null default now()
);
create index if not exists pedido_datas_eventos_pedido_idx on public.pedido_datas_eventos (loja_id, numero, em);

alter table public.pedido_datas enable row level security;
alter table public.pedido_datas_eventos enable row level security;

create policy pedido_datas_ler on public.pedido_datas for select to authenticated
  using ((select interno.e_ativo()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));
create policy pedido_datas_eventos_ler on public.pedido_datas_eventos for select to authenticated
  using ((select interno.e_ativo()) and ((select interno.le_todas_lojas()) or loja_id = (select interno.minha_loja())));

create or replace function public.salvar_datas_pedido(p_loja smallint, p_numero text, p_previsao date, p_precisa date)
returns void language plpgsql security definer set search_path to '' as $f$
#variable_conflict use_column
declare
  v_papel text; v_nome text; v_uid uuid := (select auth.uid());
  v_vend text; v_existe boolean;
  v_prev_ant date; v_prec_ant date; v_tinha boolean;
begin
  select u.papel, nullif(upper(trim(u.nome_santri)), '') into v_papel, v_nome
    from public.usuarios u where u.id = v_uid and u.ativo;
  if v_papel is null or v_papel not in ('gerente','logistica','direcao','admin','vendedor') then
    raise exception 'Sem permissão para alterar datas';
  end if;
  if coalesce(p_loja, 0) = 0 then raise exception 'Informe a loja'; end if;
  perform interno.lojas_tela(p_loja);
  p_numero := trim(p_numero);
  select true, upper(trim(v.vendedor_santri)) into v_existe, v_vend
    from public.vendas_santri v
    where v.loja_id = p_loja and v.numero = p_numero and v.tipo = 'PED'
    order by v.id limit 1;
  if not coalesce(v_existe, false) then raise exception 'Pedido não encontrado no Santri'; end if;
  if v_papel = 'vendedor' and v_nome is not null and v_vend is distinct from v_nome then
    raise exception 'Pedido de outro vendedor';
  end if;

  select d.previsao_entrega, d.data_cliente_precisa, true into v_prev_ant, v_prec_ant, v_tinha
    from public.pedido_datas d where d.loja_id = p_loja and d.numero = p_numero for update;

  insert into public.pedido_datas(loja_id, numero, previsao_entrega, data_cliente_precisa, atualizado_por, atualizado_em)
  values (p_loja, p_numero, p_previsao, p_precisa, v_uid, now())
  on conflict (loja_id, numero) do update
    set previsao_entrega = excluded.previsao_entrega, data_cliente_precisa = excluded.data_cliente_precisa,
        atualizado_por = excluded.atualizado_por, atualizado_em = excluded.atualizado_em;

  if p_previsao is distinct from v_prev_ant then
    insert into public.pedido_datas_eventos(loja_id, numero, campo, de, para, por)
    values (p_loja, p_numero, 'previsao_entrega', v_prev_ant, p_previsao, v_uid);
  end if;
  if p_precisa is distinct from v_prec_ant then
    insert into public.pedido_datas_eventos(loja_id, numero, campo, de, para, por)
    values (p_loja, p_numero, 'data_cliente_precisa', v_prec_ant, p_precisa, v_uid);
  end if;
end $f$;

create or replace function public.dados_lancar_pedido(p_loja smallint, p_numero text)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
#variable_conflict use_column
declare
  v_sis date; v_prec date; v_san date; v_formas text;
begin
  if coalesce(p_loja, 0) = 0 then raise exception 'Informe a loja'; end if;
  perform interno.lojas_tela(p_loja);
  p_numero := trim(p_numero);
  select d.previsao_entrega, d.data_cliente_precisa into v_sis, v_prec
    from public.pedido_datas d where d.loja_id = p_loja and d.numero = p_numero;
  select max(e.prev_maior) into v_san
    from public.entregas_pendentes e
    where e.loja_id = p_loja and e.pedido = p_numero
      and e.importacao_id = (select max(x.importacao_id) from public.entregas_pendentes x);
  select pp.formas into v_formas from interno.pagamento_pedidos() pp where pp.numero = p_numero limit 1;
  return jsonb_build_object('previsao_sistema', v_sis, 'previsao_santri', v_san, 'precisa', v_prec, 'formas', v_formas);
end $f$;

revoke execute on function public.salvar_datas_pedido(smallint, text, date, date) from anon, public;
grant execute on function public.salvar_datas_pedido(smallint, text, date, date) to authenticated;
revoke execute on function public.dados_lancar_pedido(smallint, text) from anon, public;
grant execute on function public.dados_lancar_pedido(smallint, text) to authenticated;
