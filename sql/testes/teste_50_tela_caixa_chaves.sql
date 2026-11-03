-- Teste da migration 50 (dados inventados, termina em rollback). Mesma preparação do teste_49 (2030, hoje = 04/09/2030)
do $$
declare adm uuid; ip bigint; ir bigint; conta bigint; h date := '2030-09-04'; m int; r jsonb; r2 jsonb; ok boolean; msg text;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into ip;
  for m in 2..7 loop
    insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado)
    values (1,'PED','TESTE-V'||m, make_timestamp(2030,m,15,12,0,0), 6000, 3000,
            '{"impostos":600,"comissao":999,"rt":300,"frete":0,"custo_financeiro":0}'::jsonb);
    insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,pedido_numero,ultima_importacao_id,importacao_id)
    values ('receber',1,'TESTE-T'||m,'Aberto', make_date(2030,m,15) + 14, 3000, 3000, 'Duplic', 'TESTE-V'||m, ir, ir);
  end loop;
  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado)
  values (1,'DEV','TESTE-D7', make_timestamp(2030,7,20,12,0,0), 600, 300, '{}'::jsonb),
         (1,'PED','TESTE-V8', make_timestamp(2030,8,30,12,0,0), 6000, 3000, '{}'::jsonb);
  perform public.salvar_datas_caixa(1::smallint, 10::smallint, 20::smallint);
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa) values ('TESTE.COM','COMISSAO DE TESTE','comissoes_rt');
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-COM','Aberto','2030-10-10',100,100,'Dup','TESTE.COM','COMISSAO DE TESTE',ip,ip);
  update public.contas_bancarias set ativo = false where loja_id in (1,2);
  insert into public.contas_bancarias(loja_id,banco,nome) values (1,'BANCO TESTE','Conta T') returning id into conta;
  perform public.informar_saldo_conta(conta, 10000, null);

  r := public.tela_caixa(1::smallint, 'triagem', 'media', null, h);
  assert r->>'vendas_modo' = 'media' and (r->'perfil'->0->>'venda_media_mes')::numeric = 5900, 'FALHOU perfil';
  assert (r->'perfil'->0->>'receb0')::numeric = 0.5, 'FALHOU receb0 do perfil';
  assert jsonb_array_length(r->'vendas_mes') = 12 and r->'vendas_mes'->0->>'fonte' = 'media', 'FALHOU vendas_mes';
  assert (r->'por_loja'->0->>'dia_comissao')::int = 10 and (r->'por_loja'->0->>'dia_impostos')::int = 20, 'FALHOU dias na por_loja';
  assert round((r->'semanas'->0->'grupos'->>'vendas_futuras')::numeric, 2) = 491.67, 'FALHOU vendas semana 0';
  assert round((r->'semanas'->0->'grupos_est'->>'fornecedor')::numeric, 2) = -491.67, 'FALHOU grupos_est';
  assert (r->'semanas'->0->'grupos_est'->>'clientes') is null, 'FALHOU lançado fora do grupos_est';
  assert jsonb_array_length(r->'semanas') = 13 and jsonb_array_length(r->'meses') = 12, 'FALHOU tamanhos';
  assert round((r->'meses'->0->'grupos_est'->>'vendas_futuras')::numeric, 2) > 0, 'FALHOU grupos_est no mes';

  r2 := public.tela_caixa(1::smallint, 'triagem', 'zero', null, h);
  assert (r2->'semanas'->0->'grupos'->>'vendas_futuras') is null, 'FALHOU zero';
  assert r2->>'vendas_modo' = 'zero', 'FALHOU modo zero';
  r2 := public.tela_caixa(1::smallint, 'triagem', 'media', 100, h);
  assert (r2->'perfil'->0->>'receb0')::numeric = 1 and (r2->>'entrada_pct')::numeric = 100, 'FALHOU receb0 com 100';
  assert round((r2->'semanas'->0->'grupos'->>'vendas_futuras')::numeric, 2) = 983.33, 'FALHOU 100% a vista na tela';

  -- detalhe de um valor estimado (RT das vendas de ago, paga em 10/09)
  r2 := public.caixa_detalhe(1::smallint, 'comissoes_rt', '2030-09-09', '2030-09-15', 'triagem', 'media', null, h);
  assert jsonb_array_length(r2) = 1 and r2->0->>'titulo_id' is null and r2->0->>'origem' = 'comissao_vendas'
         and r2->0->>'nome' = 'RT dos arquitetos das vendas de 08/2030', 'FALHOU detalhe estimado';

  -- erros
  ok := false; begin perform public.tela_caixa(1::smallint, 'triagem', 'xpto', null, h); exception when others then ok := sqlerrm = 'Modo de vendas inválido'; end;
  assert ok, 'FALHOU modo invalido';
  ok := false; begin perform public.tela_caixa(1::smallint, 'triagem', 'media', 150, h); exception when others then ok := sqlerrm = 'Percentual à vista inválido'; end;
  assert ok, 'FALHOU pct 150';
  ok := false; begin perform public.tela_caixa(1::smallint, 'triagem', 'media', -5, h); exception when others then ok := sqlerrm = 'Percentual à vista inválido'; end;
  assert ok, 'FALHOU pct -5';
  ok := false; begin perform public.caixa_detalhe(1::smallint, 'comissoes_rt', '2030-09-09', '2030-09-15', 'triagem', 'xpto', null, h); exception when others then ok := sqlerrm = 'Modo de vendas inválido'; end;
  assert ok, 'FALHOU modo invalido no detalhe';

  -- anon sem EXECUTE nas funções novas
  assert not has_function_privilege('anon', 'public.tela_caixa(smallint,text,text,numeric,date)', 'execute'), 'FALHOU anon tela_caixa';
  assert not has_function_privilege('anon', 'public.caixa_detalhe(smallint,text,date,date,text,text,numeric,date)', 'execute'), 'FALHOU anon caixa_detalhe';
  assert not has_function_privilege('anon', 'interno.caixa_projecao(smallint[],date,text,text,numeric)', 'execute'), 'FALHOU anon caixa_projecao';
  assert has_function_privilege('authenticated', 'public.tela_caixa(smallint,text,text,numeric,date)', 'execute'), 'FALHOU authenticated tela_caixa';
  -- as duas assinaturas existem e a antiga é atalho para a nova com 'media' e null
  assert exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tela_caixa' and p.pronargs = 3), 'FALHOU tela_caixa antiga sumiu';
  assert exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tela_caixa' and p.pronargs = 5), 'FALHOU tela_caixa nova';
  assert public.tela_caixa(1::smallint, 'triagem', h) = public.tela_caixa(1::smallint, 'triagem', 'media', null, h), 'FALHOU tela_caixa antiga <> nova';
  assert public.caixa_detalhe(1::smallint, 'comissoes_rt', '2030-09-09', '2030-09-15', 'triagem', h)
       = public.caixa_detalhe(1::smallint, 'comissoes_rt', '2030-09-09', '2030-09-15', 'triagem', 'media', null, h), 'FALHOU caixa_detalhe antiga <> nova';
  assert interno.caixa_projecao(array[1]::smallint[], h, 'triagem') = interno.caixa_projecao(array[1]::smallint[], h, 'triagem', 'media', null), 'FALHOU caixa_projecao antiga <> nova';
  -- os parâmetros novos não têm valor padrão (é isso que evita a ambiguidade no PostgREST)
  assert (select p.pronargs - p.pronargdefaults from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tela_caixa' and p.pronargs = 5) = 4, 'FALHOU defaults da tela_caixa nova';
  assert (select p.pronargs - p.pronargdefaults from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'caixa_detalhe' and p.pronargs = 8) = 7, 'FALHOU defaults do caixa_detalhe novo';

  raise exception 'OK-ROLLBACK';
end $$;
