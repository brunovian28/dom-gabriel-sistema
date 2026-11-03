-- Migration 68d: painel da Direção, bloco Entrega pela nota de remessa (regra única da migration 68)
-- Saem aguardando / aguardando_30 / concluidas_mes (contados pelo manifesto). Entram:
-- sairam_mes e sairam_mes_valor (entregas com nota de remessa no mês do painel), fechar_manifesto e _valor
-- (nota há mais de 30 dias e manifesto aberto), sem_nota (manifesto aberto sem nota) e pendentes_vencidas_valor.
-- Troca feita no texto atual da função (falha se o trecho não for achado).

do $$
declare d text; i int; j int;
begin
  d := pg_get_functiondef('public.painel_direcao(smallint,date)'::regprocedure);
  if position('  eg as (select * from public.entregas_santri where loja_id = any(lojas) and ativo),' in d) = 0 then
    raise exception 'CTE eg não encontrada em painel_direcao';
  end if;
  d := replace(d, '  eg as (select * from public.entregas_santri where loja_id = any(lojas) and ativo),',
    '  eg as (select e.*, n.nota_em from public.entregas_santri e left join interno.entregas_nota(lojas) n on n.entrega_id = e.id where e.loja_id = any(lojas) and e.ativo),');
  i := position('''aguardando'', (select count(*) from eg' in d);
  j := position('''pendentes'', (select count(*) from ep where secao = ''pendente'')' in d);
  if i = 0 or j <= i then raise exception 'bloco entrega não encontrado em painel_direcao'; end if;
  d := substr(d, 1, i - 1) || $q$'sairam_mes', (select count(*) from eg where nota_em >= ini and nota_em < fim),
      'sairam_mes_valor', (select coalesce(sum(valor),0) from eg where nota_em >= ini and nota_em < fim),
      'fechar_manifesto', (select count(*) from eg where status_manifesto = 'Aguardando Carregamento' and nota_em < hoje - 30),
      'fechar_manifesto_valor', (select coalesce(sum(valor),0) from eg where status_manifesto = 'Aguardando Carregamento' and nota_em < hoje - 30),
      'sem_nota', (select count(*) from eg where status_manifesto = 'Aguardando Carregamento' and nota_em is null),
      'pendentes_vencidas_valor', (select coalesce(sum(valor),0) from ep where secao = 'pendente' and prev_maior < hoje),
      $q$ || substr(d, j);
  execute d;
end $$;
