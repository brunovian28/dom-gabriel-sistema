-- Teste da migration 56 (revisão do plano 3: renegociação e permissões). Dados inventados, termina em rollback. Hoje de teste = 2030-09-04
do $$
declare adm uuid; ip bigint; h date := '2030-09-04'; d bigint; d2 bigint; d3 bigint; t1 bigint; t2 bigint; t3 bigint; t4 bigint; ok boolean; msg text;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  update public.dividas set ativo = false where ativo;

  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado) values (1,'PED','TESTE-FUTURO', make_timestamp(2030,12,31,12,0,0), 1, 1, '{}'::jsonb);
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,nome,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-V1','Aberto','2030-06-01',900,900,'Dup','FORNECEDOR TESTE','TESTE-FORN','TESTE.FOR','FORNECEDORES',ip,ip),
         ('pagar',1,'TESTE-V2','Aberto','2030-10-20',5000,5000,'Dup','FORNECEDOR TESTE','TESTE-FORN','TESTE.FOR','FORNECEDORES',ip,ip),
         ('pagar',1,'TESTE-V4','Aberto','2030-07-01',400,400,'Dup','OUTRA LOJA','TESTE-L2X','TESTE.EMP','EMPRESTIMOS',ip,ip);
  select id into t1 from public.titulos_santri where codigo = 'TESTE-V1';
  select id into t2 from public.titulos_santri where codigo = 'TESTE-V2';
  select id into t4 from public.titulos_santri where codigo = 'TESTE-V4';

  -- 1. Renegociação com fornecedor que segue vendendo: a compra normal de outubro (5000) não pode "ligar" a parcela de outubro
  d := public.renegociar_titulos(array[t1], '{"parcela":300,"primeiro_venc":"2030-10-10","n_parcelas":3}');
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -300) = 3,
    'FALHOU compra normal do mesmo fornecedor apagou a parcela';
  assert exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t2 and valor = -5000), 'FALHOU compra normal continua';
  -- a parcela lançada no Santri com o mesmo valor liga normalmente
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,nome,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-V3','Aberto','2030-11-10',300,300,'Dup','FORNECEDOR TESTE','TESTE-FORN','TESTE.FOR','FORNECEDORES',ip,ip) returning id into t3;
  assert (select titulo_id from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = d and numero = 2) = t3, 'FALHOU parcela de mesmo valor liga';
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -300) = 2, 'FALHOU 2 parcelas fora do Santri';

  -- 2. Contrato de renegociação desativado não volta (os títulos já voltaram para a diretoria: contaria em dobro)
  perform public.salvar_divida(d, '{"ativo":false}');
  assert (select decisao from public.titulos_tratativa where titulo_id = t1) = 'para_diretoria', 'FALHOU volta para diretoria';
  ok := false; begin perform public.salvar_divida(d, '{"ativo":true}'); exception when others then msg := sqlerrm; ok := msg = 'Contrato de renegociação desativado não volta: renegocie os títulos de novo'; end;
  assert ok, 'FALHOU reativar renegociacao: ' || coalesce(msg, 'sem erro');

  -- 3. Renegociar título entre lojas cria contrato entre lojas (some no Total)
  update public.caixa_parametros set cadastros_santri = array['TESTE-L2X'] where loja_id = 2;
  if not found then insert into public.caixa_parametros(loja_id, cadastros_santri) values (2, array['TESTE-L2X']); end if;
  d2 := public.renegociar_titulos(array[t4], '{"parcela":200,"primeiro_venc":"2030-10-05","n_parcelas":2}');
  assert (select tipo from public.dividas where id = d2) = 'entre_lojas' and (select outra_loja from public.dividas where id = d2) = 2, 'FALHOU renegociacao entre lojas';
  assert not exists (select 1 from interno.caixa_fluxo(array[1,2]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida'), 'FALHOU entre lojas renegociado fora do Total';
  assert (select count(*) from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = 200) = 2, 'FALHOU espelho das parcelas';

  -- 4. Usuário de uma loja só não edita contrato da outra loja
  d3 := public.salvar_divida(null, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"fixas","parcela":10,"primeiro_venc":"2030-10-01","n_parcelas":1}');
  update public.usuarios set papel = 'financeiro', loja_id = 2, todas_lojas = false where id = adm;
  ok := false; begin perform public.salvar_divida(d3, '{"loja_id":2}'); exception when others then msg := sqlerrm; ok := msg = 'Loja sem permissão'; end;
  assert ok, 'FALHOU editar contrato de outra loja: ' || coalesce(msg, 'sem erro');

  raise exception 'OK-ROLLBACK';
end $$;
