-- Teste da migration 52 (dados inventados, termina em rollback). Hoje de teste = 2030-09-04
do $$
declare adm uuid; ip bigint; h date := '2030-09-04'; a bigint; b bigint; c bigint; ok boolean; msg text;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,cadastro_codigo,documento,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-DV1','Aberto','2030-10-15',500,500,'Dup','TESTE-BCO','TESTE-A/1',ip,ip),
         ('pagar',1,'TESTE-DV2','Aberto','2030-10-15',700,700,'Dup','TESTE-BCO','TESTE-B/1',ip,ip);

  a := public.salvar_divida(null, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"fixas","parcela":500,"primeiro_venc":"2030-09-15","n_parcelas":3,"santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-A"}');
  assert (select count(*) from public.dividas_parcelas where divida_id = a and ativo) = 3, 'FALHOU 3 parcelas';
  assert (select vencimento from public.dividas_parcelas where divida_id = a and numero = 3 and ativo) = '2030-11-15', 'FALHOU datas';
  assert (select bool_and(no_santri = (vencimento = '2030-10-15')) from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = a), 'FALHOU ligacao por mes';
  assert (select count(*) from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = a) = 3, 'FALHOU 3 parcelas na lista';
  assert (select titulo_id from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = a and vencimento = '2030-10-15') = (select id from public.titulos_santri where codigo = 'TESTE-DV1'), 'FALHOU titulo ligado';

  b := public.salvar_divida(null, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"santri","santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-B"}');
  assert (select sum(valor) from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = b) = 700, 'FALHOU modo santri com prefixo';
  assert (select bool_and(no_santri) from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = b), 'FALHOU modo santri no_santri';

  perform public.salvar_divida(a, '{"credor":"BANCO TESTE","tipo":"banco","loja_id":1,"modo":"fixas","parcela":400,"primeiro_venc":"2030-09-15","n_parcelas":2,"santri_cadastro":"TESTE-BCO","santri_doc_prefixo":"TESTE-A"}');
  assert (select count(*) from public.dividas_parcelas where divida_id = a and ativo) = 2 and (select count(*) from public.dividas_parcelas where divida_id = a) = 5, 'FALHOU regerar sem apagar';
  assert (select count(*) from public.dividas_eventos where divida_id = a) = 2, 'FALHOU eventos';
  assert (select count(*) from interno.dividas_parcelas_todas(array[1]::smallint[], h) where divida_id = a) = 2, 'FALHOU inativas fora da lista';

  -- 31/01 -> 28/02 -> 31/03 (último dia do mês)
  c := public.salvar_divida(null, '{"credor":"X","tipo":"outro","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}');
  assert (select array_agg(vencimento order by numero) from public.dividas_parcelas where divida_id = c) = array['2031-01-31','2031-02-28','2031-03-31']::date[], 'FALHOU fim de mes';

  perform public.salvar_cadastros_loja(2::smallint, array['TESTE-L2']);
  assert interno.loja_do_cadastro('TESTE-L2') = 2 and interno.loja_do_cadastro('TESTE-NADA') is null, 'FALHOU loja do cadastro';

  -- erros
  ok := false; begin perform public.salvar_divida(null, '{"credor":"X","tipo":"entre_lojas","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}'); exception when others then ok := sqlerrm = 'Entre lojas precisa da outra loja'; end;
  assert ok, 'FALHOU entre lojas sem outra loja';
  ok := false; begin perform public.salvar_divida(null, '{"credor":"X","tipo":"banco","loja_id":1,"modo":"santri"}'); exception when others then ok := sqlerrm = 'Informe o código do credor no Santri'; end;
  assert ok, 'FALHOU santri sem codigo';
  ok := false; begin perform public.salvar_divida(null, '{"credor":"","tipo":"banco","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}'); exception when others then ok := sqlerrm = 'Informe o credor'; end;
  assert ok, 'FALHOU sem credor';
  ok := false; begin perform public.salvar_divida(null, '{"credor":"X","tipo":"xpto","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}'); exception when others then ok := sqlerrm = 'Tipo inválido'; end;
  assert ok, 'FALHOU tipo invalido';
  ok := false; begin perform public.salvar_divida(null, '{"credor":"X","tipo":"banco","loja_id":1,"modo":"fixas","parcela":1}'); exception when others then ok := sqlerrm = 'Informe parcela, 1º vencimento e número de parcelas'; end;
  assert ok, 'FALHOU fixas sem parcelas';

  -- sem permissão
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  ok := false; begin perform public.salvar_divida(null, '{"credor":"X","tipo":"banco","loja_id":1,"modo":"fixas","parcela":1,"primeiro_venc":"2031-01-31","n_parcelas":3}'); exception when others then ok := true; end;
  assert ok, 'FALHOU usuario sem permissao salvar_divida';
  ok := false; begin perform public.salvar_cadastros_loja(2::smallint, array['X']); exception when others then ok := true; end;
  assert ok, 'FALHOU usuario sem permissao salvar_cadastros_loja';

  raise exception 'OK-ROLLBACK';
end $$;
