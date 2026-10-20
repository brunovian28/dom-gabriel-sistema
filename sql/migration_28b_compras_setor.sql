-- Migration 28b · compras: importação liberada por setor (security definer + interno.pode_importar)
-- ---------- prévia ----------
create or replace function public.previa_importacao_compras(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.pode_importar('compras') then raise exception 'Sem permissão para importar compras'; end if;
  with s as (
    select (d->>'loja_id')::smallint loja_id, d->>'numero' numero, d->>'status' status,
           (d->>'data_cadastro')::date dc, coalesce((d->>'valor_pedido')::numeric,0) vp,
           coalesce((d->>'valor_pendencias')::numeric,0) vpend, interno.assinatura_compra(d) sig, d
    from (select dados d from public.compras_staging where importacao_id = p_importacao) z),
  j as (select s.*, c.id cid, c.assinatura csig, c.status cstatus from s
        left join public.compras_santri c on c.loja_id = s.loja_id and c.numero = s.numero),
  it as (select distinct i->>'codigo' cod from s, jsonb_array_elements(coalesce(s.d->'itens','[]'::jsonb)) i)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'itens', (select count(*) from s, jsonb_array_elements(coalesce(s.d->'itens','[]'::jsonb))),
    'valor_pedidos', (select coalesce(sum(vp),0) from s where status <> 'Cancelado'),
    'abertas', (select count(*) from s where status = 'Aberto'),
    'valor_pendente', (select coalesce(sum(vpend),0) from s where status = 'Aberto'),
    'baixadas', (select count(*) from s where status = 'Baixado'),
    'canceladas', (select count(*) from s where status = 'Cancelado'),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(dc) from s), 'ate', (select max(dc) from s),
    'novos', (select count(*) from j where cid is null),
    'alterados', (select count(*) from j where cid is not null and csig is distinct from sig),
    'iguais', (select count(*) from j where cid is not null and csig = sig),
    'mudaram_status', (select count(*) from j where cid is not null and cstatus is distinct from status),
    'produtos_sem_cadastro', (select count(*) from it where cod !~ '^\d+$' or not exists (select 1 from public.produtos p where p.id = it.cod::bigint))
  ) into r;
  return r;
end $$;

