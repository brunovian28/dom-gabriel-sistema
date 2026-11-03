-- Migration 66: tela_pedidos, nota de remessa só liga à entrega quando o cliente é o mesmo
-- "Entregas agrupadas" usam outra numeração (do agrupamento), que coincide por acaso com números de entrega:
-- na primeira carga, só 8 de 874 ligações tinham o mesmo cliente (nas notas "Entregas", 9.240 de 9.240).
-- Sem esta trava, pedido de outro cliente aparecia como entregue. Troca feita no texto atual da função.

do $$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public.tela_pedidos(smallint)'::regprocedure);
  d2 := replace(d,
    'and n.tipo_movimento in (''Entregas'', ''Entregas agrupadas'') and n.ativo',
    'and n.tipo_movimento in (''Entregas'', ''Entregas agrupadas'') and n.ativo and n.cliente_codigo is not distinct from g.cliente_codigo');
  if d2 = d then raise exception 'ligação da remessa não encontrada em tela_pedidos'; end if;
  execute d2;
end $$;
