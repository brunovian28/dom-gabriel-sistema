-- Teste da migration 55 (dados inventados, termina em rollback). Hoje de teste = 2030-09-04
do $$
declare adm uuid; ip bigint; ir bigint; h date := '2030-09-04'; a bigint; b bigint; c bigint; d bigint; r jsonb; t jsonb; x jsonb; ok boolean;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  -- os contratos reais (carga da Task 7) não entram na conta deste teste
  update public.dividas set ativo = false where ativo;
  -- uma venda em 2030 empurra a janela do perfil para longe das vendas reais
  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado) values (1,'PED','TESTE-FUTURO', make_timestamp(2030,12,31,12,0,0), 1, 1, '{}'::jsonb);
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;
  perform public.salvar_cadastros_loja(1::smallint, array['TESTE-L1']);
  perform public.salvar_cadastros_loja(2::smallint, array['TESTE-L2']);
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa) values ('TESTE.DIVSEM','CONTA DIVIDA DE TESTE','divida');

  -- e: título de dívida sem contrato (loja 2). Também: atrasados da loja 1, um entre lojas (200) e um comum (100), fora do grupo dívida
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,nome,cadastro_codigo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',2,'TESTE-E','Aberto','2030-09-20',80,80,'Dup','CREDOR SEM CONTRATO','TESTE-SEM','TESTE.DIVSEM','CONTA DIVIDA DE TESTE',ip,ip),
         ('pagar',1,'TESTE-AT1','Aberto','2030-07-01',200,200,'Dup','OUTRA LOJA','TESTE-L2','TESTE.FORN','FORNECEDORES',ip,ip),
         ('pagar',1,'TESTE-AT2','Aberto','2030-07-01',100,100,'Dup','FORN COMUM','TESTE-FORN','TESTE.FORN','FORNECEDORES',ip,ip);

  a := public.salvar_divida(null, '{"credor":"CRED-A","tipo":"banco","loja_id":1,"modo":"fixas","saldo_informado":1200,"parcela":100,"primeiro_venc":"2030-10-01","n_parcelas":24,"santri_cadastro":"TESTE-REP"}');
  b := public.salvar_divida(null, '{"credor":"CRED-B","tipo":"banco","loja_id":1,"modo":"fixas","parcela":50,"primeiro_venc":"2030-09-10","n_parcelas":4,"santri_cadastro":"TESTE-REP"}');
  c := public.salvar_divida(null, '{"credor":"CRED-C","tipo":"banco","loja_id":1,"modo":"fixas","saldo_informado":1000,"taxa_mes":1,"parcela":510,"primeiro_venc":"2030-09-15","n_parcelas":2}');
  d := public.salvar_divida(null, '{"credor":"CRED-D","tipo":"entre_lojas","loja_id":1,"outra_loja":2,"modo":"fixas","saldo_informado":300,"parcela":100,"primeiro_venc":"2030-09-25","n_parcelas":3}');

  r := interno.dividas_resumo(array[1,2]::smallint[], h);
  x := (select e from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = a);
  assert (x->>'saldo')::numeric = 1200 and x->>'acaba_em' = '2032-09-01' and (x->>'faltam')::int = 24 and not (x->>'saldo_estimado')::boolean, 'FALHOU a';
  x := (select e from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = b);
  assert (x->>'saldo')::numeric = 200 and (x->>'saldo_estimado')::boolean and (x->>'parcelas_fora')::int = 4, 'FALHOU b';
  x := (select e from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = d);
  assert (x->>'entre_lojas')::boolean and (x->>'saldo')::numeric = 300, 'FALHOU d na lista';
  assert (r->>'total')::numeric = 1200 + 200 + 1000 + 80, 'FALHOU total = ' || (r->>'total');
  assert (r->'curva'->-1->>'mes') = '2032-09-01', 'FALHOU curva ate a ultima parcela';
  assert (r->'curva'->0->>'saldo')::numeric = (r->>'total')::numeric, 'FALHOU curva comeca no total';
  assert round((r->>'parcela_media_mes')::numeric, 2) = round((12*100 + 200 + 1020 + 80) / 12.0, 2), 'FALHOU parcela media';
  assert jsonb_array_length(r->'sem_contrato') = 1 and (r->'sem_contrato'->0->>'saldo')::numeric = 80 and (r->'sem_contrato'->0->>'loja')::int = 2, 'FALHOU sem contrato';
  assert (r->>'sem_contrato_saldo')::numeric = 80, 'FALHOU sem_contrato_saldo';
  -- filtro repetido: a e b usam o mesmo filtro, c não
  assert (select (e->>'filtro_repetido')::boolean from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = a)
     and (select (e->>'filtro_repetido')::boolean from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = b)
     and not (select (e->>'filtro_repetido')::boolean from jsonb_array_elements(r->'contratos') e where (e->>'id')::bigint = c), 'FALHOU filtro repetido';
  -- só a loja 1: entre lojas entra
  assert (interno.dividas_resumo(array[1]::smallint[], h)->>'total')::numeric = 1200 + 200 + 1000 + 300, 'FALHOU total da loja 1 com entre lojas';
  -- total por loja
  assert (select (e->>'total')::numeric from jsonb_array_elements(r->'por_loja') e where (e->>'loja')::int = 1) = 1200 + 200 + 1000 + 300
     and (select (e->>'total')::numeric from jsonb_array_elements(r->'por_loja') e where (e->>'loja')::int = 2) = 80, 'FALHOU por_loja';

  -- tela_dividas e KPI do topo
  t := public.tela_dividas(0::smallint, h);
  assert (t->>'total')::numeric = (r->>'total')::numeric and t->>'hoje' = '2030-09-04' and jsonb_array_length(t->'cadastros') = 2, 'FALHOU tela_dividas';
  t := public.tela_caixa(0::smallint, 'triagem', 'zero', null, h);
  assert (t->'kpi'->'divida'->>'total')::numeric = (r->>'total')::numeric, 'FALHOU kpi divida';
  assert (t->'kpi'->'divida'->>'sem_contrato')::numeric = 80, 'FALHOU kpi sem_contrato';
  assert (select (e->>'divida')::numeric from jsonb_array_elements(t->'por_loja') e where (e->>'loja')::int = 1) = 1200 + 200 + 1000 + 300, 'FALHOU por_loja divida';
  -- atrasado do Total sem entre lojas (200 entre lojas fora, 100 comum dentro), da loja 1 com os dois
  assert (t->'kpi'->>'atrasado_pagar')::numeric = 100, 'FALHOU atrasado do Total = ' || (t->'kpi'->>'atrasado_pagar');
  assert jsonb_array_length(t->'atrasados') = 1, 'FALHOU lista de atrasados do Total';
  t := public.tela_caixa(1::smallint, 'triagem', 'zero', null, h);
  assert (t->'kpi'->>'atrasado_pagar')::numeric = 300 and jsonb_array_length(t->'atrasados') = 2, 'FALHOU atrasado da loja 1 inclui entre lojas';

  -- curva de um contrato só (c): set -> 1000, out -> 500 (1000 x 1,01 - 510)
  update public.dividas set ativo = false where id <> c;
  x := interno.dividas_resumo(array[1]::smallint[], h)->'curva';
  assert jsonb_array_length(x) = 2 and (x->0->>'mes') = '2030-09-01' and (x->0->>'saldo')::numeric = 1000 and (x->1->>'mes') = '2030-10-01' and (x->1->>'saldo')::numeric = 500, 'FALHOU curva do contrato c: ' || x::text;

  -- anon sem EXECUTE
  assert not has_function_privilege('anon', 'public.tela_dividas(smallint,date)', 'execute'), 'FALHOU anon tela_dividas';
  assert has_function_privilege('authenticated', 'public.tela_dividas(smallint,date)', 'execute'), 'FALHOU authenticated tela_dividas';
  ok := false; begin perform public.tela_dividas(0::smallint, h); perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true); perform public.tela_dividas(0::smallint, h); exception when others then ok := true; end;
  assert ok, 'FALHOU usuario sem permissao';

  raise exception 'OK-ROLLBACK';
end $$;
