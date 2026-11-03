-- Migration 57d: tela_compras liga item vendido -> compra por junção, não por varredura
-- Antes: para cada item vendido (180 dias) percorria todos os itens comprados (400 dias), ~4,8 milhões de comparações (~1,3 s).
-- Agora: candidatos por código igual (prioridade 0) ou família+marca igual (prioridade 1), mesma janela de datas,
--        e fica o de menor prioridade, depois a data mais antiga. Desempate no mesmo dia: menor número de compra (antes era ao acaso).
-- Conferido: mesmas 1.504 ligações e mesmas datas de compra. Troca feita no texto atual da função.

do $$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public.tela_compras(smallint)'::regprocedure);
  d2 := regexp_replace(d,
    'left join lateral \(select ci\.numero, ci\.d from ci\s+where ci\.loja_id = vi\.loja_id and ci\.d between vi\.f - 3 and vi\.f \+ 150\s+and \(ci\.codigo = vi\.codigo or \(vi\.fam is not null and ci\.fam = vi\.fam and ci\.marca = vi\.marca\)\)\s+order by \(ci\.codigo = vi\.codigo\) desc, ci\.d limit 1\) l on true',
    'left join lig_pick l on l.id = vi.id and l.ordem = vi.ordem');
  if d2 = d then raise exception 'trecho da ligação não encontrado em tela_compras'; end if;
  d := regexp_replace(d2, 'lig as materialized \(',
    'lig_cand as (' || chr(10)
    || '    select vi.id, vi.ordem, 0 pri, ci.numero, ci.d from vi join ci on ci.loja_id = vi.loja_id and ci.codigo = vi.codigo and ci.d between vi.f - 3 and vi.f + 150' || chr(10)
    || '    union all' || chr(10)
    || '    select vi.id, vi.ordem, 1, ci.numero, ci.d from vi join ci on ci.loja_id = vi.loja_id and ci.fam = vi.fam and ci.marca = vi.marca and ci.d between vi.f - 3 and vi.f + 150 where vi.fam is not null),' || chr(10)
    || '  lig_pick as (select distinct on (id, ordem) id, ordem, numero, d from lig_cand order by id, ordem, pri, d, numero),' || chr(10)
    || '  lig as materialized (');
  if d = d2 then raise exception 'CTE lig não encontrada em tela_compras'; end if;
  execute d;
end $$;
