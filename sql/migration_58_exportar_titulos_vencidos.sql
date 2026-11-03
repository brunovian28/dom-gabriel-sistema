-- Migration 58: exportar títulos vencidos (a pagar e a receber) para o financeiro analisar no Santri
-- Fonte: última foto de títulos + baixas posteriores (interno.titulos_aberto), só status vencido e saldo > 0.
-- Acesso: quem vê o financeiro (admin, direção, financeiro), nas lojas que pode ver.

create or replace function public.exportar_titulos_vencidos(p_loja smallint)
returns table(loja text, lado text, codigo text, documento text, nr_nota text, nome text, cadastro text, tipo text,
              plano_codigo text, plano_nome text, emissao date, vencimento date, dias_atraso integer,
              valor_documento numeric, saldo_aberto numeric, pedido text, portador text, lancado_por text, observacao text,
              triagem text, triagem_nota text)
language plpgsql stable security definer set search_path to '' as $$
#variable_conflict use_column
declare v_lojas smallint[]; v_hoje date := (now() at time zone 'America/Cuiaba')::date;
begin
  if not interno.pode_ver_financeiro() then raise exception 'sem acesso ao financeiro'; end if;
  v_lojas := interno.lojas_tela(p_loja);
  return query
  select l.codigo::text, case a.lado when 'pagar' then 'A pagar' else 'A receber' end,
         t.codigo, t.documento, t.nr_nota, t.nome, t.cadastro_codigo, t.tipo, t.plano_codigo, t.plano_nome,
         t.emissao, t.vencimento, a.dias_atraso, t.valor_documento, a.saldo_aberto, t.pedido_numero, t.portador, t.usuario, t.observacao,
         tr.decisao, tr.nota
  from (select s.*, 'pagar'::text lado from interno.titulos_aberto('pagar', v_hoje) s
        union all
        select s.*, 'receber'::text from interno.titulos_aberto('receber', v_hoje) s) a
  join public.titulos_santri t on t.id = a.titulo_id
  join public.lojas l on l.id = t.loja_id
  left join public.titulos_tratativa tr on tr.titulo_id = t.id
  where a.status = 'vencido' and a.saldo_aberto > 0 and a.loja_id = any(v_lojas)
  order by a.lado, a.dias_atraso desc, a.saldo_aberto desc;
end $$;

revoke execute on function public.exportar_titulos_vencidos(smallint) from public, anon;
grant execute on function public.exportar_titulos_vencidos(smallint) to authenticated;
