-- Teste da migration 53 (dados inventados, termina em rollback). Hoje de teste = 2030-09-04, p_vendas = 'zero'
do $$
declare adm uuid; ip bigint; ir bigint; h date := '2030-09-04'; da bigint; db bigint; dc bigint; dg bigint; dh bigint;
  t_b bigint; t_c bigint; t_d bigint; t_e bigint; t_f bigint;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  -- uma venda em 2030 empurra a janela do perfil para longe das vendas reais (sem perfil, não há estimativa de vendas, RT e impostos)
  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado) values (1,'PED','TESTE-FUTURO', make_timestamp(2030,12,31,12,0,0), 1, 1, '{}'::jsonb);
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;
  perform public.salvar_cadastros_loja(1::smallint, array['TESTE-L1']);
  perform public.salvar_cadastros_loja(2::smallint, array['TESTE-L2']);

  -- títulos
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-B','Aberto','2030-10-15',500,500,'Dup','TESTE-CRED','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',1,'TESTE-C','Aberto','2030-10-20',300,300,'Dup','TESTE-CREDC','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',1,'TESTE-D','Aberto','2030-09-20',300,300,'Dup','TESTE-L2','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',1,'TESTE-E','Aberto','2030-07-01',200,200,'Dup','TESTE-L2','TESTE.DIV','EMPRESTIMOS',ip,ip);
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('receber',2,'TESTE-F','Aberto','2030-09-20',300,300,'Duplic','TESTE-L1','TESTE.CLI','CLIENTES',ir,ir);
  select id into t_b from public.titulos_santri where codigo = 'TESTE-B'; select id into t_c from public.titulos_santri where codigo = 'TESTE-C';
  select id into t_d from public.titulos_santri where codigo = 'TESTE-D'; select id into t_e from public.titulos_santri where codigo = 'TESTE-E';
  select id into t_f from public.titulos_santri where codigo = 'TESTE-F';

  -- contratos
  da := public.salvar_divida(null, '{"credor":"CRED-A","tipo":"banco","loja_id":1,"modo":"fixas","parcela":1000,"primeiro_venc":"2030-09-10","n_parcelas":6}');
  db := public.salvar_divida(null, '{"credor":"CRED-B","tipo":"banco","loja_id":1,"modo":"fixas","parcela":500,"primeiro_venc":"2030-09-15","n_parcelas":3,"santri_cadastro":"TESTE-CRED"}');
  dc := public.salvar_divida(null, '{"credor":"CRED-C","tipo":"banco","loja_id":1,"modo":"santri","santri_cadastro":"TESTE-CREDC"}');
  dg := public.salvar_divida(null, '{"credor":"CRED-G","tipo":"entre_lojas","loja_id":1,"outra_loja":2,"modo":"fixas","parcela":100,"primeiro_venc":"2030-09-25","n_parcelas":1}');
  dh := public.salvar_divida(null, '{"credor":"CRED-H","tipo":"banco","loja_id":1,"modo":"fixas","parcela":40,"primeiro_venc":"2030-08-01","n_parcelas":1}');

  -- a: 6 parcelas de 1000, 10/09/2030 a 10/02/2031
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and descricao like 'Parcela %/6 · CRED-A' and valor = -1000 and grupo = 'divida') = 6, 'FALHOU a: 6 parcelas';
  assert (select min(data) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-A') = '2030-09-10'
     and (select max(data) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-A') = '2031-02-10', 'FALHOU a: datas';
  assert (select descricao from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-A' order by data limit 1) = 'Parcela 1/6 · CRED-A', 'FALHOU a: descricao';
  -- b: parcelas de set e nov entram, a de out está no Santri (título) e não duplica
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-B') = 2, 'FALHOU b: 2 parcelas';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-B' and data between '2030-10-01' and '2030-10-31'), 'FALHOU b: out ligada';
  assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null)
           where data between '2030-10-01' and '2030-10-31' and (titulo_id = t_b or descricao like '% · CRED-B')) = -500, 'FALHOU b: out = 500';
  -- c: contrato santri não gera parcela (o título já está no lançado)
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-C'), 'FALHOU c';
  assert exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_c and valor = -300), 'FALHOU c: titulo no lancado';
  -- h: parcela antes de hoje, não ligada, não entra
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-H'), 'FALHOU h';

  -- d: entre lojas, aberto
  assert (select valor from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = -300
     and (select grupo from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = 'entre_lojas'
     and (select data from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = '2030-09-20', 'FALHOU d em {1}';
  assert (select valor from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = 300
     and (select grupo from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = 'entre_lojas'
     and (select data from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d) = '2030-09-20', 'FALHOU d em {2} (espelho)';
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_d), 'FALHOU d fora do Total';
  -- e: entre lojas vencido, sem triagem = semana 0 nas duas pontas
  assert (select valor from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_e) = -200
     and (select data from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_e) = h, 'FALHOU e em {1}';
  assert (select valor from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_e) = 200
     and (select data from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_e) = h, 'FALHOU e em {2}';
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_e), 'FALHOU e fora do Total';
  -- f: a receber entre lojas não entra (o espelho já cobre)
  assert not exists (select 1 from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_f), 'FALHOU f em {2}';
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t_f), 'FALHOU f em {1,2}';
  -- g: contrato entre lojas
  assert (select valor from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-G') = -100, 'FALHOU g em {1}';
  assert (select valor from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-G') = 100
     and (select grupo from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-G') = 'entre_lojas', 'FALHOU g em {2}';
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where descricao like '% · CRED-G'), 'FALHOU g fora do Total';
  -- loja 2 só tem o espelho de d, e e g
  assert (select sum(valor) from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where grupo = 'entre_lojas') = 600, 'FALHOU espelho soma 600';
  assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where grupo = 'entre_lojas') = -600, 'FALHOU saida soma -600';
  -- total sem entre lojas, horizonte, e o lançado puro continua sem dívida
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where grupo = 'entre_lojas'), 'FALHOU total sem entre lojas';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and data > '2031-08-31'), 'FALHOU horizonte';
  assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where origem = 'divida'), 'FALHOU movimentos sem divida';

  raise exception 'OK-ROLLBACK';
end $$;
