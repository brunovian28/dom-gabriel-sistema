-- Teste da migration 42 (dados inventados, termina em rollback)
do $$
declare adm uuid; c1 bigint; c2 bigint; ok boolean;
begin
  select id into adm from public.usuarios where papel = 'admin' and ativo order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);

  update public.contas_bancarias set ativo = false where loja_id = 1;
  c1 := public.salvar_conta_bancaria(null, 1::smallint, 'BANCO TESTE', 'Conta A', true);
  c2 := public.salvar_conta_bancaria(null, 1::smallint, 'BANCO TESTE', 'Conta B', true);
  perform public.informar_saldo_conta(c1, 1000, null);
  perform public.informar_saldo_conta(c1, 1500, null);   -- vale o último
  perform public.informar_saldo_conta(c2, 500, null);
  assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 2000, 'FALHOU: soma 2000';
  assert (select count(*) from interno.saldo_caixa(array[1]::smallint[])) = 2, 'FALHOU: 2 contas';

  perform public.salvar_conta_bancaria(c2, 1::smallint, 'BANCO TESTE', 'Conta B', false);
  assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 1500, 'FALHOU: conta inativa fora da soma';

  -- saldo da loja inteira não é mais aceito (somaria com as contas, migration 46)
  ok := false;
  begin perform public.informar_saldo_caixa(1::smallint, 300, null); exception when others then ok := true; end;
  assert ok, 'FALHOU: informar_saldo_caixa deveria recusar';
  assert (select sum(saldo) from interno.saldo_caixa(array[1]::smallint[])) = 1500, 'FALHOU: soma sem a Geral';

  -- tela_compras segue com o formato do saldo
  assert (select (public.tela_compras(1::smallint)->'caixa'->0->'saldo'->>'saldo')::numeric) = 1500, 'FALHOU: tela_compras soma contas';

  perform public.salvar_parametros_caixa(1::smallint, 9900);
  assert (select caixa_minimo from public.caixa_parametros where loja_id = 1) = 9900, 'FALHOU: caixa minimo';
  perform public.salvar_parametros_caixa(1::smallint, 8800);
  assert (select caixa_minimo from public.caixa_parametros where loja_id = 1) = 8800, 'FALHOU: caixa minimo atualiza';

  -- usuário sem papel financeiro não informa saldo
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  ok := false;
  begin perform public.informar_saldo_conta(c1, 1, null); exception when others then ok := true; end;
  assert ok, 'FALHOU: sem permissao informar_saldo_conta';
  ok := false;
  begin perform public.salvar_parametros_caixa(1::smallint, 1); exception when others then ok := true; end;
  assert ok, 'FALHOU: sem permissao salvar_parametros_caixa';

  raise exception 'OK-ROLLBACK';
end $$;
