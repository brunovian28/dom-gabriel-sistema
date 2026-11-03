-- Migration 65 · Notas fiscais de saída: 'sumiu' só vale para o tipo de movimento que veio no arquivo (por loja)
-- Quem exporta só Entregas e Pedido não pode desativar as 'Dev. por canc. de entrega' do período (a remessa cancelada voltaria a valer na tela Pedidos).
-- Prévia e aplicar usam o mesmo conjunto deduplicado e o mesmo critério. Também amplia o "como exportar" da rotina (filtros e dicas).

update public.relatorios_rotina set
  filtros = 'Data de emissão: da última importação até hoje (primeira vez: desde 01/01/2026) · Empresa: as duas · Tipo de movimento: todos · Deixe os outros filtros como vêm: todos os tipos de cliente, situação emitidas normalmente/DPEC/EPEC/contingência, sem canceladas',
  dicas = 'Mostra as notas que saíram de verdade, inclusive a remessa de cada entrega. Não marque notas canceladas, denegadas ou inutilizadas: o relatório não traz a situação e elas entrariam como remessas válidas. Se exportar só alguns tipos de movimento, só esses tipos são conferidos (os outros não são desativados).'
where tipo = 'notas_saida';

create or replace function public.previa_importacao_notas_saida(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $$
#variable_conflict use_column
declare r jsonb;
begin
  if not interno.pode_importar('notas_saida') then raise exception 'Sem permissão para importar notas fiscais de saída'; end if;
  if not exists (select 1 from public.importacoes i where i.id = p_importacao and i.tipo = 'notas_saida'
                 and (i.usuario_id = (select auth.uid()) or (select interno.ve_todas_lojas()))) then
    raise exception 'Importação inválida'; end if;
  with s as (
    select distinct on (loja_id, cod_nota) loja_id, cod_nota, emissao, tipo, cod_mov, sig from (
      select (d->>'loja_id')::smallint loja_id, d->>'cod_nota' cod_nota, (d->>'emissao')::date emissao, d->>'tipo_movimento' tipo,
             d->>'cod_movimento' cod_mov, interno.assinatura_nota_saida(d) sig, id
      from public.notas_saida_staging, lateral (select dados d) z where importacao_id = p_importacao) q
    order by loja_id, cod_nota, id desc),
  g as (select s.*, n.id nid, n.assinatura nsig, n.ativo nativo from s left join public.notas_saida n on n.loja_id = s.loja_id and n.cod_nota = s.cod_nota),
  per as (select loja_id, min(emissao) de, max(emissao) ate from s group by 1)
  select jsonb_build_object(
    'no_arquivo', (select count(*) from s),
    'pva', (select count(*) from s where loja_id = 1), 'rv', (select count(*) from s where loja_id = 2),
    'de', (select min(emissao) from s), 'ate', (select max(emissao) from s),
    'por_tipo', coalesce((select jsonb_object_agg(tipo, n) from (select coalesce(tipo, '') tipo, count(*) n from s group by 1) t), '{}'::jsonb),
    'novos', (select count(*) from g where nid is null),
    'alterados', (select count(*) from g where nid is not null and (nsig is distinct from sig or not nativo)),
    'iguais', (select count(*) from g where nid is not null and nsig = sig and nativo),
    'sumiram', (select count(*) from public.notas_saida n join per on per.loja_id = n.loja_id
                where n.ativo and n.emissao between per.de and per.ate
                  and n.tipo_movimento in (select s2.tipo from s s2 where s2.loja_id = n.loja_id)
                  and not exists (select 1 from s where s.loja_id = n.loja_id and s.cod_nota = n.cod_nota)),
    'remessas', (select count(*) from s where tipo in ('Entregas','Entregas agrupadas')),
    'remessas_ligadas', (select count(*) from s where tipo in ('Entregas','Entregas agrupadas')
                         and exists (select 1 from public.entregas_santri e where e.loja_id = s.loja_id and e.entrega = s.cod_mov and e.ativo)),
    'pedidos_faturados', (select count(*) from s where tipo = 'Pedido'),
    'pedidos_no_sistema', (select count(*) from s where tipo = 'Pedido'
                           and exists (select 1 from public.vendas_santri v where v.loja_id = s.loja_id and v.tipo = 'PED' and v.numero = s.cod_mov))
  ) into r;
  return r;
end $$;

create or replace function public.aplicar_importacao_notas_saida(p_importacao bigint) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '300s' as $$
#variable_conflict use_column
declare res jsonb; d jsonb; nid bigint; stt text; sig text; old public.notas_saida%rowtype;
begin
  if not interno.pode_importar('notas_saida') then raise exception 'Sem permissão para importar notas fiscais de saída'; end if;
  if not exists (select 1 from public.importacoes i where i.id = p_importacao and i.tipo = 'notas_saida'
                 and (i.usuario_id = (select auth.uid()) or (select interno.ve_todas_lojas()))) then
    raise exception 'Importação inválida'; end if;
  select i.status, i.resumo into stt, res from public.importacoes i where i.id = p_importacao for update;
  if stt = 'aplicada' and res is not null then return res; end if;
  res := public.previa_importacao_notas_saida(p_importacao);
  for d in select dados from (
      select distinct on ((dados->>'loja_id'), (dados->>'cod_nota')) dados, id from public.notas_saida_staging
      where importacao_id = p_importacao order by (dados->>'loja_id'), (dados->>'cod_nota'), id desc) q order by id loop
    sig := interno.assinatura_nota_saida(d); old := null;
    select * into old from public.notas_saida where loja_id = (d->>'loja_id')::smallint and cod_nota = d->>'cod_nota';
    if old.id is not null and old.assinatura is not distinct from sig and old.ativo then continue; end if;

    insert into public.notas_saida as n (loja_id, cod_nota, nr_nota, serie, emissao, tipo_doc, cliente_codigo, cliente_nome, valor_total, cfop,
      tipo_movimento, cod_movimento, chave_nfe, peso, usuario, observacao, ativo, assinatura, importacao_id, primeira_importacao_id)
    values ((d->>'loja_id')::smallint, d->>'cod_nota', d->>'nr_nota', d->>'serie', (d->>'emissao')::date, d->>'tipo_doc', d->>'cliente_codigo',
      d->>'cliente_nome', (d->>'valor_total')::numeric, d->>'cfop', d->>'tipo_movimento', d->>'cod_movimento', d->>'chave_nfe',
      (d->>'peso')::numeric, d->>'usuario', d->>'observacao', true, sig, p_importacao, p_importacao)
    on conflict (loja_id, cod_nota) do update set
      nr_nota = excluded.nr_nota, serie = excluded.serie, emissao = excluded.emissao, tipo_doc = excluded.tipo_doc,
      cliente_codigo = excluded.cliente_codigo, cliente_nome = excluded.cliente_nome, valor_total = excluded.valor_total, cfop = excluded.cfop,
      tipo_movimento = excluded.tipo_movimento, cod_movimento = excluded.cod_movimento, chave_nfe = excluded.chave_nfe, peso = excluded.peso,
      usuario = excluded.usuario, observacao = excluded.observacao, ativo = true, assinatura = excluded.assinatura,
      importacao_id = excluded.importacao_id, atualizado_em = now()
    returning id into nid;

    insert into public.notas_saida_eventos (nota_id, importacao_id, evento, antes)
    values (nid, p_importacao,
      case when old.id is null then 'novo' when not old.ativo then 'voltou' else 'alterou' end,
      case when old.id is null then null else to_jsonb(old) end);
  end loop;

  -- notas ativas no período de emissão do arquivo (por loja) que não vieram mais: canceladas/excluídas no Santri
  -- mesmo conjunto deduplicado da prévia (última linha de cada loja + cod_nota vence)
  with s as (select distinct on (dados->>'loja_id', dados->>'cod_nota') (dados->>'loja_id')::smallint loja_id, dados->>'cod_nota' cod_nota,
                    (dados->>'emissao')::date emissao,
                    dados->>'tipo_movimento' tipo_movimento
             from public.notas_saida_staging where importacao_id = p_importacao
             order by dados->>'loja_id', dados->>'cod_nota', id desc),
       per as (select loja_id, min(emissao) de, max(emissao) ate from s group by 1),
       sai as (update public.notas_saida n set ativo = false, atualizado_em = now() from per
               where per.loja_id = n.loja_id and n.ativo and n.emissao between per.de and per.ate
                 and n.tipo_movimento in (select s2.tipo_movimento from s s2 where s2.loja_id = n.loja_id)
                 and not exists (select 1 from s where s.loja_id = n.loja_id and s.cod_nota = n.cod_nota)
               returning n.id)
  insert into public.notas_saida_eventos (nota_id, importacao_id, evento, antes)
  select id, p_importacao, 'sumiu', jsonb_build_object('ativo', true) from sai;

  update public.importacoes set status = 'aplicada', resumo = res, linhas = (res->>'no_arquivo')::int where id = p_importacao;
  return res;
end $$;

revoke execute on function public.previa_importacao_notas_saida(bigint) from anon, public;
grant execute on function public.previa_importacao_notas_saida(bigint) to authenticated;
revoke execute on function public.aplicar_importacao_notas_saida(bigint) from anon, public;
grant execute on function public.aplicar_importacao_notas_saida(bigint) to authenticated;
