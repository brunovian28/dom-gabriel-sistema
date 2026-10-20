-- Migration 28a · Rotina de relatórios do Santri: catálogo, permissão de importar por setor, status e aviso de atraso

-- quem pode importar todos os relatórios sem ser admin (ex.: Andreza, Suelen)
alter table public.usuarios add column if not exists importa_tudo boolean not null default false;

-- catálogo dos relatórios da rotina (orientação, setor responsável, prazo)
create table if not exists public.relatorios_rotina (
  tipo text primary key,
  nome text not null,
  ordem int not null default 0,
  menu_santri text,
  filtros text,
  dicas text,
  setores text[] not null default '{}',          -- papéis que importam (além de admin/direção e "importa tudo")
  prazo_dias int not null default 3,             -- passou disso sem importar = atrasado
  tipos_importacao text[] not null default '{}', -- valores de importacoes.tipo que contam para este relatório
  disponivel boolean not null default false,     -- false = leitor ainda em construção
  ativo boolean not null default true,
  atualizado_por uuid references public.usuarios(id),
  atualizado_em timestamptz not null default now()
);
alter table public.relatorios_rotina enable row level security;
create policy rr_ler on public.relatorios_rotina for select to authenticated using ((select interno.e_ativo()));
create policy rr_upd on public.relatorios_rotina for update to authenticated
  using ((select interno.ve_todas_lojas())) with check ((select interno.ve_todas_lojas()));

insert into public.relatorios_rotina (tipo, nome, ordem, menu_santri, filtros, dicas, setores, prazo_dias, tipos_importacao, disponivel) values
('vendas','Vendas e devoluções',10,'Relatórios → Vendas → Vendas e devoluções (Analítico, com itens)',
 'Empresa da venda: as duas lojas · Tipo de movimento: Não filtrar · Status: Todos · Tipo de custo: Custo comercial · Trazer itens: marcado · Período pela Data de fechamento (últimos 30 dias)',
 'Pode importar o mesmo período quantas vezes quiser: não duplica.','{gerente}',3,'{vendas}',true),
('orcamentos','Orçamentos abertos e cancelados',20,'Relatórios → Vendas → Vendas e devoluções (Analítico, com itens)',
 'Empresa da venda: as duas lojas · Status: Orçamento (um arquivo) e Cancelado (outro arquivo) · Tipo de custo: Custo comercial · Trazer itens: marcado · Período pela Data de cadastro (desde 01/01/2026)',
 'São dois arquivos: um com Status Orçamento e outro com Status Cancelado.','{gerente}',7,'{orcamentos}',false),
('receber_baixas','Baixas de contas a receber',30,'Financeiro → Relação de Baixas de Contas a Receber (Analítico)',
 'Empresas: as duas · Tipos do documento, de pagamento e de baixa: Todos · Data da baixa (últimos 30 dias)',
 'É daqui que o sistema sabe se o cliente pagou.','{financeiro}',3,'{receber_baixas}',false),
('compras','Compras',40,'Relatórios → Compras → Relação de Compras – Analítico',
 'Status: Aberto, Baixado e Cancelado · Tipo de compra: todos · Empresas: as duas · Agrupar por fornecedor: Não · Período pela Data de cadastro (primeira vez desde 01/01/2026; depois os últimos 6 meses)',
 'Não duplica; guarda o histórico do que mudou.','{compras}',3,'{compras}',true),
('entradas','Entradas (notas de entrada)',50,'Relação de Entradas – Analítico',
 'Empresas: as duas · Período pela Data de cadastro (primeira vez desde 01/01/2026; depois os últimos 3 meses)',
 'Traz a nota, o CT-e, o frete e a compra ligada. Não duplica; guarda quando a nota foi baixada.','{compras}',3,'{entradas}',true),
('entregas','Entregas',60,'Gerenciamento de Entregas → Por Entregas (Analítico)',
 'Empresa da entrega: as duas · Tipo de controle de entrega: Não filtrar · Status do manifesto e tipo de situação: todos marcados · Tipo de busca: geradas, pendentes e sem agendamento · Data de cadastro desde 01/01/2026',
 'Mostra o que já foi entregue e o que falta entregar de cada pedido.','{logistica}',3,'{entregas}',false),
('estoque','Estoque por local',70,'Relação de Estoque por Local',
 'Uma loja por arquivo (coloque PVA_ ou RV_ no começo do nome) · Locais: todos · Tipo de estoque: positivo e negativo · Tipo de custo: custo da última entrada',
 'Guarda uma foto por dia.','{logistica}',7,'{estoque_PVA,estoque_RV}',false),
('financeiro','Contas a pagar e a receber',80,'Financeiro → Relação de Contas a Pagar / a Receber (Analítico) e Relação de Baixas de Contas a Pagar',
 'Empresas: as duas · Tipos: todos · Contas a pagar e a receber pela Data de vencimento · Baixas a pagar pela Data da baixa',
 'Guarda uma foto por dia dos saldos.','{financeiro}',7,'{pagar,receber,pagar_baixas}',false),
('dre','DRE (Demonstrativo de resultado)',90,'Financeiro → Demonstrativo de Resultado',
 'Uma loja por arquivo · Período do ano · Regime de competência · Modelo Analítico · Visão Financeira · Custo médio · Empresa de lotação do funcionário marcado · Trazer vendas diretas marcado',
 'Clique em "Visualizar/atualizar dados" antes de processar.','{financeiro}',35,'{dre_PVA,dre_RV}',false),
