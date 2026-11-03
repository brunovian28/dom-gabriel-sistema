-- Migration 54: renegociado vira contrato com parcelas (F2 Caixa, plano 3)
-- "Renegociado" deixa de ser uma data: renegociar_titulos cria um contrato (origem renegociacao) com N parcelas a partir dos títulos marcados.
-- Os títulos antigos saem da projeção (continuam aparecendo no atrasado, com a decisão) e as parcelas entram. Desativar o contrato devolve os títulos para a diretoria.

alter table public.titulos_tratativa add column if not exists divida_id bigint references public.dividas(id);
alter table public.titulos_tratativa_eventos add column if not exists divida_id bigint references public.dividas(id);

create or replace function public.renegociar_titulos(p_ids bigint[], p_dados jsonb)
returns bigint language plpgsql security definer set search_path to '' as $$
declare
  v_ids bigint[]; v_hoje date := (now() at time zone 'America/Cuiaba')::date; v_n int; v_lojas int; v_nao_pagar int; v_ja int; v_abertos int;
  v_saldo numeric; v_cad text; v_nome text; v_loja smallint; v_d bigint; v_pv date; v_nota text;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Só o financeiro e a direção renegociam títulos'; end if;
  select array_agg(distinct x) into v_ids from unnest(p_ids) x where x is not null;
  if v_ids is null then raise exception 'Escolha ao menos um título'; end if;
  select count(*), count(distinct t.loja_id), count(*) filter (where t.lado <> 'pagar'), min(t.loja_id)
    into v_n, v_lojas, v_nao_pagar, v_loja
    from public.titulos_santri t where t.id = any(v_ids) and t.loja_id = any(interno.lojas_tela(0::smallint));
  if v_n <> array_length(v_ids, 1) then raise exception 'Título não encontrado ou de outra loja'; end if;
  if v_nao_pagar > 0 then raise exception 'Só contas a pagar'; end if;
  if v_lojas > 1 then raise exception 'Títulos de lojas diferentes'; end if;
  select count(*) into v_ja from public.titulos_tratativa tr where tr.titulo_id = any(v_ids) and tr.decisao = 'renegociado';
  if v_ja > 0 then raise exception 'Título já renegociado'; end if;
  select count(*), sum(a.saldo_aberto) into v_abertos, v_saldo
    from interno.titulos_aberto('pagar', v_hoje) a where a.titulo_id = any(v_ids) and a.status <> 'pago' and a.saldo_aberto > 0;
  if v_abertos <> array_length(v_ids, 1) then raise exception 'Só títulos vencidos ou em aberto'; end if;
  select case when count(distinct t.cadastro_codigo) = 1 then min(t.cadastro_codigo) end into v_cad from public.titulos_santri t where t.id = any(v_ids);
  select t.nome into v_nome from public.titulos_santri t where t.id = any(v_ids) order by t.saldo desc nulls last, t.id limit 1;
  v_pv := nullif(p_dados->>'primeiro_venc', '')::date;
  v_nota := nullif(trim(p_dados->>'nota'), '');

  v_d := public.salvar_divida(null, jsonb_build_object(
    'credor', coalesce(nullif(trim(p_dados->>'credor'), ''), v_nome), 'tipo', coalesce(nullif(p_dados->>'tipo', ''), 'outro'), 'loja_id', v_loja,
    'modo', 'fixas', 'parcela', p_dados->'parcela', 'primeiro_venc', p_dados->'primeiro_venc', 'n_parcelas', p_dados->'n_parcelas',
    'taxa_mes', p_dados->'taxa_mes', 'saldo_informado', v_saldo, 'saldo_data', v_hoje, 'santri_cadastro', v_cad, 'obs', v_nota));
  update public.dividas set origem = 'renegociacao' where id = v_d;

  insert into public.titulos_tratativa (titulo_id, decisao, nova_data, nota, por, em, divida_id)
  select x, 'renegociado', v_pv, v_nota, auth.uid(), now(), v_d from unnest(v_ids) x
  on conflict (titulo_id) do update
    set decisao = excluded.decisao, nova_data = excluded.nova_data, nota = excluded.nota, por = excluded.por, em = excluded.em, divida_id = excluded.divida_id;
  insert into public.titulos_tratativa_eventos (titulo_id, decisao, nova_data, nota, por, divida_id)
  select x, 'renegociado', v_pv, v_nota, auth.uid(), v_d from unnest(v_ids) x;
  return v_d;
end $$;

