-- Migration 29 · entradas: reposição de quebra/garantia (CFOP x.949) e compra para estoque (revenda sem pedido de compra)
-- Regra do Bruno (16/10): nota de revenda que entra sem nada vinculado é compra para estoque (normal em Sika/Portokoll;
-- acontece em Portinari/Ceusa). Reposição de quebra/garantia vem da fábrica sem financeiro, com CFOP x.949.

create or replace function interno.tipo_entrada(p_cfop text, p_obs text) returns text
language sql immutable set search_path to '' as $$
  select case
    when p_cfop ~ '^\d\.(102|403|405)' then 'revenda'
    when p_cfop ~ '^\d\.(556|407|551|406)' then 'uso_consumo'
    when p_cfop ~ '^\d\.(910|911)' then 'amostra_bonificacao'
    when p_cfop ~ '^\d\.949' and coalesce(p_obs,'') ~* '(amostr|amosttr|brinde|bonif)' and coalesce(p_obs,'') !~* '(quebr|repos|garant|avari|defeit)' then 'amostra_bonificacao'
    when p_cfop ~ '^\d\.949' then 'reposicao'
    else 'outras' end
$$;
create or replace function interno.tipo_entrada(p_cfop text) returns text
language sql immutable set search_path to '' as $$ select interno.tipo_entrada(p_cfop, null) $$;

create or replace function public.previa_importacao_entradas(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
declare r jsonb;
begin
  if not interno.pode_importar('entradas') then raise exception 'Sem permissão para importar entradas'; end if;
  with s as (
    select (d->>'loja_id')::smallint loja_id, d->>'entrada' entrada, d->>'status' status, interno.tipo_entrada(d->>'cfop', d->>'observacao') tipo, d->>'fornecedor_nome' forn,
           (d->>'data_cadastro')::date dc, coalesce((d->>'valor_nota')::numeric,0) vn, coalesce((d->>'frete_conhec')::numeric,0) fr,
           jsonb_array_length(coalesce(d->'compras','[]'::jsonb)) ncompras, jsonb_array_length(coalesce(d->'itens','[]'::jsonb)) nitens,
           nullif(d->>'cte_numero','') cte, interno.assinatura_entrada(d) sig, d
    from (select dados d from public.entradas_staging where importacao_id = p_importacao) z),
  j as (select s.*, e.id eid, e.assinatura esig, e.status estatus from s
        left join public.entradas_santri e on e.loja_id = s.loja_id and e.entrada = s.entrada),
  cmp as (select s.loja_id, c->>'numero' numero from s, jsonb_array_elements(coalesce(s.d->'compras','[]'::jsonb)) c)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'itens', (select coalesce(sum(nitens),0) from s),
    'valor_notas', (select coalesce(sum(vn),0) from s),
    'frete_cte', (select coalesce(sum(fr),0) from s),
    'revenda', (select count(*) from s where tipo = 'revenda'),
    'uso_consumo', (select count(*) from s where tipo = 'uso_consumo'),
    'amostra_bonificacao', (select count(*) from s where tipo = 'amostra_bonificacao'),
    'outras', (select count(*) from s where tipo = 'outras'),
    'abertas', (select count(*) from s where status = 'Aberta'),
    'baixadas', (select count(*) from s where status = 'Baixada'),
    'reposicao', (select count(*) from s where tipo = 'reposicao'),
    'reposicao_valor', (select coalesce(sum(vn),0) from s where tipo = 'reposicao'),
    'reposicao_frete', (select coalesce(sum(fr),0) from s where tipo = 'reposicao'),
    -- revenda sem pedido de compra ligado = compra para estoque (normal em argamassas; acontece em revestimento)
    'estoque', (select count(*) from s where tipo = 'revenda' and ncompras = 0),
    'estoque_valor', (select coalesce(sum(vn),0) from s where tipo = 'revenda' and ncompras = 0),
    'estoque_fornecedores', (select coalesce(jsonb_agg(f order by (f->>'valor')::numeric desc),'[]'::jsonb) from (
        select jsonb_build_object('nome', forn, 'notas', count(*), 'valor', sum(vn)) f
        from s where tipo = 'revenda' and ncompras = 0 group by forn order by sum(vn) desc limit 8) z),
    'compras_ligadas', (select count(distinct (loja_id, numero)) from cmp),
    'compras_fora_do_sistema', (select count(distinct (cmp.loja_id, cmp.numero)) from cmp where not exists
        (select 1 from public.compras_santri c where c.loja_id = cmp.loja_id and c.numero = cmp.numero)),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(dc) from s), 'ate', (select max(dc) from s),
    'novos', (select count(*) from j where eid is null),
    'alterados', (select count(*) from j where eid is not null and esig is distinct from sig),
    'iguais', (select count(*) from j where eid is not null and esig = sig),
    'baixadas_agora', (select count(*) from j where eid is not null and estatus is distinct from status and status = 'Baixada')
  ) into r;
  return r;
end $$;


-- aplicar: passa a observação para a classificação (troca feita por bloco DO no texto da função)
do $$ declare f text; begin
  f := pg_get_functiondef('public.aplicar_importacao_entradas(bigint)'::regprocedure);
  if position('interno.tipo_entrada(d->>''cfop'')' in f) = 0 then raise exception 'trecho não encontrado'; end if;
  f := replace(f, 'interno.tipo_entrada(d->>''cfop'')', 'interno.tipo_entrada(d->>''cfop'', d->>''observacao'')');
  execute f;
end $$;

-- reclassifica o que já foi importado
update public.entradas_santri set tipo = interno.tipo_entrada(cfop, observacao), atualizado_em = now()
 where tipo is distinct from interno.tipo_entrada(cfop, observacao);
