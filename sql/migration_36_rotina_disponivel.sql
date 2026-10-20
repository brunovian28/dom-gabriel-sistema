-- Migration 36 · Leitores novos liberados na Importadora (16/10/2026)
update public.relatorios_rotina set
  filtros = 'Empresas: as duas · Tipos: todos · Contas a pagar e Contas a receber pela Data de vencimento de 01/01/2025 a 31/12/2045 (assim entram os títulos antigos ainda em aberto) · Baixas de contas a pagar pela Data da baixa (desde 01/01/2026, depois os últimos 30 dias)',
  dicas = 'São três arquivos, todos neste mesmo tipo: Contas a pagar, Contas a receber e Baixas de contas a pagar. O sistema reconhece cada um pelo título. Guarda a foto do dia dos saldos (vale a última importação).'
where tipo = 'financeiro';
update public.relatorios_rotina set
  filtros = 'Uma loja por arquivo (coloque PVA_ ou RV_ no começo do nome) · Período do ano · Regime de competência · Modelo Analítico · Visão Financeira · Custo médio · Empresa de lotação do funcionário marcado · Trazer vendas diretas marcado'
where tipo = 'dre';
update public.relatorios_rotina set
  filtros = 'Empresas: as duas · Tipos do documento, de pagamento e de baixa: Todos · Data da baixa (primeira vez desde 01/01/2026, depois os últimos 30 dias)'
where tipo = 'receber_baixas';
update public.relatorios_rotina set disponivel = true
where tipo in ('orcamentos','receber_baixas','entregas','estoque','financeiro','dre');
