-- Migration 28d · o que o usuário logado pode fazer na Importadora (interno.* não aparece na API)
create or replace function public.minhas_permissoes_importacao() returns jsonb
language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'importa_algum', interno.importa_algum(),
    'direcao', coalesce(interno.ve_todas_lojas(), false),
    'importa_tudo', coalesce((select u.importa_tudo from public.usuarios u where u.id = (select auth.uid())), false))
$$;
grant execute on function public.minhas_permissoes_importacao() to authenticated;
grant execute on function public.status_relatorios() to authenticated;
grant execute on function public.salvar_relatorio_rotina(text, text, text, text, int, text[]) to authenticated;