-- Mesma assinatura de antes: renegociado só por renegociar_titulos, e título renegociado não troca de decisão sem desativar o contrato
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
  if p_decisao = 'renegociado' then raise exception 'Use Renegociar, que cria as parcelas'; end if;
  select count(*) into v_achados from public.titulos_santri t
   where t.id = any(v_ids) and t.loja_id = any(interno.lojas_tela(0::smallint));
  if v_achados <> array_length(v_ids, 1) then raise exception 'Título não encontrado ou de outra loja'; end if;
  if exists (select 1 from public.titulos_tratativa tr join public.dividas dv on dv.id = tr.divida_id
              where tr.titulo_id = any(v_ids) and tr.decisao = 'renegociado' and dv.ativo) then
    raise exception 'Título renegociado: desative o contrato na aba Dívidas';
  end if;
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
    set decisao = excluded.decisao, nova_data = excluded.nova_data, nota = excluded.nota, por = excluded.por, em = excluded.em, divida_id = null;
  get diagnostics v_n = row_count;
  insert into public.titulos_tratativa_eventos (titulo_id, decisao, nova_data, nota, por)
  select x, p_decisao, p_nova_data, nullif(trim(p_nota),''), auth.uid() from unnest(v_ids) x;
  return v_n;
end $$;

-- Mesma assinatura da migration 52: ao desativar um contrato de renegociação, os títulos voltam para a diretoria
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
    if cur.ativo and not v.ativo and cur.origem = 'renegociacao' then
      -- contrato de renegociação desativado: os títulos voltam para a diretoria (e para a semana 0 do caixa)
      insert into public.titulos_tratativa_eventos (titulo_id, decisao, nova_data, nota, por, divida_id)
      select tr.titulo_id, 'para_diretoria', null, 'contrato de renegociação desativado', auth.uid(), v_id
        from public.titulos_tratativa tr where tr.divida_id = v_id and tr.decisao = 'renegociado';
      update public.titulos_tratativa set decisao = 'para_diretoria', nova_data = null, nota = 'contrato de renegociação desativado', por = auth.uid(), em = now()
       where divida_id = v_id and decisao = 'renegociado';
    end if;
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

-- Mesma assinatura da migration 53: título renegociado (com contrato ativo) não entra na projeção, as parcelas entram
create or replace function interno.caixa_lancado(p_lojas smallint[], p_hoje date, p_atrasados text)
returns table(loja_id smallint, data date, grupo text, valor numeric, origem text, titulo_id bigint, vencido boolean, descricao text)
language sql stable security definer set search_path to '' as $$
  with st as (
    select s.titulo_id, s.loja_id, s.status, s.dias_atraso, s.saldo_aberto, 'pagar'::text lado from interno.titulos_aberto('pagar', p_hoje) s
    union all
    select s.titulo_id, s.loja_id, s.status, s.dias_atraso, s.saldo_aberto, 'receber'::text from interno.titulos_aberto('receber', p_hoje) s
  ), b as (
    select t.id, st.lado, t.loja_id, t.vencimento, st.saldo_aberto saldo, t.tipo, t.plano_codigo, t.plano_nome,
           st.status, st.dias_atraso, tr.decisao, tr.nova_data,
           coalesce(interno.loja_do_cadastro(t.cadastro_codigo) <> t.loja_id, false) entre_lojas
    from st
    join public.titulos_santri t on t.id = st.titulo_id
    left join public.titulos_tratativa tr on tr.titulo_id = t.id
    where st.loja_id = any(p_lojas) and st.status <> 'pago' and st.saldo_aberto > 0
      and not (tr.decisao = 'renegociado' and exists (select 1 from public.dividas dv where dv.id = tr.divida_id and dv.ativo))
  ), m as (
    select b.loja_id,
           case when b.status = 'aberto' then coalesce(b.vencimento, p_hoje)
                when b.decisao = 'nao_e_divida' then null
                when p_atrasados = 'pagar_tudo' then p_hoje
                when b.decisao in ('pagar_em','renegociado') then greatest(b.nova_data, p_hoje)
                when b.decisao = 'em_disputa' then null
                else p_hoje end data,
           case when b.entre_lojas then 'entre_lojas' else interno.grupo_caixa(b.plano_codigo, b.plano_nome) end grupo,
           -b.saldo valor, b.id titulo_id, b.status = 'vencido' vencido
    from b
    where b.lado = 'pagar' and coalesce(b.tipo, '') not in ('Pre','Cre','Adi')
    union all
    select b.loja_id,
           case when b.status = 'aberto' then b.vencimento
                when b.decisao = 'perdido' then null
                when b.decisao = 'prometeu' then greatest(b.nova_data, p_hoje)
                when b.dias_atraso <= 60 then p_hoje + 7
                else null end,
           case when interno.categoria_receber(b.tipo, b.plano_nome) in ('clientes','venda_direta') then 'clientes' else 'outros_entrada' end,
           b.saldo, b.id, b.status = 'vencido'
    from b
    where b.lado = 'receber' and coalesce(b.tipo, '') !~* '^(cart|cr.dito|adiant|previs)'
      and interno.categoria_receber(b.tipo, b.plano_nome) <> 'credito_fornecedor'
      and not b.entre_lojas
  )
  select m.loja_id, m.data, m.grupo, m.valor, 'lancado'::text, m.titulo_id, m.vencido, null::text
  from m
  where m.data is not null and m.grupo <> 'fora'
$$;

revoke execute on function public.renegociar_titulos(bigint[], jsonb) from anon, public;
grant execute on function public.renegociar_titulos(bigint[], jsonb) to authenticated;
