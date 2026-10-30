// Servidor de TESTE do ConecTorno: imita a API do Raspberry para testar o site no PC.
// NÃO é o servidor real e não deve ir para o Raspberry. Os dados ficam só na memória.
// Uso: node dev/servidor-teste.js [porta]   →   http://localhost:5000
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const PORT = Number(process.argv[2]) || 5000;
const STATIC = path.join(__dirname, '..', 'static');
const UPLOADS = fs.mkdtempSync(path.join(os.tmpdir(), 'conectorno-'));
const MAX_UPLOAD = 100 * 1024 * 1024;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.gif': 'image/gif', '.bmp': 'image/bmp', '.svg': 'image/svg+xml', '.pdf': 'application/pdf', '.ftl': 'text/plain'
};

// Estado em memória: uma conta, sessões, projeto geral e os seis monitores.
let account = null;
const sessions = new Map();
let project = null;
let version = 0;
const monitors = {};
for (let id = 1; id <= 6; id++) monitors[id] = { history: [], project: null, lastSeen: 0 };

function monitorJson(id) {
  const m = monitors[id];
  return {
    online: Date.now() - m.lastSeen < 30000,
    teacher_note: m.history.length ? m.history[m.history.length - 1].text : '',
    teacher_history: m.history,
    project: m.project,
    has_project_override: Boolean(m.project)
  };
}

