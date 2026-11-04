#!/usr/bin/env python3
"""Servidor do ConecTorno: entrega o site (pasta static) e a API usada pelo painel e pelos monitores.

Usa só a biblioteca padrão do Python (não precisa de pip nem de internet).
PDFs são convertidos em imagens pelo pdftoppm (pacote poppler-utils), se estiver instalado;
sem ele, o PDF é mostrado direto pelo navegador.

Uso: python3 servidor/servidor.py [--porta 5000] [--dados PASTA]
"""
import argparse
import hashlib
import hmac
import json
import mimetypes
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

RAIZ = Path(__file__).resolve().parent.parent
STATIC = RAIZ / 'static'
MONITORES = [str(n) for n in range(1, 7)]
TAMANHO_MAXIMO = 100 * 1024 * 1024
LIMITE_JSON = 1024 * 1024
EXTENSOES = {
    '.pdf': 'application/pdf', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.webp': 'image/webp', '.gif': 'image/gif', '.bmp': 'image/bmp',
}
ONLINE_SEGUNDOS = 30  # monitor sem sinal há mais tempo que isso aparece como desligado
COOKIE = 'conectorno_sessao'
# Endereços que celulares e computadores consultam para saber se o Wi-Fi tem internet.
# O hotspot do Pi não tem, e muitos celulares derrubam o Wi-Fi quando esse teste falha.
# O instalar.sh faz o DNS do hotspot apontar esses domínios para o Pi, e o servidor responde "tem internet".
SUCESSO_APPLE = '<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>'
TESTES_DE_INTERNET = {
    '/generate_204': (204, ''), '/gen_204': (204, ''),                          # Android
    '/hotspot-detect.html': (200, SUCESSO_APPLE),                               # iPhone, Mac
    '/library/test/success.html': (200, SUCESSO_APPLE),
    '/connecttest.txt': (200, 'Microsoft Connect Test'), '/ncsi.txt': (200, 'Microsoft NCSI'),  # Windows
}

mimetypes.add_type('text/javascript', '.mjs')
mimetypes.add_type('text/javascript', '.js')
mimetypes.add_type('text/css', '.css')
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('text/plain', '.ftl')


def agora():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def log(mensagem):
    print(f'[{datetime.now():%Y-%m-%d %H:%M:%S}] {mensagem}', flush=True)


def tamanho_legivel(n):
    return f'{n / 1024 / 1024:.1f} MB' if n >= 1024 * 1024 else f'{max(1, round(n / 1024))} KB'


def hash_senha(senha, sal=None):
    sal = sal or secrets.token_hex(16)
    calculado = hashlib.pbkdf2_hmac('sha256', senha.encode(), bytes.fromhex(sal), 120_000).hex()
    return f'{sal}${calculado}'


def senha_confere(senha, guardado):
    sal, _, _ = guardado.partition('$')
    return hmac.compare_digest(hash_senha(senha, sal), guardado)


def ler_multipart(tipo, corpo):
    """Separa um envio multipart/form-data em campos de texto e arquivos (nome, bytes)."""
    achado = re.search(r'boundary="?([^";]+)"?', tipo or '')
    if not achado:
        raise ValueError('Envio inválido.')
    separador = b'--' + achado.group(1).encode()
    campos = {}
    for parte in corpo.split(separador)[1:]:
        if parte.startswith(b'--'):
            break
        cabecalho, _, dados = parte.partition(b'\r\n\r\n')
        if dados.endswith(b'\r\n'):
            dados = dados[:-2]
        texto = cabecalho.decode('utf-8', 'replace')
        nome = re.search(r'\bname="([^"]*)"', texto)
        arquivo = re.search(r'\bfilename="([^"]*)"', texto)
        if nome:
            campos[nome.group(1)] = (arquivo.group(1), dados) if arquivo else dados.decode('utf-8', 'replace')
    return campos


def achar_pdftoppm():
    """pdftoppm do sistema (Pi: poppler-utils) ou o portátil que vem no pacote do PC (pasta poppler/)."""
    programa = shutil.which('pdftoppm')
    if programa:
        return programa
    portateis = sorted((RAIZ / 'poppler').glob('**/bin/pdftoppm.exe'))
    return str(portateis[0]) if portateis else None


