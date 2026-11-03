-- Migration 56: revisão do plano 3 da F2 (dívidas). Mesmas assinaturas das migrations 52 e 54.
-- 1. Parcela de renegociação só liga a título do Santri de valor parecido (até 2% ou R$ 1). Antes, qualquer compra nova do mesmo fornecedor
--    no mês fazia a parcela sumir do caixa.
-- 2. Contrato de renegociação desativado não pode ser reativado (os títulos já voltaram para a diretoria, contaria em dobro).
-- 3. Editar contrato exige permissão na loja atual do contrato (antes só checava a loja nova).
-- 4. Renegociar títulos cujo credor é a outra loja cria contrato entre lojas (some no Total, espelha na loja credora).

create or replace function interno.dividas_parcelas_todas(p_lojas smallint[], p_hoje date)
returns table(divida_id bigint, loja_id smallint, numero int, n_total int, vencimento date, valor numeric, titulo_id bigint, no_santri boolean)
language sql stable security definer set search_path to '' as $$
  with ut as (
    select interno.titulos_ultima_importacao('pagar') id
  ), f as (
    select p.divida_id, d.loja_id, p.numero, (count(*) over (partition by p.divida_id))::int n_total, p.vencimento, p.valor,
           (select min(t.id) from public.titulos_santri t, ut
             where t.ultima_importacao_id = ut.id and t.lado = 'pagar' and t.loja_id = d.loja_id and t.cadastro_codigo = d.santri_cadastro
               and interno.divida_casa(d, t) and date_trunc('month', t.vencimento) = date_trunc('month', p.vencimento)
               and (d.origem <> 'renegociacao' or abs(t.valor_documento - p.valor) <= greatest(1, 0.02 * p.valor))) tid
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

create or replace function public.salvar_divida(p_id bigint, p_dados jsonb)
returns bigint language plpgsql security definer set search_path to '' as $$
declare
  cur public.dividas; v public.dividas; v_id bigint; v_regerar boolean := false;
begin
  if not interno.pode_ver_financeiro() then raise exception 'Loja sem permissão'; end if;
  if p_id is not null then
    select * into cur from public.dividas where id = p_id;
    if not found then raise exception 'Contrato não encontrado'; end if;
    if not (cur.loja_id = any(interno.lojas_tela(0::smallint))) then raise exception 'Loja sem permissão'; end if;
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

  if p_id is not null and cur.origem = 'renegociacao' and not cur.ativo and v.ativo then
    raise exception 'Contrato de renegociação desativado não volta: renegocie os títulos de novo';
  end if;
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

create or replace function public.renegociar_titulos(p_ids bigint[], p_dados jsonb)
returns bigint language plpgsql security definer set search_path to '' as $$
declare
  v_ids bigint[]; v_hoje date := (now() at time zone 'America/Cuiaba')::date; v_n int; v_lojas int; v_nao_pagar int; v_ja int; v_abertos int;
  v_saldo numeric; v_cad text; v_nome text; v_loja smallint; v_outra smallint; v_tipo text; v_d bigint; v_pv date; v_nota text;
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
  -- credor é a outra loja: o contrato é entre lojas
  v_outra := interno.loja_do_cadastro(v_cad);
  if v_outra is not null and v_outra <> v_loja then v_tipo := 'entre_lojas'; else v_outra := null; v_tipo := coalesce(nullif(p_dados->>'tipo', ''), 'outro'); end if;

  v_d := public.salvar_divida(null, jsonb_build_object(
    'credor', coalesce(nullif(trim(p_dados->>'credor'), ''), v_nome), 'tipo', v_tipo, 'loja_id', v_loja, 'outra_loja', v_outra,
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