function send(res, status, data, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
  res.end(JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => { size += c.length; if (size > MAX_UPLOAD + 1e6) { reject(new Error('grande')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function parseMultipart(buf, boundary) {
  const parts = {};
  const sep = Buffer.from(`--${boundary}`);
  let pos = buf.indexOf(sep) + sep.length;
  while (pos > sep.length - 1 && buf.slice(pos, pos + 2).toString() !== '--') {
    pos += 2;
    const headEnd = buf.indexOf('\r\n\r\n', pos);
    const head = buf.slice(pos, headEnd).toString('utf8');
    const next = buf.indexOf(sep, headEnd);
    const data = buf.slice(headEnd + 4, next - 2);
    const name = /name="([^"]*)"/.exec(head)[1];
    const filename = /filename="([^"]*)"/.exec(head);
    const type = /Content-Type:\s*(\S+)/i.exec(head);
    parts[name] = filename ? { filename: filename[1], type: type ? type[1] : 'application/octet-stream', data } : data.toString('utf8');
    pos = next + sep.length;
  }
  return parts;
}

function sessionOf(req) {
  const sid = /(?:^|;\s*)sid=([^;]+)/.exec(req.headers.cookie || '')?.[1];
  return sid && sessions.has(sid) ? { sid, ...sessions.get(sid) } : null;
}

function newSession(res, username) {
  const sid = crypto.randomBytes(16).toString('hex');
  const csrf = crypto.randomBytes(16).toString('hex');
  sessions.set(sid, { username, csrf });
  return { cookie: `sid=${sid}; HttpOnly; SameSite=Lax; Path=/`, csrf };
}

function sizeLabel(bytes) {
  return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

async function handleApi(req, res, url) {
  const method = req.method;
  const route = url.pathname;
  const session = sessionOf(req);
  const json = async () => { try { return JSON.parse((await readBody(req)).toString() || '{}'); } catch { return {}; } };

  // Rotas públicas.
  if (method === 'GET' && route === '/api/auth/status') {
    return send(res, 200, { ok: true, authenticated: Boolean(session), username: session?.username, csrf_token: session?.csrf, setup_available: !account });
  }
  if (method === 'POST' && route === '/api/setup') {
    if (account) return send(res, 409, { ok: false, erro: 'A conta já foi criada.' });
    const { username, password, confirmation } = await json();
    if (!username || String(password).length < 8 || password !== confirmation) return send(res, 400, { ok: false, erro: 'Dados inválidos.' });
    account = { username, password };
    const s = newSession(res, username);
    return send(res, 200, { ok: true, username, csrf_token: s.csrf }, { 'Set-Cookie': s.cookie });
  }
  if (method === 'POST' && route === '/api/login') {
    const { username, password } = await json();
    if (!account || username !== account.username || password !== account.password) return send(res, 401, { ok: false, erro: 'Usuário ou senha incorretos.' });
    const s = newSession(res, username);
    return send(res, 200, { ok: true, username, csrf_token: s.csrf }, { 'Set-Cookie': s.cookie });
  }
  let m = /^\/api\/monitor\/([1-6])\/(heartbeat|display)$/.exec(route);
  if (m) {
    const id = Number(m[1]);
    if (m[2] === 'heartbeat' && method === 'POST') { monitors[id].lastSeen = Date.now(); return send(res, 200, { ok: true }); }
    if (m[2] === 'display' && method === 'GET') return send(res, 200, { ok: true, monitor: monitorJson(id), project: monitors[id].project || project });
  }

  // Rotas do professor: exigem sessão e, se alteram dados, o token CSRF.
  if (!session) return send(res, 401, { ok: false, erro: 'Faça login.' });
  if (method !== 'GET' && req.headers['x-csrf-token'] !== session.csrf) return send(res, 403, { ok: false, erro: 'Token CSRF inválido.' });

  if (method === 'GET' && route === '/api/state') {
    const all = {};
    for (let id = 1; id <= 6; id++) all[id] = monitorJson(id);
    return send(res, 200, { ok: true, project, monitors: all });
  }
  if (method === 'POST' && route === '/api/logout') { sessions.delete(session.sid); return send(res, 200, { ok: true }); }
  if (method === 'POST' && route === '/api/upload') {
    const boundary = /boundary=(.+)$/.exec(req.headers['content-type'] || '')?.[1];
    if (!boundary) return send(res, 400, { ok: false, erro: 'Envio inválido.' });
    const parts = parseMultipart(await readBody(req), boundary);
    const file = parts.arquivo;
    if (!file || !/\.(pdf|png|jpe?g|webp|gif|bmp)$/i.test(file.filename)) return send(res, 400, { ok: false, erro: 'Use PDF ou imagem.' });
    if (file.data.length > MAX_UPLOAD) return send(res, 413, { ok: false, erro: 'Arquivo maior que 100 MB.' });
    const stored = `${Date.now()}-${file.filename.replace(/[^\w.-]/g, '_')}`;
    fs.writeFileSync(path.join(UPLOADS, stored), file.data);
    const info = {
      name: file.filename, type: file.type, url: `/uploads/${stored}`, size_label: sizeLabel(file.data.length),
      published_at: new Date().toISOString(), version: ++version
    };
    const destino = parts.destino || 'todos';
    if (destino === 'todos') { project = info; return send(res, 200, { ok: true, mensagem: 'Projeto enviado para todos os monitores.' }); }
    if (!monitors[destino]) return send(res, 400, { ok: false, erro: 'Monitor inválido.' });
    monitors[destino].project = info;
    return send(res, 200, { ok: true, mensagem: `Projeto enviado para o Monitor ${destino}.` });
  }
  if (method === 'POST' && route === '/api/project/delete') {
    project = null;
    for (let id = 1; id <= 6; id++) monitors[id].project = null;
    return send(res, 200, { ok: true, mensagem: 'Todos os projetos foram removidos.' });
  }
  if ((m = /^\/api\/monitor\/([1-6])\/project\/reset$/.exec(route)) && method === 'POST') {
    monitors[m[1]].project = null;
    return send(res, 200, { ok: true, mensagem: `Monitor ${m[1]} voltou ao projeto geral.` });
  }
  if ((m = /^\/api\/monitor\/([1-6])\/note$/.exec(route)) && method === 'POST') {
    const { note } = await json();
    if (!String(note || '').trim()) return send(res, 400, { ok: false, erro: 'Observação vazia.' });
    monitors[m[1]].history.push({ id: crypto.randomUUID(), text: String(note).trim(), created_at: new Date().toISOString() });
    return send(res, 200, { ok: true, mensagem: 'Observação enviada.' });
  }
  if ((m = /^\/api\/monitor\/([1-6])\/note\/([\w-]+)$/.exec(route)) && method === 'DELETE') {
    const history = monitors[m[1]].history;
    const index = history.findIndex((item) => item.id === m[2]);
    if (index < 0) return send(res, 404, { ok: false, erro: 'Observação não encontrada.' });
    history.splice(index, 1);
    return send(res, 200, { ok: true, mensagem: 'Observação apagada.' });
  }
  return send(res, 404, { ok: false, erro: 'Rota não encontrada.' });
}

function serveFile(res, root, relative) {
  const file = path.normalize(path.join(root, relative));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end('Não encontrado');
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname.startsWith('/api/')) return await handleApi(req, res, url);
    if (url.pathname.startsWith('/uploads/')) return serveFile(res, UPLOADS, decodeURIComponent(url.pathname.slice(9)));
    const relative = url.pathname === '/' || /^\/monitor\/[1-6]\/?$/.test(url.pathname) ? 'index.html' : decodeURIComponent(url.pathname);
    return serveFile(res, STATIC, relative);
  } catch (error) {
    send(res, 500, { ok: false, erro: error.message });
  }
}).listen(PORT, '0.0.0.0', () => {
  console.log(`Servidor de TESTE em http://localhost:${PORT}  (monitor: http://localhost:${PORT}/?monitor=1)`);
  console.log('No celular (mesma rede): http://IP-DESTE-PC:' + PORT);
});
