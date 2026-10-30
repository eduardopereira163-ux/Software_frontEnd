# Compatibilidade da API do servidor existente

O frontend deste pacote chama a API na mesma origem do site, usando caminhos relativos. Ele não inicia servidor e não contém Flask.

## Rotas utilizadas

| Método | Rota | Uso |
|---|---|---|
| GET | `/api/auth/status` | Verifica se há usuário/cadastro e sessão |
| POST | `/api/setup` | Primeiro cadastro do professor |
| POST | `/api/login` | Login do professor |
| POST | `/api/logout` | Encerrar sessão |
| POST | `/api/change-password` | Alterar senha |
| POST | `/api/password/recover` | Recuperação por código mestre |
| GET | `/api/state` | Dados do painel do professor |
| POST | `/api/upload` | Enviar PDF/imagem |
| POST | `/api/project/delete` | Remover publicação geral |
| POST | `/api/monitor/<1-6>/project/reset` | Limpar projeto de um monitor |
| POST | `/api/monitor/<1-6>/note` | Criar observação |
| DELETE | `/api/monitor/<1-6>/note/<id>` | Apagar observação |
| POST | `/api/monitor/<1-6>/heartbeat` | Presença do monitor |
| GET | `/api/monitor/<1-6>/display` | Conteúdo exibido no monitor |

## Requisitos importantes

- O servidor precisa servir a pasta `static` na raiz do mesmo endereço que atende `/api/...`.
- Os monitores abrem por `/?monitor=1` até `/?monitor=6`.
- As rotas de monitor `/heartbeat` e `/display` precisam aceitar chamadas sem token, pois esta interface não envia token de monitor.
- As operações do professor continuam protegidas pela sessão de login e pelo mecanismo CSRF esperado pelo servidor.
- As respostas precisam manter o formato JSON esperado pelo frontend (`ok`, `erro`/`mensagem` e os campos de estado/projeto/observações).
- Uploads e links de arquivos precisam continuar sendo servidos pelo Raspberry, normalmente em `/uploads/...`.

## Como reconhecer incompatibilidade

- `404`: rota não existe no servidor.
- `401` ou `403` ao abrir o monitor: o servidor ainda exige autenticação/token para a tela pública, ou bloqueia heartbeat/display.
- `Failed to fetch`: endereço/origem incorreta, servidor desligado, rede/porta inacessível, ou bloqueio do navegador.
- Login funciona mas publicar/apagar falha: revisar sessão, CSRF e rotas administrativas.

Este documento descreve o contrato esperado pelo frontend extraído. Não afirma que o app.py atualmente instalado no Raspberry já implementa todas essas rotas. Faça backup e confirme a compatibilidade antes de substituir a pasta static.
