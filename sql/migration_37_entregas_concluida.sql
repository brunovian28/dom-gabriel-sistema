-- Migration 37 · Entregas: situação de entrega concluída no Santri é "Entrega total" (não "Total")
-- concluida_em passa a ser preenchida por gatilho; a prévia conta "Entrega total".
create or replace function interno.entrega_concluida() returns trigger
language plpgsql set search_path to '' as $$
begin
  if new.status_entrega = 'Entrega total' then
    new.concluida_em := coalesce(case when tg_op = 'UPDATE' then old.concluida_em end, new.concluida_em, (now() at time zone 'America/Cuiaba')::date);
  else
    new.concluida_em := null;
  end if;
  return new;
end $$;
create trigger entregas_concluida before insert or update on public.entregas_santri
  for each row execute function interno.entrega_concluida();
update public.entregas_santri set status_entrega = status_entrega where status_entrega = 'Entrega total';
-- + previa_importacao_entregas recriada com 'Entrega total' (texto em migration_32)
