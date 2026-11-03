-- Teste da migration 48 (dados inventados, termina em rollback). Hoje de teste = 2026-11-04
do $$
declare adm uuid; ip bigint; h date := '2026-11-04'; m int;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa, fixa) values ('TESTE.ALUG','ALUGUEL DE TESTE','fixo',true),('TESTE.ICMS','ICMS DE TESTE','impostos',true);

  -- mai a out/2026: 1000 pagos em cada conta, dia 5
  for m in 5..10 loop
    insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-A'||m,'Baixado',make_date(2026,m,5),0,1000,'Dup','TESTE.ALUG','ALUGUEL DE TESTE',ip,ip),
           ('pagar',1,'TESTE-I'||m,'Baixado',make_date(2026,m,5),0,1000,'Dup','TESTE.ICMS','ICMS DE TESTE',ip,ip);
  end loop;
  -- aluguel já lançado em aberto: 400 em nov/2026 e 1500 em jan/2027
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-A11','Aberto','2026-11-05',400,400,'Dup','TESTE.ALUG','ALUGUEL DE TESTE',ip,ip),
         ('pagar',1,'TESTE-A01','Aberto','2027-01-05',1500,1500,'Dup','TESTE.ALUG','ALUGUEL DE TESTE',ip,ip);

  assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and descricao is not null and data = '2026-11-05') = -600, 'FALHOU nov = media - lancado';
  assert (select valor from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and data = '2026-12-05') = -1000, 'FALHOU dez = media';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and data between '2027-01-01' and '2027-01-31'), 'FALHOU jan acima da media';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and grupo='impostos'), 'FALHOU fixa de imposto ignorada';
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo') = 11, 'FALHOU 11 meses (nov..out, sem jan)';
  -- nada em dobro: lançado aberto de nov (400) + fixo de nov (600) = média
  assert (select -sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null)
           where data between '2026-11-01' and '2026-11-30' and (origem='fixo' or titulo_id in (select id from public.titulos_santri where plano_codigo='TESTE.ALUG'))) = 1000, 'FALHOU nao dobra';
  -- a estimativa sai com a descrição da conta
  assert (select descricao from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='fixo' and data = '2026-12-05') = 'ALUGUEL DE TESTE', 'FALHOU descricao';
  -- caixa_movimentos continua só com o lançado
  assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where origem <> 'lancado'), 'FALHOU movimentos so lancado';
  assert exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where titulo_id in (select id from public.titulos_santri where codigo = 'TESTE-A11')), 'FALHOU movimentos tem o lancado';

  raise exception 'OK-ROLLBACK';
end $$;
