-- Teste da migration 41 (dados inventados, termina em rollback)
do $$
declare imp bigint; ta bigint; tb bigint; tc bigint; bx bigint; r record; n int;
begin
  -- status_titulo (hoje = 2026-11-04)
  assert interno.status_titulo('Baixado','2026-10-01',false,'2026-11-04') = 'pago', 'FALHOU: baixado';
  assert interno.status_titulo('Aberto','2026-11-04',false,'2026-11-04') = 'aberto', 'FALHOU: vence hoje';
  assert interno.status_titulo('Aberto','2026-11-03',false,'2026-11-04') = 'vencido', 'FALHOU: vencido';
  assert interno.status_titulo('Aberto','2026-11-03',true ,'2026-11-04') = 'pago', 'FALHOU: pago por baixa';
  -- heurística
  assert interno.grupo_caixa_padrao('FORNECEDORES') = 'fornecedor', 'FALHOU: fornecedor';
  assert interno.grupo_caixa_padrao('IMPOSTOS FEDERAIS - PARCELAMENTO') = 'divida', 'FALHOU: parcelamento';
  assert interno.grupo_caixa_padrao('SIMPLES') = 'divida', 'FALHOU: simples';
  assert interno.grupo_caixa_padrao('ICMS SOBRE VENDAS') = 'impostos', 'FALHOU: icms';
  assert interno.grupo_caixa_padrao('COMISSOES PAGAS A VENDEDORES') = 'comissoes_rt', 'FALHOU: comissoes';
  assert interno.grupo_caixa_padrao('SALARIOS') = 'pessoal', 'FALHOU: salarios';
  assert interno.grupo_caixa_padrao('DESPESAS COM CARTORIO') = 'fixo', 'FALHOU: cartorio';
  -- código desconhecido cai na heurística
  assert interno.grupo_caixa('9.999.999','FRETE SOBRE COMPRAS') = 'fornecedor', 'FALHOU: codigo desconhecido';
  -- código classificado manda sobre a heurística
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa) values ('TESTE.1','SALARIOS','fora');
  assert interno.grupo_caixa('TESTE.1','SALARIOS') = 'fora', 'FALHOU: tabela manda';

  -- titulos_status com dados inventados
  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into imp;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-A','Aberto','2026-11-10',10,10,'Dup',imp,imp) returning id into ta;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-B','Aberto','2026-10-20',20,20,'Dup',imp,imp) returning id into tb;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-C','Aberto','2026-10-25',30,30,'Dup',imp,imp) returning id into tc;
  insert into public.baixas_santri(lado,loja_id,baixa,ativo) values ('pagar',1,'TESTE-B1',true) returning id into bx;
  insert into public.baixas_santri_titulos(baixa_id,ordem,cod_financeiro,valor_baixado,ativo) values (bx,1,'TESTE-C',30,true);

  select * into r from interno.titulos_status('pagar','2026-11-04') where titulo_id = ta;
  assert r.status = 'aberto' and r.dias_atraso = 0, 'FALHOU: A aberto/0';
  select * into r from interno.titulos_status('pagar','2026-11-04') where titulo_id = tb;
  assert r.status = 'vencido' and r.dias_atraso = 15, 'FALHOU: B vencido/15';
  select * into r from interno.titulos_status('pagar','2026-11-04') where titulo_id = tc;
  assert r.status = 'pago' and r.dias_atraso = 0, 'FALHOU: C pago por baixa';

  raise exception 'OK-ROLLBACK';
end $$;
