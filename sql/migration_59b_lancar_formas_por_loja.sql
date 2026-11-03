-- Migration 59b: dados_lancar_pedido calcula as formas de pagamento por loja + numero.
-- interno.pagamento_pedidos() agrupa so pelo numero e misturaria PVA e RV quando o numero se repete.
create or replace function public.dados_lancar_pedido(p_loja smallint, p_numero text)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
#variable_conflict use_column
declare
  v_sis date; v_prec date; v_san date; v_formas text;
begin
  if coalesce(p_loja, 0) = 0 then raise exception 'Informe a loja'; end if;
  perform interno.lojas_tela(p_loja);
  p_numero := trim(p_numero);
  select d.previsao_entrega, d.data_cliente_precisa into v_sis, v_prec
    from public.pedido_datas d where d.loja_id = p_loja and d.numero = p_numero;
  select max(e.prev_maior) into v_san
    from public.entregas_pendentes e
    where e.loja_id = p_loja and e.pedido = p_numero
      and e.importacao_id = (select max(x.importacao_id) from public.entregas_pendentes x);
  select string_agg(distinct f.forma, ', ') into v_formas
    from public.baixas_santri b
    join public.baixas_santri_titulos t on t.baixa_id = b.id and t.ativo and t.pedido_numero = p_numero
    join public.baixas_santri_formas f on f.baixa_id = b.id and f.ativo
    where b.loja_id = p_loja and b.lado = 'receber' and b.ativo;
  return jsonb_build_object('previsao_sistema', v_sis, 'previsao_santri', v_san, 'precisa', v_prec, 'formas', v_formas);
end $f$;

revoke execute on function public.dados_lancar_pedido(smallint, text) from anon, public;
grant execute on function public.dados_lancar_pedido(smallint, text) to authenticated;