def converter_pdf(pdf, pasta):
    """Gera uma imagem PNG por página (até 30) para o monitor não depender do leitor de PDF."""
    programa = achar_pdftoppm()
    if not programa:
        return []
    pasta.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run([programa, '-png', '-scale-to', '2400', '-l', '30', str(pdf), str(pasta / 'pagina')],
                       check=True, timeout=180, capture_output=True)
    except (subprocess.SubprocessError, OSError) as erro:
        log(f'Não foi possível converter {pdf.name}: {erro}')
        shutil.rmtree(pasta, ignore_errors=True)
        return []
    numero = lambda p: int(re.findall(r'\d+', p.stem)[-1])
    return sorted(pasta.glob('pagina*.png'), key=numero)


class Estado:
    """Conta, projetos e observações gravados em estado.json; sessões e sinais dos monitores ficam na memória."""

    def __init__(self, pasta):
        self.pasta = pasta
        self.uploads = pasta / 'uploads'
        self.uploads.mkdir(parents=True, exist_ok=True)
        self.arquivo = pasta / 'estado.json'
        self.trava = threading.RLock()
        self.sessoes = {}
        self.vistos = {}
        self.dados = self.carregar()

    def carregar(self):
        dados = {}
        try:
            dados = json.loads(self.arquivo.read_text('utf-8'))
        except FileNotFoundError:
            pass
        except (OSError, ValueError) as erro:
            copia = self.arquivo.with_name(f'estado-corrompido-{int(time.time())}.json')
            log(f'estado.json ilegível ({erro}); guardado como {copia.name} e recomeçando vazio.')
            self.arquivo.replace(copia)
        dados.setdefault('conta', None)
        dados.setdefault('projeto', None)
        dados.setdefault('versao', 0)
        monitores = dados.setdefault('monitores', {})
        for numero in MONITORES:
            monitores.setdefault(numero, {}).setdefault('projeto', None)
            monitores[numero].setdefault('historico', [])
        return dados

    def salvar(self):
        temporario = self.arquivo.with_suffix('.tmp')
        temporario.write_text(json.dumps(self.dados, ensure_ascii=False, indent=1), 'utf-8')
        os.replace(temporario, self.arquivo)

    def limpar_uploads(self):
        """Apaga arquivos que nenhum projeto usa mais, para não encher o cartão de memória."""
        projetos = [self.dados['projeto']] + [m['projeto'] for m in self.dados['monitores'].values()]
        usados = set()
        for projeto in filter(None, projetos):
            for url in [projeto['url']] + projeto.get('image_pages', []):
                usados.add(url.split('/')[2])
        for item in self.uploads.iterdir():
            # Arquivos recentes podem ser de um envio que ainda está terminando: ficam para a próxima limpeza.
            if item.name not in usados and time.time() - item.stat().st_mtime > 600:
                shutil.rmtree(item, ignore_errors=True) if item.is_dir() else item.unlink(missing_ok=True)

    def monitor_json(self, numero):
        monitor = self.dados['monitores'][numero]
        historico = monitor['historico']
        return {
            'online': time.time() - self.vistos.get(numero, 0) < ONLINE_SEGUNDOS,
            'teacher_note': historico[-1]['text'] if historico else '',
            'teacher_history': historico,
            'project': monitor['projeto'],
            'has_project_override': monitor['projeto'] is not None,
        }


estado = None


