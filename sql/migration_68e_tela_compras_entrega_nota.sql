-- Migration 68e: tela Compras usa a nota de remessa (regra única da migration 68)
-- 1) Situação da entrega da venda ligada (lista "Faturadas: trazer agora?"): pendente/sem agendamento pelo relatório
--    de pendentes; entregue = tem nota de remessa ou entrega total; gerada = manifesto aberto sem nota. Antes, entregue
--    tinha prioridade sobre pendente e o manifesto aberto contava como "gerada" mesmo com a mercadoria já entregue.
-- 2) Sai a contagem "no depósito" pelo manifesto (transito.deposito*): a etapa 3 do Acompanhar passa a mostrar os
--    pedidos "Pronto para entregar" da tela Pedidos (calculados no front pela tela_pedidos).
-- 3) Pendentes, manifestos e a lista de vendas ligadas passam a separar por loja (o mesmo número existe em PVA e RV).
-- Troca feita no texto atual da função (falha se algum trecho não for achado).

do $$
declare d text; i int; j int; n int;
begin
  d := pg_get_functiondef('public.tela_compras(smallint)'::regprocedure);

  i := position('  ep as (' in d); j := position('  compra_ped as (' in d);
  if i = 0 or j <= i then raise exception 'ep/eg/ped_cli não encontrados em tela_compras'; end if;
  d := substr(d, 1, i - 1) || $q$  ep as (select loja_id, pedido, secao, prev_maior from public.entregas_pendentes
         where importacao_id = (select max(importacao_id) from public.entregas_pendentes) and loja_id = any(lojas)),
  eg as (select loja_id, pedido, bool_or(status_manifesto ilike 'Aguardando%') aguardando, bool_or(status_entrega ilike 'Entrega total') entregue
         from public.entregas_santri where ativo and loja_id = any(lojas) group by loja_id, pedido),
  ent_nota as materialized (select distinct x.loja_id, x.pedido from interno.entregas_nota(lojas) x),
  ped_cli as (
    select p.loja_id, p.numero pedido, p.cliente_nome cliente,
           case when exists (select 1 from ep where ep.loja_id = p.loja_id and ep.pedido = p.numero and ep.secao = 'pendente') then 'pendente'
                when exists (select 1 from ep where ep.loja_id = p.loja_id and ep.pedido = p.numero and ep.secao = 'sem_agendamento') then 'sem_agendamento'
                when exists (select 1 from ent_nota n where n.loja_id = p.loja_id and n.pedido = p.numero)
                  or coalesce((select bool_or(entregue) from eg where eg.loja_id = p.loja_id and eg.pedido = p.numero), false) then 'entregue'
                when (select bool_or(aguardando) from eg where eg.loja_id = p.loja_id and eg.pedido = p.numero) then 'gerada'
                else 'sem_info' end situacao,
           (select max(prev_maior) from ep where ep.loja_id = p.loja_id and ep.pedido = p.numero) previsao
    from vd p),
$q$ || substr(d, j);

  n := length(d);
  d := replace(d, 'where pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = nf.loja and',
                  'where pc.loja_id = nf.loja and pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = nf.loja and');
  d := replace(d, 'where pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = fab.loja_id and',
                  'where pc.loja_id = fab.loja_id and pc.pedido in (select unnest(cp.pedidos) from compra_ped cp where cp.loja_id = fab.loja_id and');
  if length(d) <> n + 2 * length('pc.loja_id = nf.loja and ') + (length('pc.loja_id = fab.loja_id and ') - length('pc.loja_id = nf.loja and ')) then
    raise exception 'filtro de loja das vendas ligadas não aplicado';
  end if;

  i := position('  dep as (' in d); j := position('  tit as (' in d);
  if i = 0 or j <= i then raise exception 'CTE dep não encontrada em tela_compras'; end if;
  d := substr(d, 1, i - 1) || substr(d, j);

  n := length(d);
  d := replace(d, $s$,
       'deposito', (select n from dep), 'deposito_valor', (select valor from dep), 'deposito_mediana', (select mediana from dep),
       'deposito_30', (select n30 from dep), 'deposito_30_valor', (select valor30 from dep))$s$, ')');
  if length(d) = n then raise exception 'chaves deposito não encontradas em tela_compras'; end if;

  execute d;
end $$;
