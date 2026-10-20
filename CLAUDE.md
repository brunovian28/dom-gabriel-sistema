# Sistema interno Dom Gabriel — instruções para a Claude

Duas pessoas trabalham neste repositório, cada uma com a própria Claude: **Bruno** (dono, direção) e **Luis** (ajuda no desenvolvimento). Uma Claude não vê as conversas da outra. A memória comum é este repositório.

## Ao começar qualquer conversa
1. `git pull` (ou clone novo) do `main`.
2. Ler `docs/ALTERACOES.md` (o que mudou e quem mudou), `docs/HANDOFF.md` (como tudo funciona) e `docs/PROXIMOS_PASSOS.md` (o que está em aberto).
3. Conferir no Supabase (projeto `dom-gabriel-sistema`, id `vmpxssoyqfdnnyhnvkyl`) a lista de migrations e comparar com `sql/` e com o registro.
4. Contar à pessoa, em poucas linhas, o que mudou desde a última conversa dela.

## Ao terminar qualquer alteração
1. Testar (ver "Testes" em `docs/HANDOFF.md`).
2. Commit e push no `main` (GitHub Pages publica em ~1 min).
3. Acrescentar uma linha **no topo** da tabela de `docs/ALTERACOES.md`: data · quem · o que mudou · migration · commit.
4. Se mudou regra, tabela, RPC ou tela: atualizar a seção certa de `docs/HANDOFF.md`.
5. SQL novo vai para `sql/migration_NN_nome.sql`.

## Regras
- **Faça, não mostre.** Edite os arquivos no repositório, teste, faça commit e push você mesma; mude o banco pelo conector do Supabase (`apply_migration`). Nunca peça para a pessoa copiar e colar código ou SQL. Se faltar permissão (GitHub sem escrita, Supabase sem a organização), diga exatamente qual conector reautorizar.
- **Migrations numeradas em sequência** (a última está em `docs/ALTERACOES.md`). Antes de criar uma, a pessoa avisa a outra para não haver dois números iguais.
- **Regra de negócio nova é decisão do Bruno/Fabio.** Pergunte antes; registre a resposta em "Decisões" do `docs/HANDOFF.md`.
- **Repositório público** (GitHub Pages gratuito). Nunca commitar: token, senha, chave `service_role`, valores financeiros da empresa, nomes ou dados de clientes. A chave publishable do Supabase no HTML é pública por desenho; a segurança está no RLS e nas RPCs.
- Cada pessoa usa o próprio token/login. Não pedir nem guardar credenciais de outra pessoa.
- Prefira desenho sem DELETE (gravar com histórico, marcar `ativo=false`).
