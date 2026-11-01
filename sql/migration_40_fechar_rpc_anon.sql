-- Migration 40 — funções SECURITY DEFINER do schema public não podem ser chamadas sem login.
-- Elas já checam papel e loja por dentro (quem não tem login recebe "sem acesso");
-- isto é uma segunda tranca: o papel anon perde o EXECUTE. Nada muda para usuário logado.
-- Também impede que funções novas nasçam executáveis por anon.

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as assinatura
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.prorettype <> 'trigger'::regtype
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  loop
    execute format('revoke execute on function %s from anon, public', f.assinatura);
    execute format('grant execute on function %s to authenticated, service_role', f.assinatura);
  end loop;
end $$;

alter default privileges in schema public revoke execute on functions from anon, public;
