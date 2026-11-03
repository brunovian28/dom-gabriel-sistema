-- Teste da migration 46 (dados inventados, termina em rollback)
do $$
declare imp bigint; dia date; tp bigint; tq bigint; tr bigint; bx bigint; r record; ok boolean; adm uuid;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.importacoes(tipo,status,criado_em) values ('pagar','aplicada',now()+interval '1 minute') returning id into imp;
  select (criado_em at time zone 'America/Cuiaba')::date into dia from public.importacoes where id = imp;

  -- P: título de 1000 com baixa parcial de 600 ANTES da foto (o saldo 400 já desconta) -> continua aberto com 400
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-P','Aberto',dia+5,400,1000,'Dup',imp,imp) returning id into tp;
  -- Q: saldo 500, baixa parcial de 200 DEPOIS da foto -> aberto com 300
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-Q','Aberto',dia+5,500,500,'Dup',imp,imp) returning id into tq;
  -- R: saldo 300, baixa de 300 depois da foto -> pago
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,ultima_importacao_id,importacao_id)
    values ('pagar',1,'TESTE-R','Aberto',dia+5,300,300,'Dup',imp,imp) returning id into tr;

  insert into public.baixas_santri(lado,loja_id,baixa,data_baixa,ativo) values ('pagar',1,'TESTE-BP',dia-30,true) returning id into bx;
  insert into public.baixas_santri_titulos(baixa_id,ordem,cod_financeiro,valor_baixado,ativo) values (bx,1,'TESTE-P',600,true);
  insert into public.baixas_santri(lado,loja_id,baixa,data_baixa,ativo) values ('pagar',1,'TESTE-BQ',dia+1,true) returning id into bx;
  insert into public.baixas_santri_titulos(baixa_id,ordem,cod_financeiro,valor_baixado,ativo) values (bx,1,'TESTE-Q',200,true);
  insert into public.baixas_santri_titulos(baixa_id,ordem,cod_financeiro,valor_baixado,ativo) values (bx,2,'TESTE-R',300,true);

  select * into r from interno.titulos_aberto('pagar', dia) where titulo_id = tp;
  assert r.status = 'aberto' and r.saldo_aberto = 400, 'FALHOU: P baixa antiga nao marca pago';
  select * into r from interno.titulos_aberto('pagar', dia) where titulo_id = tq;
  assert r.status = 'aberto' and r.saldo_aberto = 300, 'FALHOU: Q baixa parcial desconta';
  select * into r from interno.titulos_aberto('pagar', dia) where titulo_id = tr;
  assert r.status = 'pago' and r.saldo_aberto = 0, 'FALHOU: R pago por baixa';
  assert (select status from interno.titulos_status('pagar', dia) where titulo_id = tp) = 'aberto', 'FALHOU: titulos_status igual';

  assert (select valor from interno.caixa_movimentos(array[1]::smallint[], dia, 'triagem') where titulo_id = tp) = -400, 'FALHOU: P no caixa';
  assert (select valor from interno.caixa_movimentos(array[1]::smallint[], dia, 'triagem') where titulo_id = tq) = -300, 'FALHOU: Q no caixa';
  assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], dia, 'triagem') where titulo_id = tr), 'FALHOU: R fora do caixa';

  -- Q vencido: atrasado com o saldo que falta
  assert (select saldo from interno.caixa_atrasados(array[1]::smallint[], dia+10) where titulo_id = tq) = 300, 'FALHOU: atrasado com saldo parcial';

  -- saldo da loja inteira recusado
  ok := false;
  begin perform public.informar_saldo_caixa(1::smallint, 100, null); exception when others then ok := true; end;
  assert ok, 'FALHOU: informar_saldo_caixa recusa';

  raise exception 'OK-ROLLBACK';
end $$;
