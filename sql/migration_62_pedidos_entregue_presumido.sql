-- Migration 62: tela_pedidos, "entregue presumido" não exige mais a mercadoria completa
-- Pedido com mais de 60 dias, fora das entregas pendentes e sem nenhuma entrega/manifesto no Santri = entregue presumido,
-- mesmo com item sem compra ligada (era o que inchava "Falta comprar": 146 pedidos, 117 pagos, 112 sem nada no Santri).
-- Item não comprado de verdade continua na "fila antiga" da tela de Compras. Decisão do Bruno, 03/11/2026.
-- Troca feita no texto atual da função (falha se o trecho não for achado).

do $$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public.tela_pedidos(smallint)'::regprocedure);
  d2 := regexp_replace(d,
    'when coalesce\(mer\.falta, 0\) = 0 and coalesce\(mer\.fabrica, 0\) = 0 and coalesce\(mer\.faturado, 0\) = 0\s+and vd\.fechamento < hoje - 60 then ''entregue''',
    'when vd.fechamento < hoje - 60 then ''entregue''');
  if d2 = d then raise exception 'regra do entregue presumido não encontrada em tela_pedidos'; end if;
  execute d2;
end $$;
