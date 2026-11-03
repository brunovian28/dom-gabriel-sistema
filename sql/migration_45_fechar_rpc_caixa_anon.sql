-- Migration 45: fecha para anon e public as RPCs novas do Caixa (migrations 41 a 44)
-- O alter default privileges da migration 40 só acrescenta permissão: não tira o EXECUTE que PUBLIC recebe ao criar a função.
-- Regra daqui para frente: toda função public.* nova termina com revoke ... from anon, public e grant ... to authenticated.

revoke execute on function public.lista_plano_contas() from anon, public;
revoke execute on function public.salvar_classe_conta(text, text, boolean) from anon, public;
revoke execute on function public.salvar_conta_bancaria(bigint, smallint, text, text, boolean) from anon, public;
revoke execute on function public.informar_saldo_conta(bigint, numeric, text) from anon, public;
revoke execute on function public.salvar_parametros_caixa(smallint, numeric) from anon, public;
revoke execute on function public.tratar_titulos(bigint[], text, date, text) from anon, public;
revoke execute on function public.tela_caixa(smallint, text, date) from anon, public;
revoke execute on function public.caixa_detalhe(smallint, text, date, date, text, date) from anon, public;