class Requisicao(BaseHTTPRequestHandler):
    server_version = 'ConecTorno'
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        self.tratar('GET')

    def do_POST(self):
        self.tratar('POST')

    def do_DELETE(self):
        self.tratar('DELETE')

    def log_message(self, formato, *args):
        pass  # os monitores consultam a cada poucos segundos; registrar tudo encheria o log

    def tratar(self, metodo):
        caminho = unquote(urlsplit(self.path).path)
        try:
            if caminho.startswith('/api/'):
                return self.api(metodo, caminho)
            if metodo != 'GET':
                return self.responder(405, {'ok': False, 'erro': 'Método não permitido.'})
            if caminho in TESTES_DE_INTERNET:
                return self.responder_teste_internet(caminho)
            if caminho.startswith('/uploads/'):
                return self.enviar_arquivo(estado.uploads, caminho[len('/uploads/'):], cache=True)
            if caminho == '/' or re.fullmatch(r'/monitor/[1-6]/?', caminho):
                return self.enviar_arquivo(STATIC, 'index.html')
            return self.enviar_arquivo(STATIC, caminho.lstrip('/'))
        except (ConnectionError, TimeoutError):
            self.close_connection = True
        except Exception as erro:  # nunca derruba o servidor por causa de uma requisição
            log(f'Erro em {metodo} {caminho}: {erro!r}')
            self.close_connection = True
            try:
                self.responder(500, {'ok': False, 'erro': 'Erro interno do servidor.'})
            except OSError:
                pass

    # ---------- respostas ----------

    def responder(self, status, dados, cabecalhos=()):
        corpo = json.dumps(dados, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(corpo)))
        self.send_header('Cache-Control', 'no-store')
        for nome, valor in cabecalhos:
            self.send_header(nome, valor)
        self.end_headers()
        self.wfile.write(corpo)

    def responder_teste_internet(self, caminho):
        status, texto = TESTES_DE_INTERNET[caminho]
        corpo = texto.encode()
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        if corpo:
            self.send_header('Content-Length', str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def enviar_arquivo(self, raiz, relativo, cache=False):
        alvo = (raiz / relativo).resolve()
        if not alvo.is_relative_to(raiz.resolve()) or not alvo.is_file():
            return self.responder(404, {'ok': False, 'erro': 'Arquivo não encontrado.'})
        tipo = mimetypes.guess_type(alvo.name)[0] or 'application/octet-stream'
        if tipo.startswith('text/') or tipo == 'text/javascript':
            tipo += '; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', tipo)
        self.send_header('Content-Length', str(alvo.stat().st_size))
        self.send_header('Cache-Control', 'public, max-age=31536000, immutable' if cache else 'no-cache')
        self.end_headers()
        with alvo.open('rb') as arquivo:
            shutil.copyfileobj(arquivo, self.wfile)

    def ler_corpo(self, limite):
        tamanho = int(self.headers.get('Content-Length') or 0)
        if tamanho > limite:
            self.close_connection = True
            return None
        return self.rfile.read(tamanho) if tamanho else b''

    def sessao(self):
        cookie = SimpleCookie(self.headers.get('Cookie') or '')
        sid = cookie[COOKIE].value if COOKIE in cookie else ''
        with estado.trava:
            return estado.sessoes.get(sid)

    def nova_sessao(self, usuario):
        sid, csrf = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
        with estado.trava:
            estado.sessoes[sid] = {'sid': sid, 'username': usuario, 'csrf': csrf}
        cookie = f'{COOKIE}={sid}; HttpOnly; SameSite=Lax; Path=/'
        return csrf, [('Set-Cookie', cookie)]

    # ---------- API ----------

    def api(self, metodo, caminho):
        limite = TAMANHO_MAXIMO + LIMITE_JSON if caminho == '/api/upload' else LIMITE_JSON
        corpo = self.ler_corpo(limite)
        if corpo is None:
            return self.responder(413, {'ok': False, 'erro': 'O arquivo precisa ter no máximo 100 MB.'})

        def json_do_corpo():
            try:
                return json.loads(corpo or b'{}')
            except ValueError:
                return {}

        sessao = self.sessao()
        dados = estado.dados

        # Rotas públicas: estado do acesso, primeiro cadastro, login e telas dos monitores.
        if metodo == 'GET' and caminho == '/api/auth/status':
            return self.responder(200, {
                'ok': True, 'authenticated': bool(sessao), 'username': sessao and sessao['username'],
                'csrf_token': sessao and sessao['csrf'], 'setup_available': dados['conta'] is None,
            })
        if metodo == 'POST' and caminho == '/api/setup':
            pedido = json_do_corpo()
            usuario, senha = str(pedido.get('username', '')).strip(), str(pedido.get('password', ''))
            if len(usuario) < 3 or len(senha) < 8 or senha != pedido.get('confirmation'):
                return self.responder(400, {'ok': False, 'erro': 'Usuário (3+ letras) e senha (8+ caracteres) são obrigatórios.'})
            with estado.trava:
                if dados['conta'] is not None:
                    return self.responder(409, {'ok': False, 'erro': 'A conta do professor já existe.'})
                dados['conta'] = {'username': usuario, 'senha': hash_senha(senha)}
                estado.salvar()
            log(f'Conta do professor criada: {usuario}')
            csrf, cabecalhos = self.nova_sessao(usuario)
            return self.responder(200, {'ok': True, 'username': usuario, 'csrf_token': csrf}, cabecalhos)
        if metodo == 'POST' and caminho == '/api/login':
            pedido = json_do_corpo()
            conta = dados['conta']
            if not conta or pedido.get('username') != conta['username'] or not senha_confere(str(pedido.get('password', '')), conta['senha']):
                return self.responder(401, {'ok': False, 'erro': 'Usuário ou senha incorretos.'})
            csrf, cabecalhos = self.nova_sessao(conta['username'])
            return self.responder(200, {'ok': True, 'username': conta['username'], 'csrf_token': csrf}, cabecalhos)
        achado = re.fullmatch(r'/api/monitor/([1-6])/(heartbeat|display)', caminho)
        if achado:
            numero, acao = achado.groups()
            if acao == 'heartbeat' and metodo == 'POST':
                estado.vistos[numero] = time.time()
                return self.responder(200, {'ok': True})
            if acao == 'display' and metodo == 'GET':
                with estado.trava:
                    monitor = estado.monitor_json(numero)
                    projeto = monitor['project'] or dados['projeto']
                # A hora do servidor vai junto: todas as telas mostram o mesmo relógio (o do Pi).
                return self.responder(200, {'ok': True, 'monitor': monitor, 'project': projeto,
                                            'server_time': int(time.time() * 1000)})

        # Rotas do professor: exigem sessão e, quando alteram algo, o token anti-CSRF.
        if not sessao:
            return self.responder(401, {'ok': False, 'erro': 'Sessão expirada.'})
        if metodo != 'GET' and not hmac.compare_digest(self.headers.get('X-CSRF-Token') or '', sessao['csrf']):
            return self.responder(403, {'ok': False, 'erro': 'Token de segurança inválido.'})

        if metodo == 'GET' and caminho == '/api/state':
            with estado.trava:
                monitores = {n: estado.monitor_json(n) for n in MONITORES}
                return self.responder(200, {'ok': True, 'project': dados['projeto'], 'monitors': monitores})
        if metodo == 'POST' and caminho == '/api/logout':
            with estado.trava:
                estado.sessoes.pop(sessao['sid'], None)
            return self.responder(200, {'ok': True})
        if metodo == 'POST' and caminho == '/api/relogio':
            return self.acertar_relogio(json_do_corpo())
        if metodo == 'POST' and caminho == '/api/upload':
            return self.publicar(corpo)
        if metodo == 'POST' and caminho == '/api/project/delete':
            with estado.trava:
                dados['projeto'] = None
                for monitor in dados['monitores'].values():
                    monitor['projeto'] = None
                estado.salvar()
                estado.limpar_uploads()
            log('Todos os projetos removidos.')
            return self.responder(200, {'ok': True, 'mensagem': 'Todos os projetos foram removidos.'})
        achado = re.fullmatch(r'/api/monitor/([1-6])/project/reset', caminho)
        if achado and metodo == 'POST':
            numero = achado.group(1)
            with estado.trava:
                dados['monitores'][numero]['projeto'] = None
                estado.salvar()
                estado.limpar_uploads()
            mensagem = f'Monitor {numero} voltou ao projeto geral.' if dados['projeto'] else f'Projeto do Monitor {numero} removido.'
            return self.responder(200, {'ok': True, 'mensagem': mensagem})
        achado = re.fullmatch(r'/api/monitor/([1-6])/note', caminho)
        if achado and metodo == 'POST':
            texto = str(json_do_corpo().get('note', '')).strip()[:3000]
            if not texto:
                return self.responder(400, {'ok': False, 'erro': 'Digite uma observação.'})
            with estado.trava:
                historico = dados['monitores'][achado.group(1)]['historico']
                historico.append({'id': uuid.uuid4().hex, 'text': texto, 'created_at': agora()})
                del historico[:-200]  # guarda só as 200 mais recentes
                estado.salvar()
            return self.responder(200, {'ok': True, 'mensagem': 'Observação enviada.'})
        achado = re.fullmatch(r'/api/monitor/([1-6])/note/([0-9a-f-]+)', caminho)
        if achado and metodo == 'DELETE':
            numero, ident = achado.groups()
            with estado.trava:
                historico = dados['monitores'][numero]['historico']
                restantes = [item for item in historico if item['id'] != ident]
                if len(restantes) == len(historico):
                    return self.responder(404, {'ok': False, 'erro': 'Observação não encontrada.'})
                dados['monitores'][numero]['historico'] = restantes
                estado.salvar()
            return self.responder(200, {'ok': True, 'mensagem': 'Observação apagada.'})
        return self.responder(404, {'ok': False, 'erro': 'Rota não encontrada.'})

    def acertar_relogio(self, pedido):
        """O Pi não tem bateria de relógio nem internet: acerta a hora pelo celular do professor ao abrir o painel."""
        try:
            hora_celular = float(pedido.get('agora')) / 1000
        except (TypeError, ValueError):
            return self.responder(400, {'ok': False, 'erro': 'Hora inválida.'})
        diferenca = hora_celular - time.time()
        if abs(diferenca) < 60 or hora_celular < 1_700_000_000:  # já está certo, ou o celular também está errado
            return self.responder(200, {'ok': True, 'ajustado': False})
        if not hasattr(time, 'clock_settime'):
            return self.responder(200, {'ok': True, 'ajustado': False})
        try:
            time.clock_settime(time.CLOCK_REALTIME, hora_celular)  # precisa de CAP_SYS_TIME (dado pelo serviço)
        except OSError as erro:
            log(f'Não foi possível acertar o relógio pelo celular ({erro}).')
            return self.responder(200, {'ok': True, 'ajustado': False})
        log(f'Relógio acertado pelo celular do professor ({diferenca:+.0f} s).')
        return self.responder(200, {'ok': True, 'ajustado': True})

    def publicar(self, corpo):
        """Guarda o arquivo enviado, converte PDF em imagens e publica para todos ou um monitor."""
        try:
            campos = ler_multipart(self.headers.get('Content-Type'), corpo)
        except ValueError as erro:
            return self.responder(400, {'ok': False, 'erro': str(erro)})
        arquivo = campos.get('arquivo')
        destino = str(campos.get('destino') or 'todos')
        if not isinstance(arquivo, tuple) or not arquivo[1]:
            return self.responder(400, {'ok': False, 'erro': 'Escolha um arquivo.'})
        if destino != 'todos' and destino not in MONITORES:
            return self.responder(400, {'ok': False, 'erro': 'Monitor inválido.'})
        nome = Path(arquivo[0].replace('\\', '/')).name or 'arquivo'
        extensao = Path(nome).suffix.lower()
        if extensao not in EXTENSOES:
            return self.responder(400, {'ok': False, 'erro': 'Use PDF, PNG, JPG, JPEG, WEBP, GIF ou BMP.'})
        if extensao == '.pdf' and not arquivo[1].startswith(b'%PDF'):
            return self.responder(400, {'ok': False, 'erro': 'O arquivo não parece ser um PDF válido.'})

        ident = uuid.uuid4().hex[:16]
        salvo = estado.uploads / f'{ident}{extensao}'
        salvo.write_bytes(arquivo[1])
        projeto = {
            'name': nome, 'type': EXTENSOES[extensao], 'url': f'/uploads/{salvo.name}',
            'size_label': tamanho_legivel(len(arquivo[1])), 'published_at': agora(),
        }
        if extensao == '.pdf':
            paginas = converter_pdf(salvo, estado.uploads / f'{ident}-paginas')
            if paginas:
                projeto['image_pages'] = [f'/uploads/{ident}-paginas/{p.name}' for p in paginas]

        with estado.trava:
            estado.dados['versao'] += 1
            projeto['version'] = estado.dados['versao']
            if destino == 'todos':
                estado.dados['projeto'] = projeto
                mensagem = 'Projeto enviado para todos os monitores.'
            else:
                estado.dados['monitores'][destino]['projeto'] = projeto
                mensagem = f'Projeto enviado para o Monitor {destino}.'
            estado.salvar()
            estado.limpar_uploads()
        log(f'{mensagem} ({nome}, {projeto["size_label"]})')
        return self.responder(200, {'ok': True, 'mensagem': mensagem})


def main():
    parser = argparse.ArgumentParser(description='Servidor do ConecTorno')
    parser.add_argument('--porta', type=int, default=int(os.environ.get('CONECTORNO_PORTA', 5000)))
    parser.add_argument('--dados', default=os.environ.get('CONECTORNO_DADOS', str(RAIZ / 'dados')))
    args = parser.parse_args()

    global estado
    estado = Estado(Path(args.dados).resolve())
    servidor = ThreadingHTTPServer(('0.0.0.0', args.porta), Requisicao)
    servidor.daemon_threads = True
    endereco = f'http://localhost{"" if args.porta == 80 else f":{args.porta}"}'
    log(f'ConecTorno no ar em {endereco}  (monitor 1: {endereco}/?monitor=1)')
    log(f'Dados em {estado.pasta}')
    if not achar_pdftoppm():
        log('Aviso: pdftoppm não encontrado; PDFs serão mostrados sem conversão (instale poppler-utils ou use o pacote do PC).')
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    sys.exit(main())
