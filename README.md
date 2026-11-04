# ConecTorno

Sistema do SENAI para a oficina de tornos: o professor envia desenhos técnicos (PDF ou foto) e observações, e cada torno tem uma tela (**monitor**) que mostra o que o professor mandou.

**Formato atual:** o sistema roda no **computador do professor** (sem instalar nada: é uma pasta copiada) e o **Raspberry Pi é só a tela** do torno. O PC liga o *Hotspot móvel* do Windows; o Pi entra nessa rede sozinho e abre o monitor em tela cheia.

```
 PC do professor (Hotspot móvel + "Iniciar ConecTorno")
   │  rede Wi-Fi do PC  (o PC é sempre 192.168.137.1)
   ├──▶ Raspberry Pi ──HDMI──▶ Tela do torno (Monitor 1)
   ├──▶ outros Raspberry (Monitor 2 a 6), se houver
   └──▶ celular do professor (opcional): http://192.168.137.1:8080
```

## Estrutura

```
Software_frontEnd/
├── pc/                      ← pacote do computador do professor
│   ├── Iniciar ConecTorno.bat   (o professor abre este)
│   ├── ligar-hotspot.ps1        (liga o Hotspot móvel sem administrador)
│   ├── LEIA-ME.txt              (instruções para o professor)
│   └── montar-pacote.ps1        (gera o pacote: baixa Python portátil e conversor de PDF)
├── instalar-tela.sh         ← prepara o Raspberry como tela (entra no hotspot do PC)
├── servidor/servidor.py     ← servidor (Python, sem dependências externas)
├── static/                  ← o site: painel do professor e tela do monitor
├── monitor/                 ← tela cheia no Raspberry
│   ├── configurar-tela.sh       (liga sem área de trabalho e abre o monitor no cage)
│   ├── iniciar-monitor.sh       (abre o Chromium; reabre se fechar)
│   ├── aguardando.html          (tela de espera até o PC aparecer)
│   └── configurar-monitor.sh    (para aparelhos com área de trabalho)
├── instalar.sh              ← formato antigo: Pi como servidor e Access Point
├── dados/                   ← criada pelo servidor: projetos, observações e conta (não vai para o Git)
└── docs/
```

## 1. Gerar o pacote do PC (uma vez por versão)

Num computador com internet (o de desenvolvimento), na pasta do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File pc\montar-pacote.ps1
```

Ele baixa o **Python portátil** oficial (um zip, sem instalador) e o **Poppler** portátil (converte PDF em imagens), junta com o sistema e gera `dist\ConecTorno-PC.zip`. Copie esse zip para o computador do professor (pendrive, e-mail…) e extraia, por exemplo, na Área de Trabalho.

## 2. Computador do professor

Nada é instalado. Siga o `LEIA-ME.txt` que vem no pacote. Resumo:

**Só na primeira vez**
1. *Configurações → Rede e Internet → Hotspot móvel → Editar*:
   - nome **ConecTorno**;
   - senha **só com letras e números**;
   - banda **2,4 GHz** (o Pi 3 não enxerga 5 GHz).
2. Na mesma tela, **desligue a "Economia de energia"**. Sem isso, o Windows desliga o hotspot quando não há aparelhos conectados.
3. Abra **Iniciar ConecTorno**. Na primeira vez em cada PC, ele **libera o Firewall do Windows** sozinho: apaga os bloqueios do `python.exe` do pacote e cria a regra *ConecTorno (servidor)* na porta 8080. Para isso o Windows pede permissão de administrador; sem a senha, peça ao TI que abra o *Iniciar ConecTorno* **uma vez** com *Executar como administrador*. Nas outras vezes ele só confere.
4. Faça um teste: conecte o celular na rede ConecTorno e abra `http://192.168.137.1:8080`.
   - Se o painel abrir, os Raspberry também conseguem acessar o PC.
   - Se não abrir, o Firewall está bloqueando (veja o passo 3).

**Toda aula**
1. Deixe o PC com internet; o Windows só liga o hotspot com uma conexão ativa.
2. Abra **Iniciar ConecTorno**. Ele liga o hotspot, sobe o sistema e abre o painel em `http://localhost:8080`.
3. Ligue os Raspberry. Cada tela entra sozinha e mostra o último projeto.
4. **Deixe a janela preta aberta** durante a aula. Fechar a janela encerra o sistema.

