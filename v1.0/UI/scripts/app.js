const state = {
  page: 'overview',
  mode: 'dashboard',
  status: null,
  metrics: null,
  data: { users: null, groups: null, ous: null, gpos: null, tasks: null },
  loading: {},
  errors: {},
  queries: { users: '', groups: '', ous: '', gpos: '', tasks: '' }
};

const pages = {
  overview: 'Panoramica',
  users: 'Utenti',
  groups: 'Gruppi',
  ous: 'Unità organizzative',
  gpo: 'Criteri GPO',
  tasks: 'Attività pianificate'
};
const content = document.querySelector('#app-content');
const hasBridge = Boolean(window.chrome && window.chrome.webview);

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[char]);
}
function send(operation, query = '', extra = {}) {
  if (!hasBridge) {
    showBridgeError();
    return;
  }
  window.chrome.webview.postMessage({ operation, query, ...extra });
}
function showBridgeError() {
  const label = document.querySelector('#connection-label');
  if (label) label.textContent = 'Host desktop non disponibile';
  const environment = document.querySelector('.environment');
  if (environment) environment.innerHTML = '<span class="status-dot"></span> Host desktop non disponibile';
}
function metric(label, value, note, symbol) {
  return '<article class="metric"><div class="metric-top"><span>' + escapeHtml(label) +
    '</span><span class="metric-icon">' + symbol + '</span></div><div class="metric-value">' +
    escapeHtml(value ?? '—') + '</div><div class="metric-note">' + escapeHtml(note) + '</div></article>';
}
function overview() {
  const status = state.status;
  const metrics = state.metrics;
  const connected = Boolean(status && status.adConnected);
  const domain = connected ? status.domain : 'Dominio non connesso';
  const modeLabel = connected ? 'ACTIVE DIRECTORY · ' + domain : 'CONNESSIONE AD NON DISPONIBILE';
  return '<div class="welcome"><div><h2>Panoramica ambiente</h2><p>' +
    escapeHtml(connected ? 'Controller di dominio: ' + (status.domainController || 'non indicato') : 'Metriche disponibili dopo la connessione ad Active Directory.') +
    '</p></div><span class="date-chip">' + escapeHtml(modeLabel) + '</span></div>' +
    '<div class="metrics">' +
    metric('Utenti censiti', metrics && metrics.users, 'Account restituiti da Active Directory', '♙') +
    metric('Gruppi', metrics && metrics.groups, 'Gruppi del dominio', '♧') +
    metric('Unità organizzative', metrics && metrics.ous, 'OU del dominio', '▤') +
    metric('GPO', metrics && metrics.gpos, 'Criteri di gruppo rilevati', '⚙') +
    '</div><div class="columns">' +
    '<section class="panel"><div class="panel-head"><div><h3>Stato connessione</h3><div class="panel-sub">Informazioni restituite dal backend</div></div></div>' +
    '<div class="activity"><div class="activity-row"><div class="activity-icon">●</div><div class="activity-copy"><strong>' +
    escapeHtml(connected ? 'Active Directory connesso' : 'Active Directory non disponibile') +
    '</strong><small>' + escapeHtml(status && status.operator ? 'Operatore: ' + status.operator : (status && status.message) || 'In attesa del backend') +
    '</small></div><span class="pill ' + (connected ? 'ok' : 'warn') + '">' + (connected ? 'Online' : 'Offline') + '</span></div>' +
    '<div class="activity-row"><div class="activity-icon">⌘</div><div class="activity-copy"><strong>Modulo ActiveDirectory</strong><small>Disponibilità rilevata dal backend</small></div><span class="pill ' +
    (status && status.activeDirectoryModule ? 'ok' : 'warn') + '">' + (status && status.activeDirectoryModule ? 'Disponibile' : 'Non disponibile') + '</span></div>' +
    '<div class="activity-row"><div class="activity-icon">⚙</div><div class="activity-copy"><strong>Modulo GroupPolicy</strong><small>Disponibilità rilevata dal backend</small></div><span class="pill ' +
    (status && status.groupPolicyModule ? 'ok' : 'warn') + '">' + (status && status.groupPolicyModule ? 'Disponibile' : 'Non disponibile') + '</span></div></div>' +
    (state.errors.dashboard ? '<div class="notice">' + escapeHtml(state.errors.dashboard) + '</div>' : '') +
    '</section><section class="panel"><div class="panel-head"><div><h3>Aree di lavoro</h3><div class="panel-sub">Consulta i dati correnti del dominio o del computer</div></div></div>' +
    '<div class="quick-grid"><button class="quick" data-page="users"><span>♙</span><strong>Utenti</strong><small>Account AD</small></button>' +
    '<button class="quick" data-page="groups"><span>♧</span><strong>Gruppi</strong><small>Gruppi e membri</small></button>' +
    '<button class="quick" data-page="ous"><span>▤</span><strong>Unità organizzative</strong><small>Struttura OU</small></button>' +
    '<button class="quick" data-page="gpo"><span>⚙</span><strong>Criteri GPO</strong><small>Criteri di gruppo</small></button></div>' +
    '<div class="panel-sub" style="margin-top:14px">I dati visualizzati provengono dal backend; nessun dato dimostrativo viene usato come fallback.</div></section></div>';
}
const pageConfig = {
  users: {
    operation: 'users', title: 'Utenti', search: 'Cerca per nome, account o reparto…',
    columns: [['Name', 'Nome'], ['SamAccountName', 'Account'], ['Department', 'Reparto'], ['DistinguishedName', 'Distinguished name'], ['Enabled', 'Stato'], ['Actions', 'Azioni']],
    render: row => [row.Name, row.SamAccountName, row.Department || '—', row.DistinguishedName, row.Enabled === true ? 'Abilitato' : 'Disabilitato', row]
  },
  groups: {
    operation: 'groups', title: 'Gruppi', search: 'Cerca per nome, account o descrizione…',
    columns: [['Name', 'Nome'], ['GroupCategory', 'Categoria'], ['GroupScope', 'Ambito'], ['MemberCount', 'Membri'], ['Description', 'Descrizione']],
    render: row => [row.Name, row.GroupCategory, row.GroupScope, row.MemberCount, row.Description || '—']
  },
  ous: {
    operation: 'ous', title: 'Unità organizzative', search: 'Cerca per nome OU…',
    columns: [['Name', 'Nome OU'], ['DistinguishedName', 'Percorso'], ['Description', 'Descrizione'], ['ProtectedFromAccidentalDeletion', 'Protezione eliminazione']],
    render: row => [row.Name, row.DistinguishedName, row.Description || '—', row.ProtectedFromAccidentalDeletion ? 'Attiva' : 'Non attiva']
  },
  gpo: {
    operation: 'gpos', title: 'Criteri GPO', search: 'Cerca per nome criterio…',
    columns: [['DisplayName', 'Nome criterio'], ['GpoStatus', 'Stato'], ['ModificationTime', 'Ultima modifica'], ['Owner', 'Proprietario'], ['Description', 'Descrizione']],
    render: row => [row.DisplayName, row.GpoStatus, row.ModificationTime ? new Date(row.ModificationTime).toLocaleString('it-IT') : '—', row.Owner, row.Description || '—']
  },
  tasks: {
    operation: 'tasks', title: 'Attività pianificate', search: 'Cerca per nome o percorso…',
    columns: [['TaskName', 'Attività'], ['TaskPath', 'Percorso'], ['State', 'Stato'], ['Author', 'Autore'], ['Description', 'Descrizione']],
    render: row => [row.TaskName, row.TaskPath, row.State, row.Author || '—', row.Description || '—']
  }
};
function requestPage(page, query = '') {
  const config = pageConfig[page];
  if (!config) return;
  state.loading[page] = true;
  state.errors[page] = null;
  render();
  send(config.operation, query);
}
function tablePage(page) {
  const config = pageConfig[page];
  const query = state.queries[page] || '';
  const data = state.data[page];
  const error = state.errors[page];
  const loading = state.loading[page];
  const rows = Array.isArray(data) ? data : [];
  const header = config.columns.map(col => '<th>' + escapeHtml(col[1]) + '</th>').join('');
  let body;
  if (loading && data === null) {
    body = '<tr><td colspan="' + config.columns.length + '" class="empty">Caricamento dati dal backend…</td></tr>';
  } else if (error) {
    body = '<tr><td colspan="' + config.columns.length + '" class="empty">Errore: ' + escapeHtml(error) + '</td></tr>';
  } else if (!rows.length) {
    body = '<tr><td colspan="' + config.columns.length + '" class="empty">Nessun risultato restituito dal backend.</td></tr>';
  } else {
    body = rows.map(row => '<tr>' + config.render(row).map((value, index) => {
      const key = config.columns[index][0];
      if (page === 'users' && key === 'Actions') {
        const identity = escapeHtml(row.DistinguishedName || row.SamAccountName || '');
        const stateAction = row.Enabled === true
          ? '<button class="text-button" data-user-action="disableUser" data-identity="' + identity + '">Disabilita</button>'
          : '<button class="text-button" data-user-action="enableUser" data-identity="' + identity + '">Abilita</button>';
        const resetAction = row.Enabled === true
          ? '<button class="text-button" data-user-action="resetPassword" data-identity="' + identity + '">Reset password</button>'
          : '<span class="panel-sub">Reset non disponibile</span>';
        return '<td>' + stateAction + ' <button class="text-button" data-user-action="moveUser" data-identity="' + identity + '">Sposta OU</button> ' + resetAction + '</td>';
      }
      const statusCell = (page === 'users' && key === 'Enabled') ||
        (page === 'tasks' && key === 'State') ||
        (page === 'ous' && key === 'ProtectedFromAccidentalDeletion');
      if (statusCell) {
        let text = String(value ?? '—');
        let cls = 'pill';
        if (text === 'Abilitato' || text === 'Ready' || text === 'Running' || text === 'Attiva') cls += ' ok';
        else if (text === 'Disabilitato' || text === 'Disabled' || text === 'Non attiva') cls += ' warn';
        return '<td><span class="' + cls + '">' + escapeHtml(text) + '</span></td>';
      }
      return '<td>' + escapeHtml(value ?? '—') + '</td>';
    }).join('') + '</tr>').join('');
  }
  return '<div class="page-toolbar"><div class="panel-sub">' + escapeHtml(config.title) +
    ' · dati ricevuti dal backend</div><input class="search" id="page-search" value="' + escapeHtml(query) +
    '" placeholder="' + escapeHtml(config.search) + '" aria-label="' + escapeHtml(config.search) + '"></div>' +
    '<div class="table-wrap"><table class="data-table"><thead><tr>' + header +
    '</tr></thead><tbody>' + body + '</tbody></table></div>' +
    (loading && data !== null ? '<div class="panel-sub">Aggiornamento in corso…</div>' : '');
}
function runUserAction(operation, identity) {
  const user = (state.data.users || []).find(item => (item.DistinguishedName || item.SamAccountName) === identity);
  if (!user) { alert('Utente non trovato nei dati correnti. Aggiorna la tabella e riprova.'); return; }
  const account = user.SamAccountName || user.Name || identity;
  const payload = { operation, identity };
  if (operation === 'disableUser') {
    if (!confirm('Confermi la disabilitazione dell’account ' + account + '? L’accesso dell’utente verrà bloccato.')) return;
  } else if (operation === 'enableUser') {
    if (!confirm('Confermi la riabilitazione dell’account ' + account + '?')) return;
  } else if (operation === 'moveUser') {
    const destinationOU = prompt('Inserisci il Distinguished Name completo della OU di destinazione.\nEsempio: OU=RepartoIT,OU=Utenti,DC=homelab,DC=local');
    if (!destinationOU || !destinationOU.trim()) return;
    if (!confirm('Spostare ' + account + ' in questa OU?\n' + destinationOU.trim())) return;
    payload.destinationOU = destinationOU.trim();
  } else if (operation === 'resetPassword') {
    if (user.Enabled !== true) { alert('Il reset password è consentito solo agli account abilitati.'); return; }
    const password = prompt('Inserisci la nuova password per ' + account + '. La policy del dominio verrà applicata da Active Directory.');
    if (password === null || password.length === 0) return;
    const repeated = prompt('Conferma la nuova password.');
    if (password !== repeated) { alert('Le password non coincidono. Nessuna modifica eseguita.'); return; }
    payload.password = password;
    payload.changePasswordAtLogon = confirm('Richiedere all’utente di cambiare password al prossimo accesso?');
    if (!confirm('Confermi il reset della password per ' + account + '?')) return;
  } else return;
  send(operation, state.queries.users || '', payload);
}
function guided() {
  return '<section class="panel guided-card"><div class="step-count">PERCORSO GUIDATO</div><h2>Che cosa vuoi consultare?</h2>' +
    '<p>Seleziona un’area per leggere i dati restituiti dal backend. In questa versione le operazioni di modifica ad Active Directory non sono abilitate.</p>' +
    '<div class="workflow-list"><button class="workflow" data-page="users"><b>01</b><span><strong>Consultare un account</strong><small>Utenti e stato account</small></span></button>' +
    '<button class="workflow" data-page="groups"><b>02</b><span><strong>Verificare un gruppo</strong><small>Categoria, ambito e numero di membri</small></span></button>' +
    '<button class="workflow" data-page="ous"><b>03</b><span><strong>Esplorare le OU</strong><small>Percorsi e protezione da eliminazione</small></span></button>' +
    '<button class="workflow" data-page="gpo"><b>04</b><span><strong>Analizzare una GPO</strong><small>Stato, proprietario e ultima modifica</small></span></button></div>' +
    '<button class="primary" data-page="overview">Torna alla panoramica</button></section>';
}
function render() {
  document.querySelector('#page-title').textContent = state.mode === 'guided' ? 'Modalità guidata' : pages[state.page];
  content.innerHTML = state.mode === 'guided' ? guided() :
    state.page === 'overview' ? overview() : tablePage(state.page);
  content.querySelectorAll('[data-page]').forEach(el => el.addEventListener('click', () => {
    state.page = el.dataset.page;
    state.mode = 'dashboard';
    document.querySelectorAll('.nav-item').forEach(x => x.classList.toggle('active', x.dataset.page === state.page));
    document.querySelectorAll('.mode').forEach(x => x.classList.toggle('active', x.dataset.mode === state.mode));
    render();
    if (state.page === 'overview') send('dashboard');
    else if (pageConfig[state.page]) requestPage(state.page, state.queries[state.page] || '');
  }));
  content.querySelectorAll('[data-user-action]').forEach(button => button.addEventListener('click', () => runUserAction(button.dataset.userAction, button.dataset.identity)));
  const search = document.querySelector('#page-search');
  if (search) search.addEventListener('input', event => {
    const page = state.page;
    state.queries[page] = event.target.value;
    if (state.searchTimer) clearTimeout(state.searchTimer);
    state.searchTimer = setTimeout(() => requestPage(page, state.queries[page]), 250);
  });
}
function handleMessage(event) {
  const result = event.data;
  if (!result || !result.operation) return;
  if (result.operation === 'status') {
    if (result.success && result.data) {
      state.status = result.data;
      const connected = Boolean(result.data.adConnected);
      const label = document.querySelector('#connection-label');
      const environment = document.querySelector('.environment');
      if (label) label.textContent = connected ? 'AD · ' + (result.data.domain || 'connesso') : 'Active Directory offline';
      if (environment) environment.innerHTML = '<span class="status-dot"></span> ' + escapeHtml(connected ? result.data.domain : 'Connessione AD assente');
      render();
      send('dashboard');
    } else {
      state.status = result.data || { adConnected: false, message: result.error || 'Connessione non disponibile' };
      state.errors.dashboard = result.error || 'Impossibile verificare Active Directory.';
      showBridgeError();
      render();
    }
    return;
  }
  if (['disableUser', 'enableUser', 'moveUser', 'resetPassword'].includes(result.operation)) {
    if (result.success && result.data) {
      alert(result.data.message || 'Operazione completata.');
      state.data.users = null;
      requestPage('users', state.queries.users || '');
      send('dashboard');
    } else {
      alert('Operazione non completata: ' + (result.error || 'errore non specificato'));
    }
    return;
  }
  if (result.operation === 'dashboard') {
    if (result.success && result.data) {
      state.status = result.data.status || state.status;
      state.metrics = result.data.metrics || null;
      state.errors.dashboard = result.data.message || null;
    } else {
      state.errors.dashboard = result.error || 'Impossibile caricare le metriche.';
    }
    render();
    return;
  }
  const page = Object.keys(pageConfig).find(key => pageConfig[key].operation === result.operation);
  if (!page) return;
  state.loading[page] = false;
  if (result.success && Array.isArray(result.data)) {
    state.data[page] = result.data;
    state.errors[page] = null;
  } else {
    state.errors[page] = result.error || 'Risposta non valida dal backend.';
    state.data[page] = null;
  }
  if (state.page === page && state.mode === 'dashboard') render();
}
document.querySelectorAll('.mode').forEach(button => button.addEventListener('click', () => {
  state.mode = button.dataset.mode;
  document.querySelectorAll('.mode').forEach(item => item.classList.toggle('active', item === button));
  render();
}));
document.querySelectorAll('.nav-item').forEach(button => button.addEventListener('click', () => {
  state.page = button.dataset.page;
  state.mode = 'dashboard';
  document.querySelectorAll('.nav-item').forEach(item => item.classList.toggle('active', item === button));
  document.querySelectorAll('.mode').forEach(item => item.classList.toggle('active', item.dataset.mode === state.mode));
  render();
  if (state.page === 'overview') send('dashboard');
  else if (pageConfig[state.page]) requestPage(state.page, state.queries[state.page] || '');
}));
if (hasBridge) {
  window.chrome.webview.addEventListener('message', handleMessage);
  send('status');
} else {
  showBridgeError();
}
render();