-- ---------- aplicar ----------
create or replace function public.aplicar_importacao_compras(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
declare res jsonb; d jsonb; cid bigint; sig text; old public.compras_santri%rowtype;
  o_ent numeric; o_saldo numeric; n_ent numeric; n_saldo numeric;
  n_novos int := 0; n_alt int := 0; n_iguais int := 0;
begin
  if not interno.pode_importar('compras') then raise exception 'Sem permissão para importar compras'; end if;
  res := public.previa_importacao_compras(p_importacao);
  for d in select dados from public.compras_staging where importacao_id = p_importacao order by id loop
    sig := interno.assinatura_compra(d); old := null; o_ent := null; o_saldo := null;
    select * into old from public.compras_santri where loja_id = (d->>'loja_id')::smallint and numero = d->>'numero';
    if old.id is not null then
      select coalesce(sum(entregues),0), coalesce(sum(saldo_pendente),0) into o_ent, o_saldo
        from public.compras_santri_itens where compra_id = old.id and ativo;
    end if;
    if old.id is null then n_novos := n_novos + 1;
    elsif old.assinatura is distinct from sig then n_alt := n_alt + 1;
    else n_iguais := n_iguais + 1; continue; end if;

    insert into public.compras_santri as c (loja_id, numero, fornecedor_codigo, fornecedor_nome, status, tipo_compra, comprador,
      data_cadastro, data_fatura, prev_entrega, data_baixa, media_prazo, xml_pendente, entrada_realizada, bloqueada, confirmada,
      conf_gerencia, ped_venda_vinculado, pedidos_venda, total_bruto, desconto_comercial, desconto, total_st, outras_despesas,
      total_frete, total_ipi, valor_pedido, total_peso, qtd_produtos, qtd_itens, qtd_itens_pendentes, valor_pendencias,
      fornecedor_integracao, enviada_integradora, nr_pedido_fornecedor, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'numero', d->>'fornecedor_codigo', d->>'fornecedor_nome', d->>'status', d->>'tipo_compra',
      d->>'comprador', (d->>'data_cadastro')::date, (d->>'data_fatura')::date, (d->>'prev_entrega')::date, (d->>'data_baixa')::date,
      (d->>'media_prazo')::numeric, coalesce((d->>'xml_pendente')::boolean,false), coalesce((d->>'entrada_realizada')::boolean,false),
      coalesce((d->>'bloqueada')::boolean,false), coalesce((d->>'confirmada')::boolean,false), coalesce((d->>'conf_gerencia')::boolean,false),
      coalesce((d->>'ped_venda_vinculado')::boolean,false), nullif(d->>'pedidos_venda',''),
      (d->>'total_bruto')::numeric, (d->>'desconto_comercial')::numeric, (d->>'desconto')::numeric, (d->>'total_st')::numeric,
      (d->>'outras_despesas')::numeric, (d->>'total_frete')::numeric, (d->>'total_ipi')::numeric, (d->>'valor_pedido')::numeric,
      (d->>'total_peso')::numeric, (d->>'qtd_produtos')::numeric, (d->>'qtd_itens')::numeric, (d->>'qtd_itens_pendentes')::numeric,
      (d->>'valor_pendencias')::numeric, nullif(d->>'fornecedor_integracao',''), coalesce((d->>'enviada_integradora')::boolean,false),
      nullif(d->>'nr_pedido_fornecedor',''), sig, p_importacao, p_importacao)
    on conflict (loja_id, numero) do update set
      fornecedor_codigo = excluded.fornecedor_codigo, fornecedor_nome = excluded.fornecedor_nome, status = excluded.status,
      tipo_compra = excluded.tipo_compra, comprador = excluded.comprador, data_cadastro = excluded.data_cadastro,
      data_fatura = excluded.data_fatura, prev_entrega = excluded.prev_entrega, data_baixa = excluded.data_baixa,
      media_prazo = excluded.media_prazo, xml_pendente = excluded.xml_pendente, entrada_realizada = excluded.entrada_realizada,
      bloqueada = excluded.bloqueada, confirmada = excluded.confirmada, conf_gerencia = excluded.conf_gerencia,
      ped_venda_vinculado = excluded.ped_venda_vinculado, pedidos_venda = coalesce(excluded.pedidos_venda, c.pedidos_venda),
      total_bruto = excluded.total_bruto, desconto_comercial = excluded.desconto_comercial, desconto = excluded.desconto,
      total_st = excluded.total_st, outras_despesas = excluded.outras_despesas, total_frete = excluded.total_frete,
      total_ipi = excluded.total_ipi, valor_pedido = excluded.valor_pedido, total_peso = excluded.total_peso,
      qtd_produtos = excluded.qtd_produtos, qtd_itens = excluded.qtd_itens, qtd_itens_pendentes = excluded.qtd_itens_pendentes,
      valor_pendencias = excluded.valor_pendencias, fornecedor_integracao = excluded.fornecedor_integracao,
      enviada_integradora = excluded.enviada_integradora, nr_pedido_fornecedor = excluded.nr_pedido_fornecedor,
      assinatura = excluded.assinatura, importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into cid;

    insert into public.compras_santri_itens as t (compra_id, ordem, produto_id, codigo, nome, unidade, prev_entrega, quantidade,
      em_analise_xml, em_entrada, entregues, canceladas, saldo_pendente, preco, total_bruto, pct_desc, outras_despesas,
      total_liquido, cod_original, marca, valor_st, ativo)
    select cid, (i->>'ordem')::int,
      (select p.id from public.produtos p where (i->>'codigo') ~ '^\d+$' and p.id = (i->>'codigo')::bigint),
      i->>'codigo', i->>'nome', i->>'unidade', (i->>'prev_entrega')::date, (i->>'quantidade')::numeric,
      (i->>'em_analise_xml')::numeric, (i->>'em_entrada')::numeric, (i->>'entregues')::numeric, (i->>'canceladas')::numeric,
      (i->>'saldo_pendente')::numeric, (i->>'preco')::numeric, (i->>'total_bruto')::numeric, (i->>'pct_desc')::numeric,
      (i->>'outras_despesas')::numeric, (i->>'total_liquido')::numeric, i->>'cod_original', i->>'marca', (i->>'valor_st')::numeric, true
    from jsonb_array_elements(coalesce(d->'itens','[]'::jsonb)) i
    on conflict (compra_id, ordem) do update set
      produto_id = excluded.produto_id, codigo = excluded.codigo, nome = excluded.nome, unidade = excluded.unidade,
      prev_entrega = excluded.prev_entrega, quantidade = excluded.quantidade, em_analise_xml = excluded.em_analise_xml,
      em_entrada = excluded.em_entrada, entregues = excluded.entregues, canceladas = excluded.canceladas,
      saldo_pendente = excluded.saldo_pendente, preco = excluded.preco, total_bruto = excluded.total_bruto,
      pct_desc = excluded.pct_desc, outras_despesas = excluded.outras_despesas, total_liquido = excluded.total_liquido,
      cod_original = excluded.cod_original, marca = excluded.marca, valor_st = excluded.valor_st, ativo = true;
    -- item que saiu da compra no Santri fica guardado como inativo
    update public.compras_santri_itens set ativo = false
     where compra_id = cid and ativo and ordem > jsonb_array_length(coalesce(d->'itens','[]'::jsonb));

    -- histórico
    select coalesce(sum(entregues),0), coalesce(sum(saldo_pendente),0) into n_ent, n_saldo
      from public.compras_santri_itens where compra_id = cid and ativo;
    if old.id is null then
      insert into public.compras_santri_eventos (compra_id, importacao_id, campo, de, para)
      values (cid, p_importacao, 'status', null, d->>'status');
    else
      insert into public.compras_santri_eventos (compra_id, importacao_id, campo, de, para)
      select cid, p_importacao, x.campo, x.de, x.para from (values
        ('status', old.status, d->>'status'),
        ('data_baixa', old.data_baixa::text, d->>'data_baixa'),
        ('prev_entrega', old.prev_entrega::text, d->>'prev_entrega'),
        ('nr_pedido_fornecedor', old.nr_pedido_fornecedor, nullif(d->>'nr_pedido_fornecedor','')),
        ('valor_pedido', old.valor_pedido::text, (d->>'valor_pedido')::numeric::text),
        ('entregues', o_ent::text, n_ent::text),
        ('saldo_pendente', o_saldo::text, n_saldo::text)
      ) x(campo, de, para) where x.de is distinct from x.para;
    end if;
  end loop;
  -- a área de espera (compras_staging) é limpa pela Importadora depois de gravar
  res := res || jsonb_build_object('novos', n_novos, 'alterados', n_alt, 'iguais', n_iguais);
  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;