('precos','Formação de Custo e Preço',100,'Formação de Custo e Preço (um arquivo por loja)',
 'Renomeie o arquivo com PVA_ ou RV_ no começo do nome. Importe as duas lojas.',
 'Exportar todo mês e sempre que entrar tabela nova.','{}',35,'{precos_PVA,precos_RV}',true),
('produtos','Cadastro de produtos',110,'Relação de Produtos – Analítico',
 'Produtos ativos', 'Exportar todo mês.','{}',35,'{produtos}',true)
on conflict (tipo) do nothing;

-- pode importar este relatório?
create or replace function interno.pode_importar(p_tipo text) returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce((
    select u.ativo and (u.papel in ('admin','direcao') or u.importa_tudo
           or u.papel = any(coalesce((select r.setores from public.relatorios_rotina r
                                      where r.tipo = p_tipo or p_tipo = any(r.tipos_importacao) limit 1), '{}'::text[])))
    from public.usuarios u where u.id = (select auth.uid())), false)
$$;

-- importa algum relatório? (para entrar na Importadora)
create or replace function interno.importa_algum() returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce((
    select u.ativo and (u.papel in ('admin','direcao') or u.importa_tudo
           or exists (select 1 from public.relatorios_rotina r where r.ativo and u.papel = any(r.setores)))
    from public.usuarios u where u.id = (select auth.uid())), false)
$$;

-- situação de cada relatório: última importação, quem, se está atrasado, se é meu
create or replace function public.status_relatorios() returns table (
  tipo text, nome text, ordem int, menu_santri text, filtros text, dicas text, setores text[], prazo_dias int,
  disponivel boolean, ultima_em timestamptz, ultima_por text, ultima_arquivo text, ultima_resumo jsonb,
  faltando text[], dias numeric, atrasado boolean, meu boolean)
language sql stable security definer set search_path to '' as $$
  with r as (select * from public.relatorios_rotina where ativo and (select interno.e_ativo())),
  ult as (  -- última importação aplicada de cada tipo de importação
    select distinct on (i.tipo) i.tipo, i.criado_em, i.arquivo_nome, i.resumo, u.nome
    from public.importacoes i left join public.usuarios u on u.id = i.usuario_id
    where i.status = 'aplicada' order by i.tipo, i.criado_em desc),
  x as (
    select r.tipo,
      (select min(ult.criado_em) from unnest(r.tipos_importacao) t join ult on ult.tipo = t) mais_antiga,
      (select array_agg(t) from unnest(r.tipos_importacao) t where not exists (select 1 from ult where ult.tipo = t)) faltando
    from r)
  select r.tipo, r.nome, r.ordem, r.menu_santri, r.filtros, r.dicas, r.setores, r.prazo_dias, r.disponivel,
    case when x.faltando is null then x.mais_antiga end,
    (select ult.nome from unnest(r.tipos_importacao) t join ult on ult.tipo = t order by ult.criado_em desc limit 1),
    (select ult.arquivo_nome from unnest(r.tipos_importacao) t join ult on ult.tipo = t order by ult.criado_em desc limit 1),
    (select ult.resumo from unnest(r.tipos_importacao) t join ult on ult.tipo = t order by ult.criado_em desc limit 1),
    x.faltando,
    case when x.faltando is null then round(extract(epoch from now() - x.mais_antiga)/86400, 1) end,
    r.disponivel and (x.faltando is not null or now() - x.mais_antiga > make_interval(days => r.prazo_dias)),
    interno.pode_importar(r.tipo)
  from r join x on x.tipo = r.tipo
  order by r.ordem
$$;

-- direção ajusta orientação e prazo
create or replace function public.salvar_relatorio_rotina(p_tipo text, p_menu text, p_filtros text, p_dicas text, p_prazo int, p_setores text[])
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not interno.ve_todas_lojas() then raise exception 'Só a direção altera a rotina de relatórios'; end if;
  update public.relatorios_rotina set menu_santri = p_menu, filtros = p_filtros, dicas = p_dicas,
    prazo_dias = greatest(1, coalesce(p_prazo, prazo_dias)), setores = coalesce(p_setores, setores),
    atualizado_por = auth.uid(), atualizado_em = now()
  where tipo = p_tipo;
end $$;

-- setores passam a poder registrar e acompanhar as próprias importações
create policy importacoes_setor on public.importacoes for all to authenticated
  using (usuario_id = (select auth.uid()) and interno.pode_importar(tipo))
  with check (usuario_id = (select auth.uid()) and interno.pode_importar(tipo));
create policy cstg_setor on public.compras_staging for all to authenticated
  using (exists (select 1 from public.importacoes i where i.id = compras_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = compras_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));
create policy vstg_setor on public.vendas_staging for all to authenticated
  using (exists (select 1 from public.importacoes i where i.id = vendas_staging.importacao_id and i.usuario_id = (select auth.uid())))
  with check (exists (select 1 from public.importacoes i where i.id = vendas_staging.importacao_id and i.usuario_id = (select auth.uid()) and interno.pode_importar(i.tipo)));