Para usar outro computador, configure o hotspot dele com **o mesmo nome e a mesma senha**: o Pi conecta nele também. Os projetos ficam na pasta `dados` do pacote.

## 3. Raspberry Pi (tela do torno)

**Antes de tudo, confira a energia.** Se o Pi reinicia sozinho, quase sempre a fonte é fraca. Com a tela aberta, rode:

```bash
vcgencmd get_throttled
```

O resultado precisa ser `0x0`. Qualquer outro valor indica falta de energia: use a fonte oficial, de 5 V / 2,5 A no Pi 3 ou de 3 A no Pi 4.

Instalação (o Pi precisa de internet só durante ela, por cabo ou Wi-Fi):

```bash
cd ~/Software_frontEnd
git pull
chmod +x instalar-tela.sh
./instalar-tela.sh        # Monitor 1  (./instalar-tela.sh 2 para o Monitor 2, etc.)
sudo reboot
```

O script faz o seguinte:
- pergunta o **nome e a senha do hotspot do PC** e recusa símbolos, porque o teclado do Pi vem em inglês e troca alguns deles;
- **desfaz o formato antigo**: desliga o servidor do Pi e apaga o Access Point;
- faz o Pi **entrar sozinho no hotspot** sempre que ele estiver ligado;
- faz o Pi ligar **sem área de trabalho**, direto na tela do monitor.

Enquanto o PC não está pronto, a tela mostra *"Aguardando o computador do professor"* e entra no monitor sozinha quando o PC aparecer. Se o PC desligar no meio da aula, a tela mostra *"Sem conexão com o servidor"* e volta sozinha.

Sem perguntas: `WIFI_NOME=ConecTorno WIFI_SENHA=senai12345 ./instalar-tela.sh`. Outro endereço de servidor: `SERVIDOR=http://IP:PORTA ./instalar-tela.sh`.

**Monitor de pé (retrato).** A instalação já gira a imagem 90°: o layout fica em pé, com as páginas do PDF uma embaixo da outra e a observação no pé da tela. Para mudar depois, sem reinstalar:

```bash
~/Software_frontEnd/monitor/girar-tela.sh 270   # ficou de cabeça para baixo? gira para o outro lado
~/Software_frontEnd/monitor/girar-tela.sh 0     # monitor deitado
```

Para instalar já com outro giro: `GIRAR=270 ./instalar-tela.sh` ou `GIRAR=0 ./instalar-tela.sh`. Num navegador qualquer, a tela do monitor (`/?monitor=1`) **gira 90° sozinha quando a tela está deitada**, porque os monitores dos tornos ficam de pé. Com a tela em pé (celular na vertical ou tela girada no Windows) ela não gira. Para ver sem girar, acrescente `&girar=0` ao endereço; `&girar=270` gira para o outro lado.

Manutenção no Pi: `Ctrl+Alt+F2` abre um terminal; `Ctrl+Alt+F1` volta para a tela.

| Problema no Pi | O que fazer |
|---|---|
| Fica em "Aguardando o computador do professor" | No PC: hotspot ligado, em 2,4 GHz, com o mesmo nome/senha, e "Iniciar ConecTorno" aberto. No Pi: `nmcli dev status` deve mostrar `wlan0` conectado em `hotspot-professor`; `curl -I http://192.168.137.1:8080` testa se o Pi alcança o PC. |
| Reinicia sozinho | Fonte fraca: veja `vcgencmd get_throttled` acima. |
| Tela não abre (fica no login em modo texto) | `sudo journalctl -u conectorno-tela -n 50` mostra o erro. Depois de 10 falhas seguidas a tela devolve o login de propósito. |
| Wi-Fi desligado | `sudo nmcli radio wifi on && sudo rfkill unblock wifi` |

---

## Alternativa: Pi como servidor e Access Point (formato antigo)

O formato abaixo deixa tudo no Raspberry: ele cria a própria rede Wi-Fi e roda o servidor. Ele **não ficou estável** nos testes da oficina, porque o celular não conectava e o Pi reiniciava. Fica aqui só como referência.

### Instalar no Raspberry Pi

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
