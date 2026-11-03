# ConecTorno

Sistema do SENAI para a oficina de tornos: o professor envia desenhos técnicos (PDF ou foto) e observações **pelo celular**, e cada torno tem uma tela (**monitor**) que mostra o que o professor mandou.

Tudo roda no **Raspberry Pi**: ele emite o Wi-Fi, roda o servidor e, com uma tela ligada no HDMI, já funciona como **Monitor 1** em modo quiosque.

```
 Celular do professor ──Wi-Fi do Pi──▶ Raspberry Pi (servidor) ──HDMI──▶ Tela do torno (Monitor 1)
                                              ▲
                     Outras telas (Monitor 2 a 6) pelo Wi-Fi, se houver
```

## Estrutura

```
Software_frontEnd/
├── instalar.sh              ← instala TUDO no Pi (servidor + tela do monitor)
├── servidor/servidor.py     ← servidor (Python, sem dependências externas)
├── static/                  ← o site: painel do professor e tela do monitor
├── monitor/                 ← abre a tela do monitor em tela cheia ao ligar
│   ├── configurar-monitor.sh
│   └── iniciar-monitor.sh
├── dados/                   ← criada pelo servidor: projetos, observações e conta (não vai para o Git)
└── docs/
```

## Instalar no Raspberry Pi

Pré-requisitos: Raspberry Pi OS (32 ou 64 bits, *Lite* ou com área de trabalho), uma tela no HDMI e internet **só durante a instalação** (para baixar o conversor de PDF, o Chromium e o `cage`, se faltarem).

```bash
cd ~
git clone https://github.com/eduardopereira163-ux/Software_frontEnd.git
cd Software_frontEnd
chmod +x instalar.sh
./instalar.sh
```

O instalador (não use `sudo`; ele pede a senha quando precisar):

1. instala o `poppler-utils` (converte PDF em imagens) e o Chromium, se faltarem;
2. cria o serviço **`conectorno`**, que sobe o servidor **sozinho sempre que o Pi liga** (porta 80);
3. cria o **Wi-Fi próprio do Pi** (Access Point): pergunta o nome da rede e a senha, define o país do Wi-Fi (BR) e faz as outras redes Wi-Fi pararem de conectar sozinhas;
4. **desliga a área de trabalho**: o Pi passa a ligar em modo texto e o serviço **`conectorno-tela`** abre o **Monitor 1** em tela cheia (Chromium dentro do `cage`), sem menus, ícones ou login;
5. mostra a rede, a senha e o endereço para abrir no celular.

Depois, reinicie:

```bash
sudo reboot
```

Ao ligar, o Pi liga o Wi-Fi dele, sobe o servidor e a tela abre sozinha no Monitor 1, **mostrando o que estava no ar antes de desligar** (fica salvo em `dados/estado.json`). O painel fica em `http://10.42.0.1`.

> O Wi-Fi do Pi só liga no reinício, então a instalação inteira roda com internet. Depois disso a antena fica só como Access Point: para ter internet de novo (atualizar), ligue um **cabo de rede**.

Para não responder perguntas: `WIFI_NOME=Torno1 WIFI_SENHA=minhasenha ./instalar.sh`. Rodar o instalador de novo mantém a rede e a senha já criadas (ou troca, se você passar `WIFI_NOME`/`WIFI_SENHA`).

**Variações:**

| Comando | Resultado |
|---|---|
| `./instalar.sh` | porta 80, tela do Pi = Monitor 1 |
| `./instalar.sh 80 2` | tela do Pi = Monitor 2 |
| `./instalar.sh 80 sem-monitor` | só o servidor, sem tela |
| `./instalar.sh 5000` | servidor na porta 5000 (endereço vira `http://IP:5000`) |
| `SEM_WIFI=1 ./instalar.sh` | não cria nem altera o Wi-Fi do Pi |

### Atualizar

Com um cabo de rede ligado no Pi (o Wi-Fi dele não tem internet):

```bash
cd ~/Software_frontEnd
git pull
./instalar.sh
```

Projetos, observações e a conta ficam em `dados/` e **não se perdem** na atualização.

## Usar (celular do professor)

1. Conecte o celular no **Wi-Fi do Raspberry** e abra o endereço que o instalador mostrou (ex.: `http://10.42.0.1`). Dica: adicione à tela inicial.
2. Aba **Enviar**:
   1. toque na área tracejada e escolha um **PDF ou foto** (pode tirar a foto na hora);
   2. escolha o destino — **Todos os monitores** ou um monitor (a bolinha verde indica monitor ligado). O app lembra a última escolha;
   3. se quiser, escreva uma **observação** — ela vai junto;
   4. toque em **Enviar para o Monitor 1** (o botão sempre diz para onde vai).
