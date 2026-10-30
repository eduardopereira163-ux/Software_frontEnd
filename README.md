# ConecTorno — Site (frontend)

Site do ConecTorno, sistema do SENAI em que o professor publica desenhos técnicos (PDF ou imagem) e envia observações para os **6 monitores** dos tornos da oficina.

Este pacote contém **somente o site** (HTML, CSS, JavaScript, imagens e PDF.js). O **servidor** (Python/Flask, `app.py`, dados, senhas, uploads) **já está instalado no Raspberry Pi** e não faz parte deste repositório. Instalar significa **trocar a pasta `static` do servidor existente** por esta.

## Estrutura

```
Software_frontEnd/
├── README.md            ← este arquivo
├── instalar.sh          ← script que roda NO Raspberry: faz backup, copia e reinicia
├── monitor/             ← abre a tela do monitor sozinha, em tela cheia, ao ligar
│   ├── configurar-monitor.sh
│   └── iniciar-monitor.sh
├── dev/servidor-teste.js ← servidor FALSO para testar o site no PC (não vai para o Pi)
├── static/              ← o site (é isto que vai para o servidor)
│   ├── index.html       ← telas: painel do professor e tela do monitor
│   ├── app.js           ← toda a lógica; conversa com a API em /api/...
│   ├── style.css
│   ├── images/
│   └── pdfjs/           ← visualizador de PDF (pode ser usado pelo servidor)
└── docs/
    ├── API_COMPATIBILIDADE.md               ← rotas que o servidor precisa ter
    └── Documentacao_ConecTorno_Raspberry.pdf
```

## O que você precisa saber antes

Você vai precisar de três informações do Raspberry. Para descobri-las, acesse o Pi (`ssh pi@IP-DO-RASPBERRY`) e rode:

| Informação | Como descobrir |
|---|---|
| **Nome do serviço** | `systemctl list-units --type=service \| grep -i -E "conec\|torno\|flask\|app"` |
| **Pasta do projeto** | `systemctl cat NOME-DO-SERVICO` → linha `WorkingDirectory=` (ou o caminho do `app.py` em `ExecStart=`). A pasta certa contém o `app.py` e uma pasta `static`. |
| **Porta** | `sudo ss -tlnp \| grep -i python` (ex.: `0.0.0.0:5000` → porta 5000) |

> Se o servidor não roda como serviço do systemd (por exemplo, é iniciado à mão com `python3 app.py`), deixe o nome do serviço em branco no script e reinicie o servidor do jeito de sempre.

## Instalação no Raspberry Pi

### 1. Levar a pasta para o Pi

**Opção A — direto do GitHub (mais simples):** no Raspberry:

```bash
cd ~
git clone https://github.com/eduardopereira163-ux/Software_frontEnd.git conectorno-site
# nas próximas atualizações: cd ~/conectorno-site && git pull
```

**Opção B — copiar do computador (Windows, PowerShell):**

```powershell
scp -r .\Software_frontEnd pi@IP-DO-RASPBERRY:~/conectorno-site
```

### 2. Rodar o instalador

No Raspberry:

```bash
cd ~/conectorno-site
chmod +x instalar.sh
./instalar.sh /caminho/do/projeto NOME-DO-SERVICO http://localhost:PORTA
```

Exemplo: `./instalar.sh /home/pi/conectorno conectorno http://localhost:5000`

O script:

1. confere se a pasta informada é mesmo a do projeto (precisa ter `static/`);
2. faz **backup** da `static` atual em `static_backup_DATA-HORA/`, ao lado dela;
3. copia o site novo **por cima** — não apaga nada (uploads e outros arquivos do servidor ficam intactos);
4. reinicia o serviço (pede a senha do `sudo`);
5. testa as rotas principais da API e mostra `OK` ou `FALHA`.

Ele **não mexe** em `app.py`, configurações, banco de dados, senhas ou uploads.

### 3. Testar

| Quem | Endereço |
|---|---|
| Professor (PC) | `http://IP-DO-RASPBERRY:PORTA/` |
| Monitor 1 a 6 (em cada torno) | `http://IP-DO-RASPBERRY:PORTA/?monitor=1` … `?monitor=6` |

Confira: o painel abre direto (sem login), publicar um PDF, ver o desenho nos monitores, bolinha verde de "online" na aba **Monitores**, enviar e apagar uma observação.

> Não abra o `index.html` com dois cliques nem pelo Live Server do VS Code: o site só funciona quando é servido pelo próprio servidor do Raspberry (mesmo endereço da API).

### 4. Monitor abrindo sozinho (modo quiosque)

Configure o aparelho do monitor para, ao ligar, **esperar o servidor subir** e abrir a tela do monitor **em tela cheia, sem barra de endereço**. Assim o aluno só vê o desenho e as observações.

No aparelho do monitor (o próprio Raspberry, se a tela estiver ligada no HDMI dele):

```bash
cd ~/conectorno-site/monitor
chmod +x configurar-monitor.sh iniciar-monitor.sh
./configurar-monitor.sh http://localhost:PORTA 1
```

- Tela ligada **no próprio Pi**: use `http://localhost:PORTA`.
- Tela em **outro aparelho** (Linux com Chromium) conectado ao Wi-Fi do Pi: use `http://IP-DO-RASPBERRY:PORTA` e copie a pasta `monitor/` para ele.
- O último número é o monitor (1 a 6). Hoje há só um, então use `1`.

Depois reinicie o aparelho (`sudo reboot`). O script:

- espera o servidor responder antes de abrir (no boot ele pode demorar um pouco);
- abre o Chromium em modo quiosque e o reabre se ele fechar;
- desativa o descanso de tela, quando possível.

