# API do servidor ConecTorno

Implementada em [servidor/servidor.py](../servidor/servidor.py). Todas as respostas são JSON com `ok` (`true`/`false`) e, em caso de erro, `erro`; ações costumam devolver `mensagem`.

## Rotas

| Método | Rota | Acesso | Uso |
|---|---|---|---|
| GET | `/api/auth/status` | público | `authenticated`, `username`, `csrf_token`, `setup_available` |
| POST | `/api/setup` | público | Cria a conta do professor (só se ainda não existir). Corpo: `username`, `password`, `confirmation` |
| POST | `/api/login` | público | Corpo: `username`, `password`. Devolve `csrf_token` e o cookie de sessão |
| POST | `/api/logout` | professor | Encerra a sessão |
| GET | `/api/state` | professor | `project` (geral) e `monitors` (`"1"` a `"6"`) |
| POST | `/api/upload` | professor | multipart: `arquivo` (PDF/imagem, até 100 MB) e `destino` (`todos` ou `1`–`6`) |
| POST | `/api/project/delete` | professor | Remove o projeto geral e todos os exclusivos |
| POST | `/api/monitor/<1-6>/project/reset` | professor | Remove o projeto exclusivo do monitor (volta ao geral) |
| POST | `/api/monitor/<1-6>/note` | professor | Corpo: `note` (até 3000 caracteres) |
| DELETE | `/api/monitor/<1-6>/note/<id>` | professor | Apaga uma observação |
| POST | `/api/monitor/<1-6>/heartbeat` | público | Sinal de vida do monitor (online por 30 s) |
| GET | `/api/monitor/<1-6>/display` | público | `monitor` e `project` que o monitor deve mostrar |

Rotas do professor exigem o cookie de sessão; as que alteram dados exigem também o cabeçalho `X-CSRF-Token`. Sem sessão: `401`; token errado: `403`.

## Formatos

**Projeto**: `name`, `type` (MIME), `url` (`/uploads/...`), `size_label`, `published_at` (ISO 8601), `version` e, para PDFs convertidos, `image_pages` (lista de URLs PNG, uma por página).

**Monitor**: `online`, `teacher_note` (observação atual = a mais recente), `teacher_history` (`id`, `text`, `created_at`), `project` (exclusivo ou `null`), `has_project_override`.

## Arquivos

- `/` e `/monitor/<n>` → `static/index.html`; demais caminhos → arquivos de `static/`.
- `/uploads/...` → arquivos enviados, em `dados/uploads/`.
- Estado em `dados/estado.json` (senha guardada como hash PBKDF2). Sessões ficam só na memória: ao reiniciar o servidor, o painel entra de novo sozinho.