3. Em poucos segundos a tela do torno mostra o desenho. **No ar agora** lista o que cada monitor exibe; **Remover tudo** limpa os monitores.
4. Aba **Monitores**: toque em um monitor para ver o que ele mostra, mandar observações, apagar observações ou fazê-lo voltar ao projeto geral.

A tela do torno é horizontal: no alto, a logo do SENAI, o número do monitor, o nome do projeto e um **relógio**; no meio, o desenho ocupando a largura toda (PDFs de várias páginas ficam com as páginas lado a lado, até 4 por tela). A **observação só aparece se o professor escreveu alguma**, numa faixa na parte de baixo, e **pisca quando chega uma nova**. PDFs são convertidos em imagens (até 30 páginas). Se o servidor cair, aparece "Sem conexão com o servidor" em vermelho.

> Enviar para **Todos** não substitui um projeto **exclusivo** já enviado a um monitor — o app avisa. Para trocar, use **Voltar ao projeto geral** na página do monitor.

### Mais telas (Monitor 2 a 6)

Em outro aparelho Linux com tela (ex.: outro Raspberry), conectado ao Wi-Fi do Pi:

```bash
git clone https://github.com/eduardopereira163-ux/Software_frontEnd.git && cd Software_frontEnd
chmod +x monitor/*.sh
./monitor/configurar-monitor.sh http://IP-DO-PI 2
sudo reboot
```

Qualquer navegador também serve: abra `http://IP-DO-PI/?monitor=2` em tela cheia (F11).

Sair do quiosque: `Alt+F4`. Desativar a abertura automática: `rm ~/.config/autostart/conectorno-monitor.desktop`.

## Acesso sem login

Não há tela de login: o acesso é controlado pelo **Wi-Fi do Raspberry**. O painel entra sozinho no servidor com as credenciais fixas de `AUTO_LOGIN` (topo de [static/app.js](static/app.js)); no primeiro acesso, a conta é criada com elas. Os monitores rodam em quiosque, sem barra de endereço, então o aluno não navega até o painel por eles.

## Testar no PC (sem Raspberry)

Com Python 3.9+ instalado, na pasta do projeto:

```bash
python servidor/servidor.py --porta 5000
```

Abra `http://localhost:5000` (painel) e `http://localhost:5000/?monitor=1` (monitor). Pelo celular na mesma rede: `http://IP-DO-PC:5000`. Sem o `pdftoppm` instalado, os PDFs aparecem sem conversão.

## Manutenção

| Situação | O que fazer |
|---|---|
| Ver se o servidor está rodando | `sudo systemctl status conectorno` |
| Ver o registro (erros, envios) | `sudo journalctl -u conectorno -f` |
| Reiniciar o servidor | `sudo systemctl restart conectorno` |
| Backup | copie a pasta `dados/` |
| Apagar tudo e começar do zero | `sudo systemctl stop conectorno && rm -rf dados && sudo systemctl start conectorno` |

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Instalador diz "o servidor não respondeu" | Outro programa usa a porta 80. Veja `sudo ss -tlnp \| grep :80` e pare-o, ou use `./instalar.sh 5000`. Detalhes: `sudo journalctl -u conectorno -n 50`. |
| Rede Wi-Fi do Pi não aparece | Veja o erro com `sudo nmcli con up ConecTorno`. Wi-Fi bloqueado: `sudo rfkill unblock wifi`. Precisa do Raspberry Pi OS com NetworkManager (não o *Legacy*). |
| Celular não abre o painel | Celular fora do Wi-Fi do Pi, ou endereço errado. Confira o IP com `hostname -I` no Pi. |
| Tela do Pi não abre sozinha (fica no login em modo texto) | Veja o erro com `sudo journalctl -u conectorno-tela -n 50`. Para mexer no Pi com a tela aberta: `Ctrl+Alt+F2` abre um terminal; `Ctrl+Alt+F1` volta. |
| Quero a área de trabalho de volta | `sudo systemctl disable conectorno-tela && sudo systemctl set-default graphical.target && sudo reboot` |
| PDF aparece com barra do leitor em vez de imagens | `poppler-utils` não instalado: conecte o Pi à internet e rode `./instalar.sh` de novo. |
| Relógio da tela errado | O Pi não tem bateria de relógio nem internet. Ele acerta a hora sozinho **quando o professor abre o painel no celular** (vale a hora do celular). À mão: `sudo date -s "2026-11-03 15:00"`. |
| "Não foi possível entrar no servidor" no painel | A conta em `dados/estado.json` foi criada com outra senha. Ajuste `AUTO_LOGIN` em `static/app.js` ou apague `dados/` para recomeçar. |

---
Desenvolvido pela turma de Desenvolvimento de Sistemas — Vespertino, SENAI.
