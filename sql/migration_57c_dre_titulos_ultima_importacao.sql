-- Migration 57c: painel_direcao e tela_financeiro sem busca linha a linha da última importação
-- DRE: a última importação era procurada de novo para cada linha (3.348 linhas x 1.687 = 5,6 milhões de leituras, ~3 s).
--      Agora é calculada uma vez por loja (dre_ult).
-- Títulos: interno.titulos_ultima_importacao(t.lado) era chamada para cada um dos 66 mil títulos.
--      Agora o par (lado, última importação) é comparado com os dois valores calculados uma vez.
-- Mesmas linhas antes e depois (conferido). A troca é feita no texto atual das funções e falha se algum trecho não for achado.

do $$
declare
  f regprocedure; v_ano text; d text;
  v_dre_old text := '(select max(x.importacao_id) from public.dre_santri x where x.loja_id = d.loja_id and x.ano = d.ano)';
  v_dre_new text := '(select u.id from dre_ult u where u.loja_id = d.loja_id)';
  v_tit_old text := 't.ultima_importacao_id = interno.titulos_ultima_importacao(t.lado)';
  v_tit_new text := '(t.lado, t.ultima_importacao_id) in ((''pagar'', interno.titulos_ultima_importacao(''pagar'')), (''receber'', interno.titulos_ultima_importacao(''receber'')))';
  v_cte text := 'dre as (select d.* from public.dre_santri d';
begin
  foreach f in array array['public.painel_direcao(smallint,date)'::regprocedure, 'public.tela_financeiro(smallint,integer)'::regprocedure] loop
    v_ano := case when f = 'public.painel_direcao(smallint,date)'::regprocedure then 'extract(year from ini)::int' else 'v_ano' end;
    d := pg_get_functiondef(f);
    if position(v_dre_old in d) = 0 or position(v_tit_old in d) = 0 or position(v_cte in d) = 0 then
      raise exception 'trecho não encontrado em %', f;
    end if;
    d := replace(d, v_dre_old, v_dre_new);
    d := replace(d, v_tit_old, v_tit_new);
    d := replace(d, v_cte, 'dre_ult as materialized (select x.loja_id, max(x.importacao_id) id from public.dre_santri x where x.loja_id = any(lojas) and x.ano = '
                           || v_ano || ' group by 1),' || chr(10) || '  ' || v_cte);
    execute d;
  end loop;
end $$;
