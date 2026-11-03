-- Teste da migration 43 (dados inventados, termina em rollback)
do $$
declare adm uuid; tp bigint; tp2 bigint; tr bigint; n int; msg text;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo)
    values ('pagar',1,'TESTE-TP','Aberto','2026-10-01',100,100,'Dup') returning id into tp;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo)
    values ('pagar',1,'TESTE-TP2','Aberto','2026-10-02',200,200,'Dup') returning id into tp2;
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo)
    values ('receber',1,'TESTE-TR','Aberto','2026-10-01',100,100,'Dup') returning id into tr;

  n := public.tratar_titulos(array[tp], 'pagar_em', '2026-11-20', 'combinado');
  assert n = 1, 'FALHOU: devolve 1';
  assert (select decisao from public.titulos_tratativa where titulo_id = tp) = 'pagar_em', 'FALHOU: grava pagar_em';
  assert (select nova_data from public.titulos_tratativa where titulo_id = tp) = '2026-11-20', 'FALHOU: grava a data';
  assert (select por from public.titulos_tratativa where titulo_id = tp) = adm, 'FALHOU: grava quem';

  perform public.tratar_titulos(array[tp], 'em_disputa', null, null);
  assert (select decisao from public.titulos_tratativa where titulo_id = tp) = 'em_disputa', 'FALHOU: troca a decisao';
  assert (select count(*) from public.titulos_tratativa) = 1, 'FALHOU: uma linha por titulo';
  assert (select count(*) from public.titulos_tratativa_eventos where titulo_id = tp) = 2, 'FALHOU: historico com 2 eventos';

  -- lote: dois títulos a pagar de uma vez
  n := public.tratar_titulos(array[tp, tp2], 'nao_e_divida', null, 'corrigir no Santri');
  assert n = 2, 'FALHOU: lote devolve 2';
  assert (select count(*) from public.titulos_tratativa where titulo_id in (tp, tp2) and decisao = 'nao_e_divida') = 2, 'FALHOU: lote grava os dois';

  -- validações
  msg := null;
  begin perform public.tratar_titulos(array[tp], 'pagar_em', null, null); exception when others then msg := sqlerrm; end;
  assert msg = 'Informe a data', 'FALHOU: pagar_em sem data -> ' || coalesce(msg, 'sem erro');
  msg := null;
  begin perform public.tratar_titulos(array[tp], 'prometeu', '2026-11-20', null); exception when others then msg := sqlerrm; end;
  assert msg = 'Decisão não vale para contas a pagar', 'FALHOU: prometeu no pagar -> ' || coalesce(msg, 'sem erro');
  msg := null;
  begin perform public.tratar_titulos(array[tr], 'em_disputa', null, null); exception when others then msg := sqlerrm; end;
  assert msg = 'Decisão não vale para contas a receber', 'FALHOU: em_disputa no receber -> ' || coalesce(msg, 'sem erro');
  msg := null;
  begin perform public.tratar_titulos(array[tp], 'inventada', null, null); exception when others then msg := sqlerrm; end;
  assert msg is not null, 'FALHOU: decisao desconhecida passou';
  -- renegociado deixou de ser uma data: só pelo Renegociar (cria as parcelas), ver teste_54
  msg := null;
  begin perform public.tratar_titulos(array[tp], 'renegociado', '2026-11-20', null); exception when others then msg := sqlerrm; end;
  assert msg = 'Use Renegociar, que cria as parcelas', 'FALHOU renegociado -> ' || coalesce(msg, 'sem erro');
  perform public.tratar_titulos(array[tr], 'perdido', null, null);
  assert (select decisao from public.titulos_tratativa where titulo_id = tr) = 'perdido', 'FALHOU: perdido no receber';

  -- sem papel financeiro não grava
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  msg := null;
  begin perform public.tratar_titulos(array[tp], 'para_diretoria', null, null); exception when others then msg := sqlerrm; end;
  assert msg is not null, 'FALHOU: usuario sem permissao gravou';

  raise exception 'OK-ROLLBACK';
end $$;
