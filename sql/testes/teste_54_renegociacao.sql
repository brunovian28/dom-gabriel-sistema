-- Teste da migration 54 (dados inventados, termina em rollback). Hoje de teste = 2030-09-04
do $$
declare adm uuid; ip bigint; ir bigint; h date := '2030-09-04'; d bigint; t1 bigint; t2 bigint; t3 bigint; t4 bigint; t5 bigint; t6 bigint; ok boolean; msg text;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  -- uma venda em 2030 empurra a janela do perfil para longe das vendas reais
  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado) values (1,'PED','TESTE-FUTURO', make_timestamp(2030,12,31,12,0,0), 1, 1, '{}'::jsonb);
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;

  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,nome,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-R1','Aberto','2030-06-01',900,900,'Dup','CREDOR TESTE GRANDE','TESTE-CRED3','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',1,'TESTE-R2','Aberto','2030-09-03',100,100,'Dup','CREDOR TESTE GRANDE','TESTE-CRED3','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',1,'TESTE-R4','Aberto','2030-06-01',50,50,'Dup','OUTRO','TESTE-OUTRO','TESTE.DIV','EMPRESTIMOS',ip,ip),
         ('pagar',2,'TESTE-R5','Aberto','2030-06-01',70,70,'Dup','OUTRO','TESTE-OUTRO','TESTE.DIV','EMPRESTIMOS',ip,ip);
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('receber',1,'TESTE-R6','Aberto','2030-10-01',80,80,'Duplic','TESTE-CLI','TESTE.CLI','CLIENTES',ir,ir);
  select id into t1 from public.titulos_santri where codigo = 'TESTE-R1'; select id into t2 from public.titulos_santri where codigo = 'TESTE-R2';
  select id into t4 from public.titulos_santri where codigo = 'TESTE-R4'; select id into t5 from public.titulos_santri where codigo = 'TESTE-R5';
  select id into t6 from public.titulos_santri where codigo = 'TESTE-R6';

  d := public.renegociar_titulos(array[t1, t2], '{"credor":"CREDOR TESTE","tipo":"outro","parcela":250,"primeiro_venc":"2030-09-10","n_parcelas":4}');
  assert (select origem from public.dividas where id = d) = 'renegociacao' and (select saldo_informado from public.dividas where id = d) = 1000, 'FALHOU contrato';
  assert (select modo from public.dividas where id = d) = 'fixas' and (select santri_cadastro from public.dividas where id = d) = 'TESTE-CRED3', 'FALHOU modo e cadastro';
  assert (select count(*) from public.titulos_tratativa where divida_id = d and decisao = 'renegociado') = 2, 'FALHOU tratativas';
  assert (select count(*) from public.titulos_tratativa_eventos where divida_id = d) = 2, 'FALHOU eventos';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id in (t1, t2)), 'FALHOU titulos fora';
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -250) = 4, 'FALHOU 4 parcelas';

  -- Ana lança a 1ª parcela no Santri: título novo do mesmo cadastro, aberto, 10/09/2030, 250.
  -- A parcela de set sai do caixa, o título entra, e o título antigo t2 (set, renegociado) não liga à parcela.
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,nome,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-R3','Aberto','2030-09-10',250,250,'Dup','CREDOR TESTE GRANDE','TESTE-CRED3','TESTE.DIV','EMPRESTIMOS',ip,ip) returning id into t3;
  assert (select sum(valor) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where data between '2030-09-01' and '2030-09-30' and (origem = 'divida' or titulo_id = t3)) = -250, 'FALHOU sem dobro no mes';
  assert (select titulo_id from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = d and numero = 1) = t3, 'FALHOU parcela liga ao titulo novo e nao ao renegociado';
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -250) = 3, 'FALHOU 3 parcelas restantes';

  -- o atrasado continua mostrando o título renegociado (ainda aberto no Santri)
  assert exists (select 1 from interno.caixa_atrasados(array[1]::smallint[], h) where titulo_id = t1 and decisao = 'renegociado'), 'FALHOU atrasado mostra o renegociado';

  -- erros
  ok := false; begin perform public.tratar_titulos(array[t1], 'pagar_em', '2030-10-01', null); exception when others then msg := sqlerrm; ok := msg = 'Título renegociado: desative o contrato na aba Dívidas'; end;
  assert ok, 'FALHOU trocar decisao do renegociado: ' || coalesce(msg, 'sem erro');
  ok := false; begin perform public.tratar_titulos(array[t4], 'renegociado', '2030-10-01', null); exception when others then msg := sqlerrm; ok := msg = 'Use Renegociar, que cria as parcelas'; end;
  assert ok, 'FALHOU tratar renegociado: ' || coalesce(msg, 'sem erro');
  ok := false; begin perform public.renegociar_titulos(array[t4, t5], '{"parcela":10,"primeiro_venc":"2030-10-10","n_parcelas":2}'); exception when others then msg := sqlerrm; ok := msg = 'Títulos de lojas diferentes'; end;
  assert ok, 'FALHOU lojas diferentes: ' || coalesce(msg, 'sem erro');
  ok := false; begin perform public.renegociar_titulos(array[t6], '{"parcela":10,"primeiro_venc":"2030-10-10","n_parcelas":2}'); exception when others then msg := sqlerrm; ok := msg = 'Só contas a pagar'; end;
  assert ok, 'FALHOU so a pagar: ' || coalesce(msg, 'sem erro');
  ok := false; begin perform public.renegociar_titulos(array[t1], '{"parcela":10,"primeiro_venc":"2030-10-10","n_parcelas":2}'); exception when others then msg := sqlerrm; ok := msg = 'Título já renegociado'; end;
  assert ok, 'FALHOU ja renegociado: ' || coalesce(msg, 'sem erro');
  -- outra decisão continua valendo para título que não é renegociado
  perform public.tratar_titulos(array[t4], 'em_disputa', null, null);
  assert (select decisao from public.titulos_tratativa where titulo_id = t4) = 'em_disputa', 'FALHOU tratar normal continua';

  -- desativar o contrato devolve os títulos para a diretoria e para a semana 0
  perform public.salvar_divida(d, (select to_jsonb(x) - 'id' from public.dividas x where id = d) || '{"ativo":false}');
  assert (select decisao from public.titulos_tratativa where titulo_id = t1) = 'para_diretoria', 'FALHOU volta para diretoria';
  assert (select nota from public.titulos_tratativa where titulo_id = t1) = 'contrato de renegociação desativado', 'FALHOU nota ao desativar';
  assert exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where titulo_id = t1 and data = h), 'FALHOU titulo volta para semana 0';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem = 'divida' and valor = -250), 'FALHOU parcelas somem com o contrato desativado';

  raise exception 'OK-ROLLBACK';
end $$;
