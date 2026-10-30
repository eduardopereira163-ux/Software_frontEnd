(() => {
  'use strict';
  // Funções utilitárias e seletores: concentram o acesso aos elementos HTML em um único local.
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];
  const startupView = $('#startupView');
  const teacherApp = $('#teacherApp');
  const monitorView = $('#monitorView');
  const pages = { send: $('#sendPage'), monitors: $('#monitorsPage'), detail: $('#detailPage') };
  const MONITOR_IDS = [1, 2, 3, 4, 5, 6];
  const ALLOWED_EXTENSIONS = ['.pdf', '.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
  const MAX_FILE_SIZE = 100 * 1024 * 1024;
  const coarsePointer = window.matchMedia('(pointer: coarse)').matches; // celular/tablet
  const state = { data: null, page: 'send', detailId: 1, target: 'todos', file: null, previewUrl: '', sending: false };
  let csrfToken = ''; // Token anti-CSRF da sessão; não é salvo no armazenamento do navegador.
  let toastTimer; // Controla quando a mensagem temporária desaparece.
  // Credenciais fixas do painel: não há tela de login, pois só acessa quem está no Wi-Fi do Raspberry.
  // Se o servidor já tiver uma conta com outro usuário/senha, coloque aqui os dados dela.
  const AUTO_LOGIN = { username: 'professor', password: 'conectorno-senai' };

  // Cria um elemento com classe e texto opcionais (o texto nunca é interpretado como HTML).
  function el(tag, className = '', text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  // Lê e grava preferências deste aparelho (ex.: último monitor escolhido) sem quebrar se o navegador bloquear.
  const prefs = {
    get(key) { try { return localStorage.getItem(`conectorno.${key}`); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(`conectorno.${key}`, value); } catch { /* sem armazenamento local */ } }
  };
  // Exibe uma mensagem de sucesso ou erro na parte de baixo da tela.
  function toast(message, error = false) {
    const box = $('#toast');
    box.textContent = message;
    box.classList.toggle('error', error);
    box.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => box.classList.remove('show'), error ? 5000 : 3300);
  }
  // Centraliza chamadas à API e inclui proteção CSRF em ações administrativas.
  async function api(url, options = {}, retry = true) {
    const method = String(options.method || 'GET').toUpperCase();
    const headers = new Headers(options.headers || {});
    if (!['GET', 'HEAD', 'OPTIONS'].includes(method) && csrfToken) {
      headers.set('X-CSRF-Token', csrfToken);
    }
    let response;
    try {
      response = await fetch(url, { credentials: 'same-origin', ...options, headers });
    } catch {
      throw new Error('Sem conexão com o servidor. Confira se está no Wi-Fi do Raspberry.');
    }
    // Sessão do painel expirou: entra de novo sozinho e repete a chamada uma única vez.
    if ((response.status === 401 || response.status === 403) && retry && monitorView.hidden) {
      await ensureSession();
      return api(url, options, false);
    }
    let data;
    try { data = await response.json(); } catch { data = {}; }
    if (!response.ok || data.ok === false) throw new Error(data.erro || data.mensagem || 'Não foi possível concluir a operação.');
    return data;
  }
  // Atalho para POST com corpo JSON.
  function postJson(url, body = {}) {
    return api(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  }
  // Garante a sessão do professor: reaproveita a atual, cria a conta no primeiro acesso ou entra com AUTO_LOGIN.
  async function ensureSession() {
    let result = await api('/api/auth/status', {}, false);
    if (!result.authenticated) {
      const { username, password } = AUTO_LOGIN;
      result = result.setup_available
        ? await api('/api/setup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username, password, confirmation: password }) }, false)
        : await api('/api/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username, password }) }, false);
    }
    csrfToken = result.csrf_token || '';
  }
  // Envia o arquivo com XMLHttpRequest para mostrar o progresso (fetch não informa o andamento do envio).
  function sendUpload(body, onProgress) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open('POST', '/api/upload');
      if (csrfToken) xhr.setRequestHeader('X-CSRF-Token', csrfToken);
      xhr.upload.onprogress = (event) => { if (event.lengthComputable) onProgress(event.loaded / event.total); };
      xhr.onload = () => {
        let data;
        try { data = JSON.parse(xhr.responseText); } catch { data = {}; }
        resolve({ status: xhr.status, data });
      };
      xhr.onerror = () => reject(new Error('A conexão caiu durante o envio. Tente de novo.'));
      xhr.send(body);
    });
  }
  // Publica o arquivo; se a sessão tiver expirado, entra de novo e repete o envio.
  async function uploadProject(body, onProgress) {
    let { status, data } = await sendUpload(body, onProgress);
    if (status === 401 || status === 403) {
      await ensureSession();
      ({ status, data } = await sendUpload(body, onProgress));
    }
    if (status < 200 || status >= 300 || data.ok === false) throw new Error(data.erro || data.mensagem || 'Não foi possível enviar o arquivo.');
    return data;
  }
  // Formata uma data devolvida pelo servidor segundo o padrão brasileiro.
  function fmtDate(value) {
    if (!value) return '';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
  }
  // Mostra o tamanho do arquivo em KB ou MB.
  function fmtSize(bytes) {
    return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
  }
  // Junta nomes em português: "Monitor 1, Monitor 2 e Monitor 3".
  function joinNames(names) {
    return names.length > 1 ? `${names.slice(0, -1).join(', ')} e ${names[names.length - 1]}` : names.join('');
  }
  function isImage(project) {
    return String(project?.type || '').startsWith('image/');
  }
  // Páginas PNG geradas pelo servidor a partir de um PDF (quando ele faz a conversão).
  function pageUrlsOf(project) {
    return Array.isArray(project?.image_pages)
      ? project.image_pages.map((page) => typeof page === 'string' ? page : page?.url).filter((url) => typeof url === 'string' && url.length > 0)
      : [];
  }
  function monitorOf(id) {
    return state.data?.monitors?.[String(id)] || {};
  }
  // Projeto que o monitor está mostrando: o exclusivo dele ou, se não houver, o geral.
  function projectOf(id) {
    return monitorOf(id).project || state.data?.project || null;
  }

  // Exibe o projeto num quadro: páginas convertidas, imagem, PDF ou aviso de vazio.
  // Só recria o conteúdo quando o projeto muda, para a tela não piscar a cada atualização.
  function setProjectViewer(container, project, { monitor = false } = {}) {
    const pageUrls = pageUrlsOf(project);
    let key;
    let build;
    if (pageUrls.length) {
      key = `pages|${project.version || 1}|${pageUrls.join('|')}`;
      build = () => {
        const wrap = el('div', `viewer-pages${pageUrls.length === 1 ? ' single' : ''}`);
        wrap.setAttribute('aria-label', 'Páginas do projeto técnico');
        pageUrls.forEach((url, index) => {
          const img = el('img');
          img.src = url;
          img.alt = `Página ${index + 1} do projeto técnico`;
          img.loading = index === 0 ? 'eager' : 'lazy';
          img.decoding = 'async';
          wrap.append(img);
        });
        return wrap;
      };
    } else if (project?.type === 'application/pdf' && project?.image_conversion_error) {
      // Em vez de exibir um PDF que o servidor não conseguiu converter, mostra a causa provável.
      key = `error|${project.image_conversion_error}`;
      build = () => el('div', 'viewer-message error', project.image_conversion_error);
    } else if (project?.url) {
      const url = String(project.url);
      if (isImage(project)) {
        key = `img|${url}`;
        build = () => {
          const img = el('img', 'viewer-image');
          img.src = url;
          img.alt = 'Projeto técnico publicado';
          return img;
        };
      } else if (coarsePointer && !monitor) {
        // Celulares não mostram PDF dentro da página: oferece abrir o arquivo.
        key = `file|${url}`;
        build = () => {
          const box = el('div', 'viewer-message');
          const open = el('a', 'btn btn-secondary', 'Abrir PDF');
          open.href = url;
          open.target = '_blank';
          open.rel = 'noopener';
          box.append(el('span', 'file-badge', 'PDF'), el('strong', '', project.name || 'Projeto'), open);
          return box;
        };
      } else {
        // No monitor, esconde a barra do leitor de PDF e ajusta à largura.
        const src = monitor && /\.pdf$/i.test(url) ? `${url}#toolbar=0&navpanes=0&view=FitH` : url;
        key = `pdf|${src}`;
        build = () => {
          const frame = el('iframe');
          frame.src = src;
          frame.title = 'Projeto técnico publicado';
          return frame;
        };
      }
    } else {
      key = `empty|${monitor}`;
      build = () => {
        const box = el('div', 'viewer-message');
        box.append(el('span', 'file-badge', 'PDF'), el('p', '', monitor ? 'Aguardando o professor enviar um projeto' : 'Nenhum projeto publicado'));
        return box;
      };
    }
    if (container.dataset.viewKey === key) return;
    container.dataset.viewKey = key;
    container.replaceChildren(build());
  }
  // Miniatura de um projeto para cartões e listas.
  function projectThumb(project) {
    const box = el('div', 'thumb');
    const src = pageUrlsOf(project)[0] || (isImage(project) ? project.url : '');
    if (src) {
      const img = el('img');
      img.src = src;
      img.alt = '';
      img.loading = 'lazy';
      box.append(img);
    } else {
      box.append(el('span', 'file-badge', project ? 'PDF' : '—'));
    }
    return box;
  }
  function statusPill(online) {
    return el('span', `status-pill${online ? ' online' : ''}`, online ? 'Conectado' : 'Desligado');
  }

  // ---------- ENVIAR ----------

  // Cria as opções de destino uma única vez; depois só atualiza o estado de cada monitor.
  function buildTargets() {
    const options = ['todos'].concat(MONITOR_IDS.map(String));
    $('#targetGrid').replaceChildren(...options.map((value) => {
      const option = el('label', `target-option${value === 'todos' ? ' all' : ''}`);
      const input = el('input');
      input.type = 'radio';
      input.name = 'target';
      input.value = value;
      input.addEventListener('change', () => setTarget(value));
      const label = el('span', 'target-label');
      if (value === 'todos') {
        label.textContent = 'Todos os monitores';
        option.append(input, label);
      } else {
        label.append(el('small', '', 'Monitor'), el('strong', '', value));
        option.append(input, label, el('span', 'status-dot'));
      }
      return option;
    }));
  }
  function updateTargets() {
    $$('#targetGrid input').forEach((input) => {
      input.checked = input.value === state.target;
      const dot = input.parentElement.querySelector('.status-dot');
      if (dot) {
        const online = Boolean(monitorOf(input.value).online);
        dot.classList.toggle('online', online);
        dot.title = online ? 'Conectado' : 'Desligado';
      }
    });
  }
  // Escolhe o destino do envio e lembra a escolha neste aparelho.
  function setTarget(value) {
    state.target = value === 'todos' || MONITOR_IDS.includes(Number(value)) ? String(value) : 'todos';
    prefs.set('target', state.target);
    updateTargets();
    updateSendForm();
  }
  // Atualiza o texto do botão e a dica abaixo dos destinos.
  function updateSendForm() {
    const target = state.target;
    const button = $('#sendButton');
    if (!state.sending) {
      button.textContent = target === 'todos' ? 'Enviar para todos os monitores' : `Enviar para o Monitor ${target}`;
      button.disabled = !state.file;
    }
    let hint = '';
    if (state.data && target === 'todos') {
      const exclusive = MONITOR_IDS.filter((id) => monitorOf(id).has_project_override).map((id) => `Monitor ${id}`);
      hint = exclusive.length === 1 ? `O ${exclusive[0]} tem um projeto exclusivo e vai continuar mostrando ele.`
        : exclusive.length ? `${joinNames(exclusive)} têm projetos exclusivos e vão continuar mostrando eles.`
        : 'Todos os monitores vão mostrar este arquivo.';
    } else if (state.data) {
      hint = monitorOf(target).online
        ? `Só o Monitor ${target} vai mudar. Os outros continuam como estão.`
        : `O Monitor ${target} está desligado agora. Ele mostrará o arquivo quando ligar.`;
    }
    $('#targetHint').textContent = hint;
  }
  // Valida e guarda o arquivo escolhido (pelo seletor ou arrastando para a área).
  function chooseFile(file) {
    if (!file) return;
    const name = file.name.toLowerCase();
    if (!ALLOWED_EXTENSIONS.some((ext) => name.endsWith(ext))) {
      toast('Use um PDF ou uma imagem (JPG, PNG, WEBP, GIF ou BMP).', true);
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      toast('O arquivo precisa ter no máximo 100 MB.', true);
      return;
    }
    state.file = file;
    renderChosenFile();
  }
  function clearFile() {
    state.file = null;
    renderChosenFile();
  }
  // Mostra o arquivo escolhido com miniatura (fotos) ou o selo PDF.
  function renderChosenFile() {
    const file = state.file;
    $('#filePicker').hidden = Boolean(file);
    $('#fileChosen').hidden = !file;
    $('#fileInput').value = '';
    if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = '';
    if (file) {
      $('#fileName').textContent = file.name;
      $('#fileSize').textContent = fmtSize(file.size);
      if (file.type.startsWith('image/')) {
        state.previewUrl = URL.createObjectURL(file);
        const img = el('img');
        img.src = state.previewUrl;
        img.alt = '';
        $('#fileThumb').replaceChildren(img);
      } else {
        $('#fileThumb').replaceChildren(el('span', 'file-badge', 'PDF'));
      }
    }
    updateSendForm();
  }
  function setProgress(fraction) {
    const percent = Math.round(fraction * 100);
    $('#uploadProgressBar').style.width = `${percent}%`;
    $('#uploadProgressText').textContent = percent >= 100 ? 'Processando no servidor...' : `${percent}%`;
  }
  // Lista o que está no ar agora: projeto geral e projetos exclusivos.
  function renderSummary() {
    const rows = [];
    if (state.data?.project) rows.push(['Todos os monitores', state.data.project]);
    MONITOR_IDS.forEach((id) => {
      const monitor = monitorOf(id);
      if (monitor.has_project_override && monitor.project) rows.push([`Só no Monitor ${id}`, monitor.project]);
    });
    $('#liveSummary').hidden = !rows.length;
    $('#liveList').replaceChildren(...rows.map(([where, project]) => {
      const row = el('div', 'live-row');
      const info = el('div', 'live-info');
      info.append(el('strong', '', project.name || 'Projeto'), el('small', '', `${where}${project.published_at ? ` · ${fmtDate(project.published_at)}` : ''}`));
      row.append(projectThumb(project), info);
      return row;
    }));
  }

  // ---------- MONITORES ----------

  // Monta os seis cartões com miniatura, conexão, projeto e última observação.
  function renderMonitorGrid() {
    $('#monitorGrid').replaceChildren(...MONITOR_IDS.map((id) => {
      const monitor = monitorOf(id);
      const project = projectOf(id);
      const card = el('a', `monitor-card${monitor.online ? ' online' : ''}`);
      card.href = `#monitor/${id}`;
      const body = el('div', 'monitor-card-body');
      const title = el('div', 'monitor-card-title');
      title.append(el('strong', '', `Monitor ${id}`), statusPill(monitor.online));
      const projectLine = el('p', 'monitor-card-project', project ? project.name || 'Projeto' : 'Nenhum projeto');
      if (monitor.has_project_override) projectLine.append(el('span', 'tag', 'Exclusivo'));
      body.append(title, projectLine);
      if (monitor.teacher_note) body.append(el('p', 'monitor-card-note', monitor.teacher_note));
      card.append(projectThumb(project), body);
      return card;
    }));
  }
  // Página de um monitor: prévia, ações, nova observação e histórico.
  function renderDetail() {
    const id = state.detailId;
    const monitor = monitorOf(id);
    const project = projectOf(id);
    $('#detailTitle').textContent = `Monitor ${id}`;
    $('#detailStatus').replaceWith(Object.assign(statusPill(monitor.online), { id: 'detailStatus' }));
    setProjectViewer($('#detailPreview'), project);
    $('#detailProject').textContent = project ? project.name || 'Projeto sem nome' : 'Nenhum projeto';
    $('#detailScope').textContent = monitor.has_project_override ? 'Projeto exclusivo deste monitor'
      : project ? 'Projeto geral (o mesmo dos outros monitores)' : 'Envie um arquivo para este monitor mostrar.';
    $('#detailSend').href = `#enviar/${id}`;
    $('#detailOpen').href = `/?monitor=${id}`;
    const reset = $('#detailReset');
    reset.hidden = !monitor.has_project_override;
    reset.textContent = state.data?.project ? 'Voltar ao projeto geral' : 'Remover projeto deste monitor';
    renderHistory(monitor.teacher_history, id);
  }
  // Histórico de observações, da mais nova para a mais antiga, com exclusão individual.
  function renderHistory(history, id) {
    const entries = Array.isArray(history) ? [...history].reverse().slice(0, 100) : [];
    if (!entries.length) {
      $('#historyList').replaceChildren(el('p', 'muted', 'Nenhuma observação enviada ainda.'));
      return;
    }
    $('#historyList').replaceChildren(...entries.map((item, index) => {
      const row = el('div', `history-item${index === 0 ? ' current' : ''}`);
      const head = el('div', 'history-head');
      head.append(el('time', '', fmtDate(item.created_at)));
      if (index === 0) head.append(el('span', 'tag', 'Na tela agora'));
      if (item.id) {
        const remove = el('button', 'btn btn-ghost btn-danger btn-small', 'Apagar');
        remove.type = 'button';
        remove.setAttribute('aria-label', `Apagar observação enviada em ${fmtDate(item.created_at)}`);
        remove.addEventListener('click', () => deleteNote(id, item, remove));
        head.append(remove);
      }
      row.append(head, el('p', 'history-text', item.text || ''));
      return row;
    }));
  }
  async function deleteNote(id, item, button) {
    if (!confirm(`Apagar esta observação do Monitor ${id}? Não dá para desfazer.`)) return;
    button.disabled = true;
    try {
      const result = await api(`/api/monitor/${id}/note/${encodeURIComponent(item.id)}`, { method: 'DELETE' });
      await refreshState();
      toast(result.mensagem || 'Observação apagada.');
    } catch (error) {
      toast(error.message, true);
      button.disabled = false;
    }
  }

  // ---------- NAVEGAÇÃO ----------

  // Lê a situação atual do servidor e redesenha o painel.
  async function refreshState() {
    state.data = await api('/api/state');
    renderAll();
  }
  function renderAll() {
    updateTargets();
    updateSendForm();
    renderSummary();
    renderMonitorGrid();
    if (state.page === 'detail') renderDetail();
  }
  // Exibe uma das páginas do painel.
  function showPage(name) {
    const changed = state.page !== name;
    state.page = name;
    Object.entries(pages).forEach(([key, page]) => { page.hidden = key !== name; });
    $$('.tab').forEach((tab) => tab.classList.toggle('active', tab.dataset.page === (name === 'detail' ? 'monitors' : name)));
    if (state.data) renderAll();
    if (changed) window.scrollTo(0, 0);
  }
  // Rotas pelo endereço (#enviar, #enviar/1, #monitores, #monitor/1): o botão Voltar do celular funciona.
  function route() {
    const hash = location.hash.replace(/^#\/?/, '');
    let match;
    if ((match = hash.match(/^monitor\/([1-6])$/))) {
      state.detailId = Number(match[1]);
      $('#noteInput').value = '';
      showPage('detail');
    } else if (hash === 'monitores') {
      showPage('monitors');
    } else {
      if ((match = hash.match(/^enviar\/([1-6])$/))) setTarget(match[1]);
      showPage('send');
    }
  }
  // Mostra o painel depois que ensureSession confirmar a sessão do professor.
  function openTeacherApp() {
    setVisible(teacherApp);
    route();
    refreshState().catch((e) => toast(e.message, true));
    clearInterval(window.teacherRefreshTimer);
    window.teacherRefreshTimer = setInterval(() => {
      if (!document.hidden) refreshState().catch(() => {});
    }, 10000);
  }
  function setVisible(view) {
    [startupView, teacherApp, monitorView].forEach((section) => { section.hidden = section !== view; });
  }
  // Entra no servidor sozinho; se falhar, mostra o motivo e um botão para tentar de novo.
  function startTeacher() {
    setVisible(startupView);
    $('#startupMessage').textContent = 'Conectando ao servidor...';
    $('#startupSpinner').hidden = false;
    $('#startupRetry').hidden = true;
    ensureSession().then(openTeacherApp).catch((e) => {
      $('#startupMessage').textContent = `Não foi possível entrar no servidor: ${e.message}`;
      $('#startupSpinner').hidden = true;
      $('#startupRetry').hidden = false;
    });
  }

  // ---------- TELA DO MONITOR ----------

  // Inicializa a tela de um monitor pelo número, sem token na URL ou nos cabeçalhos.
  function startMonitor(id) {
    id = Math.max(1, Math.min(6, Number(id) || 1));
    document.title = `Monitor ${id} - ConecTorno`;
    setVisible(monitorView);
    $('#monitorHeading').textContent = `Monitor ${id}`;
    const connection = $('#monitorConnection');
    const noteBox = $('#monitorNote');
    let lastNote = null;

    function setConnected(ok) {
      connection.textContent = ok ? 'Conectado' : 'Sem conexão com o servidor';
      connection.classList.toggle('disconnected', !ok);
    }
    // Envia um sinal periódico; o servidor usa o horário recebido para mostrar "Conectado" no painel.
    async function heartbeat() {
      try {
        await api(`/api/monitor/${id}/heartbeat`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      } catch {
        setConnected(false);
      }
    }
    // Atualiza o desenho e a observação; destaca a observação quando ela muda.
    async function refreshMonitor() {
      try {
        const result = await api(`/api/monitor/${id}/display`);
        const monitor = result.monitor || {};
        const project = result.project;
        setProjectViewer($('#monitorPdfViewer'), project, { monitor: true });
        $('#monitorProjectName').textContent = project?.name || 'Aguardando projeto do professor';
        const note = monitor.teacher_note || '';
        const history = Array.isArray(monitor.teacher_history) ? monitor.teacher_history : [];
        const latest = history[history.length - 1];
        noteBox.hidden = !note;
        $('#teacherFeedbackText').textContent = note;
        $('#monitorNoteTime').textContent = latest?.created_at ? `Enviada em ${fmtDate(latest.created_at)}` : '';
        if (lastNote !== null && note && note !== lastNote) {
          noteBox.classList.remove('flash');
          void noteBox.offsetWidth; // reinicia a animação
          noteBox.classList.add('flash');
        }
        lastNote = note;
        setConnected(true);
      } catch {
        setConnected(false);
      }
    }

    heartbeat();
    refreshMonitor();
    setInterval(heartbeat, 10000);
    setInterval(refreshMonitor, 4000);
  }

  // ---------- EVENTOS ----------

  $('#fileInput').addEventListener('change', (event) => chooseFile(event.target.files[0]));
  $('#fileClear').addEventListener('click', () => { clearFile(); $('#fileInput').click(); });
  // Arrastar e soltar um arquivo na área (no computador).
  const picker = $('#filePicker');
  picker.addEventListener('dragover', (event) => { event.preventDefault(); picker.classList.add('dragging'); });
  picker.addEventListener('dragleave', () => picker.classList.remove('dragging'));
  picker.addEventListener('drop', (event) => {
    event.preventDefault();
    picker.classList.remove('dragging');
    chooseFile(event.dataTransfer.files[0]);
  });
  // Envia o arquivo, o destino e, se houver, a observação para o(s) monitor(es).
  $('#sendForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!state.file || state.sending) return;
    const target = state.target;
    const note = $('#sendNote').value.trim();
    const button = $('#sendButton');
    state.sending = true;
    button.disabled = true;
    button.textContent = 'Enviando...';
    setProgress(0);
    $('#uploadProgress').hidden = false;
    try {
      const body = new FormData();
      body.append('arquivo', state.file);
      body.append('destino', target);
      const result = await uploadProject(body, setProgress);
      if (note) {
        const ids = target === 'todos' ? MONITOR_IDS : [Number(target)];
        await Promise.all(ids.map((id) => postJson(`/api/monitor/${id}/note`, { kind: 'teacher', note })));
      }
      clearFile();
      $('#sendNote').value = '';
      toast(result.mensagem || 'Projeto enviado.');
      await refreshState();
    } catch (e) {
      toast(e.message, true);
    } finally {
      state.sending = false;
      $('#uploadProgress').hidden = true;
      updateSendForm();
    }
  });
  // Remove o projeto geral e todos os exclusivos.
  $('#clearAllButton').addEventListener('click', async () => {
    if (!confirm('Remover o projeto geral e todos os projetos exclusivos? Os monitores ficarão sem desenho.')) return;
    try {
      const result = await postJson('/api/project/delete');
      await refreshState();
      toast(result.mensagem || 'Projetos removidos.');
    } catch (e) { toast(e.message, true); }
  });
  // Faz o monitor voltar ao projeto geral (ou ficar sem projeto, se não houver geral).
  $('#detailReset').addEventListener('click', async () => {
    const id = state.detailId;
    const question = state.data?.project
      ? `O Monitor ${id} voltará a mostrar o projeto geral. Continuar?`
      : `O projeto do Monitor ${id} será removido e ele ficará sem desenho. Continuar?`;
    if (!confirm(question)) return;
    try {
      const result = await postJson(`/api/monitor/${id}/project/reset`);
      await refreshState();
      toast(result.mensagem || 'Pronto.');
    } catch (e) { toast(e.message, true); }
  });
  // Envia uma observação para o monitor aberto.
  $('#noteForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    const note = $('#noteInput').value.trim();
    if (!note) return toast('Digite uma observação antes de enviar.', true);
    const button = event.submitter || event.currentTarget.querySelector('button[type="submit"]');
    button.disabled = true;
    try {
      await postJson(`/api/monitor/${state.detailId}/note`, { kind: 'teacher', note });
      $('#noteInput').value = '';
      await refreshState();
      toast(`Observação enviada ao Monitor ${state.detailId}.`);
    } catch (e) {
      toast(e.message, true);
    } finally {
      button.disabled = false;
    }
  });
  $('#startupRetry').addEventListener('click', startTeacher);
  window.addEventListener('hashchange', () => { if (!teacherApp.hidden) route(); });
  // Ao voltar para o app no celular, atualiza na hora.
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && !teacherApp.hidden) refreshState().catch(() => {});
  });

  // ---------- INÍCIO ----------

  buildTargets();
  setTarget(prefs.get('target') || 'todos');
  // Lê somente o número do monitor informado na URL (?monitor=1 até ?monitor=6).
  const url = new URL(window.location.href);
  const monitorId = url.searchParams.get('monitor') || (location.pathname.match(/^\/monitor\/([1-6])\/?$/) || [])[1];
  if (monitorId) {
    // Mantém o endereço simples, sem token ou credencial.
    window.history.replaceState({}, document.title, `${url.pathname}?monitor=${encodeURIComponent(monitorId)}`);
    startMonitor(monitorId);
  } else {
    startTeacher();
  }
})();
