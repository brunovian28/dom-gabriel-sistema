-- Teste da migration 49 (dados inventados, termina em rollback).
-- Mesma estrutura do plano (hoje = quarta, dia 4, mês de 30 dias), deslocada para 2030 para não misturar com as vendas reais:
-- plano 04/11/2026 -> aqui 04/09/2030 · vendas de abr a set -> fev a jul · vendas de out -> ago · nov -> set · dez -> out
do $$
declare adm uuid; ip bigint; ir bigint; h date := '2030-09-04'; m int; ok boolean; vm record;
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
         (1,'PED','TESTE-V8', make_timestamp(2030,8,30,12,0,0), 6000, 3000, '{}'::jsonb);   -- vendas reais do mês anterior (6000)
  perform public.salvar_datas_caixa(1::smallint, 10::smallint, 20::smallint);
  insert into public.plano_contas_classe(plano_codigo, plano_nome, grupo_caixa) values ('TESTE.COM','COMISSAO DE TESTE','comissoes_rt');
  insert into public.titulos_santri(lado,loja_id,codigo,situacao,vencimento,saldo,valor_documento,tipo,plano_codigo,plano_nome,ultima_importacao_id,importacao_id)
  values ('pagar',1,'TESTE-COM','Aberto','2030-10-10',100,100,'Dup','TESTE.COM','COMISSAO DE TESTE',ip,ip);

  -- vendas futuras: entrada pelo perfil (50% na semana, 50% 14 dias depois)
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='vendas' and data = '2030-09-04') = 491.67, 'FALHOU entrada semana 0';
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='vendas' and data = '2030-09-18') = 491.67, 'FALHOU entrada k=2';
  assert (select count(*) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='vendas' and data = '2030-09-04' and grupo = 'vendas_futuras' and descricao = 'Vendas futuras (média 6 meses)') = 1, 'FALHOU grupo e descricao das vendas';
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='custo_vendas' and grupo='fornecedor' and data = '2030-09-04') = -491.67, 'FALHOU custo semana 0';
  -- comissão (só a RT, 5%) e impostos (10%) das vendas do mês anterior, pagos no mês seguinte
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='comissao_vendas' and data = '2030-09-10') = -300, 'FALHOU comissao das vendas de ago';
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='imposto_vendas' and data = '2030-09-20') = -600, 'FALHOU impostos das vendas de ago';
  assert (select descricao from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='comissao_vendas' and data = '2030-09-10') = 'RT dos arquitetos das vendas de 08/2030', 'FALHOU descricao da RT';
  -- comissão do mês corrente (27 dias estimados = 5310) menos o título já lançado de 100
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null) where origem='comissao_vendas' and data = '2030-10-10') = -165.50, 'FALHOU comissao menos o lancado';
  -- sem vendas novas: some a venda e o custo, a comissão e o imposto das vendas reais continuam
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem in ('vendas','custo_vendas')), 'FALHOU zero';
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'zero', null) where origem='comissao_vendas' and data = '2030-09-10') = -300, 'FALHOU comissao com zero';
  -- % à vista = 100: tudo entra na semana da venda
  assert (select round(sum(valor),2) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', 100) where origem='vendas' and data = '2030-09-04') = 983.33, 'FALHOU entrada 100% a vista';
  assert not exists (select 1 from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', 100) where origem='vendas' and data = '2030-09-18'), 'FALHOU nada em 18/09 com 100%';
  -- meta só em out/2030: out = 31000 (meta), set cai na média
  insert into public.metas(loja_id, mes, usuario_id, faturamento) values (1, '2030-10-01', null, 31000);
  select * into vm from interno.caixa_vendas_mes(1::smallint, h, 'meta') where mes = '2030-10-01';
  assert vm.venda = 31000 and vm.fonte = 'meta', 'FALHOU meta de outubro';
  select * into vm from interno.caixa_vendas_mes(1::smallint, h, 'meta') where mes = '2030-09-01';
  assert vm.venda = 5900 and vm.fonte = 'media', 'FALHOU setembro cai na media';
  assert (select count(*) from interno.caixa_vendas_mes(1::smallint, h, 'media')) = 12, 'FALHOU 12 meses';
  assert (select count(*) from interno.caixa_vendas_mes(1::smallint, h, 'zero') where venda = 0 and fonte = 'zero') = 12, 'FALHOU zero em vendas_mes';
  -- loja 2 sem vendas na janela: sem linhas de vendas e sem erro
  assert not exists (select 1 from interno.caixa_fluxo(array[2]::smallint[], h, 'triagem', 'media', null) where origem in ('vendas','custo_vendas','comissao_vendas','imposto_vendas')), 'FALHOU loja 2';
  -- nada fora do horizonte
  assert (select max(data) from interno.caixa_fluxo(array[1]::smallint[], h, 'triagem', 'media', null)) <= '2031-08-31', 'FALHOU horizonte';
  -- o lançado continua igual
  assert exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where titulo_id in (select id from public.titulos_santri where codigo='TESTE-COM')), 'FALHOU lancado';
  assert not exists (select 1 from interno.caixa_movimentos(array[1]::smallint[], h, 'triagem') where origem <> 'lancado'), 'FALHOU movimentos so lancado';

  raise exception 'OK-ROLLBACK';
end $$;
