-- Teste da migration 47 (dados inventados, termina em rollback)
do $$
declare adm uuid; ir bigint; p jsonb; m int; ok boolean; soma numeric;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  -- as vendas de teste ficam em 2030 (a janela vem da última venda importada), assim não misturam com as vendas reais
  insert into public.importacoes(tipo,status,criado_em) values ('receber','aplicada',now()+interval '1 minute') returning id into ir;

  for m in 4..9 loop
    insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado)
    values (1,'PED','TESTE-V'||m, make_timestamp(2030,m,15,12,0,0), 6000, 3000,
            '{"impostos":600,"comissao":999,"rt":300,"frete":0,"custo_financeiro":0}'::jsonb);
    insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,pedido_numero,ultima_importacao_id,importacao_id)
    values ('receber',1,'TESTE-T'||m,'Aberto', make_date(2030,m,15) + 14, 3000, 3000, 'Duplic', 'TESTE-V'||m, ir, ir);
  end loop;
  -- devolução em setembro e uma venda em outubro (só define a janela)
  insert into public.vendas_santri(loja_id,tipo,numero,data_fechamento,vlr_liquido,custo_compra_santri,resultado)
  values (1,'DEV','TESTE-D9', make_timestamp(2030,9,20,12,0,0), 600, 300, '{}'::jsonb),
         (1,'PED','TESTE-V10', make_timestamp(2030,10,30,12,0,0), 6000, 3000, '{}'::jsonb);

  p := interno.caixa_perfil(1::smallint);
  assert p->>'ini' = '2030-04-01' and p->>'fim' = '2030-09-30', 'FALHOU janela: ' || coalesce(p->>'ini','nulo') || ' a ' || coalesce(p->>'fim','nulo');
  assert (p->>'venda_media_mes')::numeric = 5900, 'FALHOU venda media';
  assert (p->'pct'->>'custo_compra')::numeric = 0.5 and (p->'pct'->>'impostos')::numeric = 0.1 and (p->'pct'->>'comissao')::numeric = 0.05,
         'FALHOU pct (comissao = so RT, comissao de vendedor fora)';
  assert (p->'pct'->>'frete')::numeric = 0 and (p->'pct'->>'financeiro')::numeric = 0, 'FALHOU pct frete e financeiro';
  assert jsonb_array_length(p->'receb') = 53, 'FALHOU tamanho receb';
  assert round((p->'receb'->>0)::numeric, 4) = 0.5 and round((p->'receb'->>2)::numeric, 4) = 0.5, 'FALHOU perfil';
  select sum(x::numeric) into soma from jsonb_array_elements_text(p->'receb') x;
  assert round(soma, 6) = 1, 'FALHOU soma do receb = 1';
  assert interno.caixa_perfil(2::smallint) is null, 'FALHOU loja sem venda';

  perform public.salvar_datas_caixa(1::smallint, 5::smallint, 25::smallint);
  assert (select dia_comissao from public.caixa_parametros where loja_id = 1) = 5, 'FALHOU dia comissao';
  assert (select dia_impostos from public.caixa_parametros where loja_id = 1) = 25, 'FALHOU dia impostos';
  ok := false;
  begin perform public.salvar_datas_caixa(1::smallint, 31::smallint, 25::smallint); exception when others then ok := sqlerrm = 'Dia inválido'; end;
  assert ok, 'FALHOU dia 31 deveria dar Dia inválido';

  -- sem permissão
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  ok := false;
  begin perform public.salvar_datas_caixa(1::smallint, 5::smallint, 25::smallint); exception when others then ok := true; end;
  assert ok, 'FALHOU usuario sem permissao';

  raise exception 'OK-ROLLBACK';
end $$;