> O aparelho precisa iniciar **com a área de trabalho e login automático** (no Raspberry Pi OS: `sudo raspi-config` → *System Options* → *Boot / Auto Login* → *Desktop Autologin*). Se a tela ainda apagar depois de um tempo: `sudo raspi-config` → *Display Options* → *Screen Blanking* → *No*.

Sair do quiosque: `Alt+F4`. Desativar o início automático: `rm ~/.config/autostart/conectorno-monitor.desktop`.

### Desfazer

O script mostra no final o comando exato. De forma geral:

```bash
cp -a /caminho/do/projeto/static_backup_DATA-HORA/. /caminho/do/projeto/static/
sudo systemctl restart NOME-DO-SERVICO
```

## Como usar (celular ou PC do professor)

1. Conecte o celular no **Wi-Fi do Raspberry** e abra `http://IP-DO-RASPBERRY:PORTA/` (dica: adicione à tela inicial).
2. Aba **Enviar**:
   1. toque na área tracejada e escolha um **PDF ou foto** (pode tirar a foto na hora);
   2. escolha o destino — **Todos os monitores** ou um monitor específico (a bolinha verde indica monitor ligado). O app lembra a última escolha;
   3. se quiser, escreva uma **observação** — ela vai junto para o(s) monitor(es);
   4. toque em **Enviar para o Monitor 1** (o botão sempre diz para onde vai). Uma barra mostra o progresso.
3. Em poucos segundos o monitor mostra o desenho. **No ar agora** lista o que cada monitor está exibindo; **Remover tudo** limpa os monitores.
4. Aba **Monitores**: toque em um monitor para ver o que ele mostra, mandar novas observações, apagar observações antigas ou fazê-lo voltar ao projeto geral.

Na tela do monitor, a observação aparece em destaque à direita e **pisca quando chega uma nova**. Se o servidor cair, aparece "Sem conexão com o servidor" em vermelho.

> Enviar para **Todos** não substitui um projeto **exclusivo** já enviado a um monitor — o app avisa quando isso acontece. Para trocar, use **Voltar ao projeto geral** na página do monitor.

## Testar no PC (sem Raspberry)

Com o [Node.js](https://nodejs.org) instalado:

```bash
node dev/servidor-teste.js
```

Abra `http://localhost:5000` (painel) e `http://localhost:5000/?monitor=1` (monitor) em outra janela. Pelo celular na mesma rede: `http://IP-DO-PC:5000`. Esse servidor **imita** a API do Raspberry, guarda tudo só na memória e não converte PDF em imagem; serve apenas para testar o site.

## Acesso sem login

O site **não tem tela de login**: o acesso é controlado pela rede Wi-Fi do Raspberry. Ao abrir o endereço do professor, o painel entra sozinho no servidor usando as credenciais fixas definidas no topo de [static/app.js](static/app.js):

```js
const AUTO_LOGIN = { username: 'professor', password: 'conectorno-senai' };
```

- **Servidor sem conta ainda:** o site cria a conta com esses dados automaticamente.
- **Servidor que já tem conta** (criada antes, pela tela de login antiga): troque esses valores pelo usuário e senha dessa conta **antes** de rodar o instalador. Senão o painel mostra "Não foi possível entrar no servidor".
- Se a sessão expirar, o painel entra de novo sozinho.

> O Raspberry funciona como ponto de acesso (AP): emite o próprio Wi-Fi e roda o servidor. Para abrir o painel é preciso estar nesse Wi-Fi **e** digitar o endereço do Pi no navegador. Os monitores rodam em modo quiosque (sem barra de endereço), então o aluno não tem como navegar até o painel por eles.

> ⚠️ **O código mestre de recuperação não deve ficar no repositório nem no Raspberry.** Ele foi retirado desta pasta.

## Compatibilidade com o servidor

O site chama estas rotas no próprio servidor (detalhes em [docs/API_COMPATIBILIDADE.md](docs/API_COMPATIBILIDADE.md)):

`/api/auth/status`, `/api/setup`, `/api/login`, `/api/state`, `/api/upload`, `/api/project/delete`, `/api/monitor/<1-6>/project/reset`, `/api/monitor/<1-6>/note`, `/api/monitor/<1-6>/note/<id>`, `/api/monitor/<1-6>/heartbeat`, `/api/monitor/<1-6>/display`.

As telas dos monitores **não enviam token**: as rotas `heartbeat` e `display` precisam funcionar sem login.

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| "Não foi possível entrar no servidor: usuário ou senha..." | O servidor já tem uma conta com outros dados. Ajuste `AUTO_LOGIN` em `static/app.js` e rode o instalador de novo. |
| `FALHA` com HTTP `404` | O servidor não tem essa rota. O `app.py` atual é incompatível com este site. |
| `401`/`403` na tela do monitor | O servidor exige token/login para o monitor. Precisa ajustar o `app.py`. |
| HTTP `000` / "Não foi possível falar com o servidor" | Servidor parado, porta errada ou IP errado. Veja `sudo systemctl status NOME-DO-SERVICO`. |
| Login funciona, mas publicar/apagar falha | Sessão ou CSRF no servidor. Veja `sudo journalctl -u NOME-DO-SERVICO -n 50`. |
| Site novo não aparece | Cache do navegador: `Ctrl+F5`. Confira se a pasta usada no script é a mesma do serviço. |
| PDF não aparece no monitor | Confira se o upload deu certo e se `/uploads/...` abre no navegador. |

---
Desenvolvido pela turma de Desenvolvimento de Sistemas — Vespertino, SENAI.
