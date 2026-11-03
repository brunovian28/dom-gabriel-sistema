-- Migration 60c: fecha interno.pedidos_mercadoria para anon/public (mesmo padrao de interno.saldo_caixa e das migrations 45/46).
-- tela_pedidos e security definer: continua chamando a funcao como dono.
revoke execute on function interno.pedidos_mercadoria(smallint[], date) from anon, public;
grant execute on function interno.pedidos_mercadoria(smallint[], date) to authenticated;
