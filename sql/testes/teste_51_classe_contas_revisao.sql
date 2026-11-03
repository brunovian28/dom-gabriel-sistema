-- Teste da migration 51 (só funções, termina em rollback)
do $$
begin
  assert interno.grupo_caixa_padrao('COMPRA DE MERCADORIA ESTOQUE') = 'fornecedor', 'FALHOU compra de mercadoria';
  assert interno.grupo_caixa_padrao('LOJA NOVA IMOBILIZADO (TESTE)') = 'outros', 'FALHOU imobilizado';
  assert interno.grupo_caixa_padrao('COMPRA DE VEICULOS') = 'outros', 'FALHOU veiculos';
  assert interno.grupo_caixa_padrao('PIX') = 'outros', 'FALHOU pix';
  assert interno.grupo_caixa_padrao('CONTRIBUICAO SOCIAL') = 'impostos', 'FALHOU csll';
  -- o que já era certo continua
  assert interno.grupo_caixa_padrao('DESPESAS COM CARTORIO') = 'fixo', 'FALHOU cartorio';
  assert interno.grupo_caixa_padrao('ENERGIA') = 'fixo', 'FALHOU energia';
  assert interno.grupo_caixa_padrao('FORNECEDORES') = 'fornecedor', 'FALHOU fornecedores';
  assert interno.grupo_caixa_padrao('IMPOSTOS FEDERAIS - PARCELAMENTO') = 'divida', 'FALHOU parcelamento';
  -- nenhuma conta não revisada fica fixa fora de pessoal/fixo
  assert not exists (select 1 from public.plano_contas_classe where not revisado and fixa and grupo_caixa not in ('pessoal','fixo')), 'FALHOU fixa fora do grupo';
  assert not exists (select 1 from public.plano_contas_classe where not revisado and fixa and plano_nome ~* 'COMPRA DE MERCADORIA|IMOBILIZADO'), 'FALHOU carga';
  raise exception 'OK-ROLLBACK';
end $$;
