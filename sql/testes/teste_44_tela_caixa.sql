-- Teste da migration 44 (dados inventados, termina em rollback). Hoje de teste = 2026-11-04 (quarta)
do $$
declare
  adm uuid; ip bigint; ir bigint; conta bigint; bx bigint; r jsonb; h date := '2026-11-04';
  t_a bigint; t_b bigint; t_c bigint; t_c2 bigint; t_d bigint; t_e bigint; t_f bigint; t_g bigint; t_h bigint;
  t_i bigint; t_j bigint; t_k bigint; t_l bigint; t_m bigint; t_n bigint; t_o bigint;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;
  update public.contas_bancarias set ativo = false where loja_id in (1,2);
  insert into public.contas_bancarias(loja_id,banco,nome) values (1,'BANCO TESTE','Conta T') returning id into conta;
  perform public.informar_saldo_conta(conta, 10000, null);
  perform public.salvar_parametros_caixa(1::smallint, 9900);
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa) values ('TESTE.FORA','CONTA DE TESTE','fora');

  -- a pagar (plano TESTE.FORN cai na heurística: fornecedor)
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,nome,ultima_importacao_id,importacao_id)
  select 'pagar', v.loja, 'TESTE-'||v.c, 'Aberto', v.venc::date, v.saldo, v.saldo, v.tipo, coalesce(v.plano,'TESTE.FORN'), case when v.plano is null then 'FORNECEDORES' else 'CONTA DE TESTE' end, 'FORNECEDOR '||v.c, ip, ip
  from (values (1,'a','2026-11-10',100,'Dup',null),(1,'b','2026-10-20',200,'Dup',null),(1,'c','2026-10-15',300,'Dup',null),(1,'c2','2026-10-15',50,'Dup',null),
               (1,'d','2026-10-10',400,'Dup',null),(1,'e','2026-10-10',500,'Dup',null),(1,'f','2026-11-12',50,'Pre',null),(1,'g','2026-11-12',60,'Dup',null),
               (1,'h','2026-11-12',70,'Dup','TESTE.FORA'),(2,'o','2026-11-10',70,'Dup',null)) v(loja,c,venc,saldo,tipo,plano);
  select id into t_a  from public.titulos_santri where codigo='TESTE-a';  select id into t_b  from public.titulos_santri where codigo='TESTE-b';
  select id into t_c  from public.titulos_santri where codigo='TESTE-c';  select id into t_c2 from public.titulos_santri where codigo='TESTE-c2';
  select id into t_d  from public.titulos_santri where codigo='TESTE-d';  select id into t_e  from public.titulos_santri where codigo='TESTE-e';
  select id into t_f  from public.titulos_santri where codigo='TESTE-f';  select id into t_g  from public.titulos_santri where codigo='TESTE-g';
  select id into t_h  from public.titulos_santri where codigo='TESTE-h';  select id into t_o  from public.titulos_santri where codigo='TESTE-o';
  insert into public.titulos_tratativa(titulo_id,decisao,nova_data) values (t_c,'pagar_em','2026-11-20'),(t_c2,'pagar_em','2026-11-01'),(t_d,'em_disputa',null),(t_e,'nao_e_divida',null);
  -- g: pago por baixa depois da última foto
  insert into public.baixas_santri(lado,loja_id,baixa,data_baixa,ativo) values ('pagar',1,'TESTE-BX',(now() at time zone 'America/Cuiaba')::date + 1,true) returning id into bx;
  insert into public.baixas_santri_titulos(baixa_id,ordem,cod_financeiro,valor_baixado,ativo) values (bx,1,'TESTE-g',60,true);

  -- a receber
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,nome,ultima_importacao_id,importacao_id)
  select 'receber', 1, 'TESTE-'||v.c, 'Aberto', v.venc::date, v.saldo, v.saldo, v.tipo, 'TESTE.CLI', 'CLIENTES', 'CLIENTE '||v.c, ir, ir
  from (values ('i','2026-11-15',1000,'Duplic'),('j','2026-10-05',700,'Duplic'),('k','2026-08-06',800,'Duplic'),('l','2026-08-06',900,'Duplic'),
               ('m','2026-11-20',400,'Cartão'),('n','2026-10-15',150,'Duplic')) v(c,venc,saldo,tipo);
  select id into t_i from public.titulos_santri where codigo='TESTE-i'; select id into t_j from public.titulos_santri where codigo='TESTE-j';
  select id into t_k from public.titulos_santri where codigo='TESTE-k'; select id into t_l from public.titulos_santri where codigo='TESTE-l';
  select id into t_m from public.titulos_santri where codigo='TESTE-m'; select id into t_n from public.titulos_santri where codigo='TESTE-n';
  insert into public.titulos_tratativa(titulo_id,decisao,nova_data) values (t_l,'prometeu','2026-11-25'),(t_n,'perdido',null);

  -- movimentos (modo triagem)
  create temp table mv on commit drop as select * from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem');
  assert (select data from mv where titulo_id = t_a) = '2026-11-10' and (select valor from mv where titulo_id = t_a) = -100 and (select grupo from mv where titulo_id = t_a) = 'fornecedor', 'FALHOU a';
  assert (select data from mv where titulo_id = t_b) = h and (select valor from mv where titulo_id = t_b) = -200, 'FALHOU b';
  assert (select data from mv where titulo_id = t_c) = '2026-11-20' and (select valor from mv where titulo_id = t_c) = -300, 'FALHOU c';
  assert (select data from mv where titulo_id = t_c2) = h and (select valor from mv where titulo_id = t_c2) = -50, 'FALHOU c2 (pagar_em no passado)';
  assert not exists (select 1 from mv where titulo_id = t_d), 'FALHOU d (em disputa fora)';
  assert not exists (select 1 from mv where titulo_id in (t_e, t_f, t_g, t_h, t_k, t_m, t_n, t_o)), 'FALHOU e/f/g/h/k/m/n/o fora';
  assert (select data from mv where titulo_id = t_i) = '2026-11-15' and (select valor from mv where titulo_id = t_i) = 1000 and (select grupo from mv where titulo_id = t_i) = 'clientes', 'FALHOU i';
  assert (select data from mv where titulo_id = t_j) = '2026-11-11' and (select valor from mv where titulo_id = t_j) = 700, 'FALHOU j (vencido 30 dias -> hoje+7)';
  assert (select data from mv where titulo_id = t_l) = '2026-11-25' and (select valor from mv where titulo_id = t_l) = 900, 'FALHOU l (prometeu)';
  assert (select count(*) from mv) = 7, 'FALHOU: total de movimentos = ' || (select count(*) from mv);
  -- modo pagar_tudo
  assert (select data from interno.caixa_movimentos(array[1]::smallint[], h, 'pagar_tudo') where titulo_id = t_d) = h, 'FALHOU d em pagar_tudo';
  assert (select data from interno.caixa_movimentos(array[1]::smallint[], h, 'pagar_tudo') where titulo_id = t_c) = h, 'FALHOU c em pagar_tudo';
  assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'pagar_tudo') where titulo_id = t_e), 'FALHOU e em pagar_tudo';
  -- loja 2 aparece só quando pedida
  assert exists (select 1 from interno.caixa_movimentos(array[2]::smallint[], h, 'triagem') where titulo_id = t_o), 'FALHOU o em loja 2';

  -- tela_caixa
  r := public.tela_caixa(1::smallint, 'triagem', h);
  assert (r->'saldo'->>'informado')::boolean and (r->'saldo'->>'total')::numeric = 10000, 'FALHOU saldo';
  assert jsonb_array_length(r->'semanas') = 13 and jsonb_array_length(r->'meses') = 12, 'FALHOU tamanhos';
  assert (r->'semanas'->0->>'saldo_fim')::numeric = 9750, 'FALHOU semana 0 = ' || (r->'semanas'->0->>'saldo_fim');
  assert (r->'semanas'->1->>'saldo_fim')::numeric = 11350, 'FALHOU semana 1 = ' || (r->'semanas'->1->>'saldo_fim');
  assert (r->'semanas'->2->>'saldo_fim')::numeric = 11050, 'FALHOU semana 2 = ' || (r->'semanas'->2->>'saldo_fim');
  assert (r->'semanas'->3->>'saldo_fim')::numeric = 11950, 'FALHOU semana 3 = ' || (r->'semanas'->3->>'saldo_fim');
  assert (r->'kpi'->'primeira_abaixo'->>'k')::int = 0 and not (r->'kpi'->'primeira_abaixo'->>'negativo')::boolean, 'FALHOU primeira_abaixo';
  assert (r->'kpi'->'maior_buraco'->>'valor')::numeric = 9750, 'FALHOU maior_buraco';
  assert (r->'kpi'->>'atrasado_pagar')::numeric = 950, 'FALHOU atrasado_pagar = ' || (r->'kpi'->>'atrasado_pagar');
  assert (r->'kpi'->>'atrasado_nao_triado')::numeric = 200, 'FALHOU atrasado_nao_triado';
  assert (r->'meses'->0->>'saldo_fim')::numeric = 11950, 'FALHOU mes 0';
  assert jsonb_array_length(r->'atrasados') = 4, 'FALHOU atrasados = ' || jsonb_array_length(r->'atrasados');
  assert (r->'atrasados'->0->>'saldo')::numeric = 400, 'FALHOU atrasados ordem por saldo';
  assert (r->'semanas'->0->'grupos'->>'fornecedor')::numeric = -250, 'FALHOU grupos semana 0';
  assert jsonb_array_length(r->'por_loja') = 1 and (r->'por_loja'->0->>'atrasado_pagar')::numeric = 950, 'FALHOU por_loja 1';
  -- duas lojas: a loja sem saldo informado derruba o "informado" do total
  r := public.tela_caixa(0::smallint, 'triagem', h);
  assert jsonb_array_length(r->'por_loja') = 2, 'FALHOU por_loja 2 lojas';
  assert (r->'por_loja'->0->>'atrasado_pagar')::numeric = 950 and (r->'por_loja'->1->>'atrasado_pagar')::numeric = 0, 'FALHOU por_loja valores';
  assert not (r->'saldo'->>'informado')::boolean and r->'saldo'->'lojas_sem_saldo' = '[2]'::jsonb, 'FALHOU loja 2 sem saldo';
  -- pagar_tudo
  r := public.tela_caixa(1::smallint, 'pagar_tudo', h);
  assert (r->'semanas'->0->>'saldo_fim')::numeric = 9050, 'FALHOU pagar_tudo semana 0 = ' || (r->'semanas'->0->>'saldo_fim');
  -- detalhe
  assert jsonb_array_length(public.caixa_detalhe(1::smallint, 'fornecedor', '2026-11-09', '2026-11-15', 'triagem', h)) = 1, 'FALHOU detalhe';
  -- sem saldo informado (Review Focus 3)
  update public.contas_bancarias set ativo = false where id = conta;
  r := public.tela_caixa(1::smallint, 'triagem', h);
  assert not (r->'saldo'->>'informado')::boolean, 'FALHOU informado=false';
  assert jsonb_typeof(r->'kpi'->'primeira_abaixo') = 'null', 'FALHOU primeira_abaixo sem saldo';

  -- usuário financeiro de uma loja só (Review Focus 4)
  update public.usuarios set papel = 'financeiro', loja_id = 2, todas_lojas = false where id = adm;
  r := public.tela_caixa(0::smallint, 'triagem', h);
  assert r->'lojas' = '[2]'::jsonb, 'FALHOU lojas do financeiro RV = ' || (r->>'lojas');

  raise exception 'OK-ROLLBACK';
end $$;
