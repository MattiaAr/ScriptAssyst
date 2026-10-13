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

const treeExpanded = { groups: new Set(), ous: new Set() };
function dnParent(dn) {
  const parts = String(dn || '').split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/);
  return parts.length > 1 ? parts.slice(1).join(',') : '';
}
function dnDepth(dn, prefix) {
  const matches = String(dn || '').match(new RegExp(prefix + '=', 'ig'));
  return matches ? matches.length : 0;
}
function renderTreeNode(item, type, depth, childHtml, hasChildren, open) {
  const id = type + '-' + btoa(unescape(encodeURIComponent(item.DistinguishedName || item.Name || ''))).replace(/[^a-zA-Z0-9]/g,'').slice(0,48);
  const label = item.Name || item.DisplayName || item.DistinguishedName;
  const icon = type === 'ous' ? '▤' : '♧';
  return '<div class="directory-node ' + type + '-node" style="--tree-depth:' + depth + '">' +
    '<div class="directory-row ' + (depth % 2 ? 'directory-row-alt' : '') + '">' +
    (hasChildren ? '<button class="tree-toggle" data-tree-toggle="' + escapeHtml(id) + '" data-tree-type="' + type + '" aria-expanded="' + open + '" title="' + (open ? 'Comprimi' : 'Espandi') + '">' + (open ? '−' : '+') + '</button>' : '<span class="tree-toggle-spacer"></span>') +
    '<span class="directory-icon">' + icon + '</span><div class="directory-label"><strong>' + escapeHtml(label) + '</strong>' +
    (type === 'ous' ? '<small>' + escapeHtml(item.DistinguishedName || '') + '</small>' : '<small>' + escapeHtml(item.GroupCategory || '') + ' · ' + escapeHtml(item.GroupScope || '') + ' · ' + escapeHtml(item.MemberCount ?? 0) + ' membri</small>') +
    '</div>' + (type === 'ous' ? '<span class="directory-meta ' + (item.ProtectedFromAccidentalDeletion ? 'protected' : '') + '">' + (item.ProtectedFromAccidentalDeletion ? 'Protetta' : 'Non protetta') + '</span>' : '<span class="directory-tag ' + (item.ScriptAssystGroupType === 'Predefinito' ? 'default-tag' : 'custom-tag') + '">' + escapeHtml(item.ScriptAssystGroupType || 'Personalizzato') + '</span>') +
    '</div>' + (hasChildren && open ? '<div class="directory-children">' + childHtml + '</div>' : '') + '</div>';
}
function filterTreeItems(items, query, getChildren) {
  if (!query) return items;
  const lower = query.toLocaleLowerCase('it');
  return items.filter(item => {
    const matches = [item.Name, item.DistinguishedName, item.Description, item.GroupCategory, item.GroupScope]
      .some(value => String(value || '').toLocaleLowerCase('it').includes(lower));
    return matches || getChildren(item).length > 0;
  });
}
function buildOuTree(items, query = '') {
  const all = Array.isArray(items) ? items : [];
  const byDn = new Map(all.map(item => [String(item.DistinguishedName).toLowerCase(), item]));
  const children = new Map();
  const roots = [];
  for (const item of all) {
    const parentDn = dnParent(item.DistinguishedName).toLowerCase();
    if (byDn.has(parentDn)) {
      if (!children.has(parentDn)) children.set(parentDn, []);
      children.get(parentDn).push(item);
    } else roots.push(item);
  }
  for (const list of children.values()) list.sort((a,b)=>a.Name.localeCompare(b.Name,'it'));
  roots.sort((a,b)=>a.Name.localeCompare(b.Name,'it'));
  function node(item, depth) {
    const key = String(item.DistinguishedName).toLowerCase();
    const kids = children.get(key) || [];
    const filteredKids = filterTreeItems(kids, query, child => children.get(String(child.DistinguishedName).toLowerCase()) || []);
    const hasChildren = filteredKids.length > 0;
    const open = query ? true : treeExpanded.ous.has(item.DistinguishedName);
    return renderTreeNode(item, 'ous', depth, filteredKids.map(child=>node(child,depth+1)).join(''), hasChildren, open);
  }
  const filteredRoots = filterTreeItems(roots, query, item => children.get(String(item.DistinguishedName).toLowerCase()) || []);
  return filteredRoots.map(item=>node(item,0)).join('') || '<div class="empty">Nessuna unità organizzativa trovata.</div>';
}
function buildGroupTree(items, query = '') {
  const all = Array.isArray(items) ? items : [];
  const lower = query.toLocaleLowerCase('it');
  const isBuiltin = item => item.ScriptAssystGroupType === 'Predefinito';
  const categories = [
    { id:'predefiniti', title:'Builtin e gruppi predefiniti', description:'Gruppi integrati di Windows e gruppi standard del dominio', items:all.filter(isBuiltin) },
    { id:'personalizzati', title:'Gruppi personalizzati', description:'Altri gruppi presenti nella directory', items:all.filter(item=>!isBuiltin(item)) }
  ];
  return categories.map(category => {
    const matches = category.items.filter(item => !query || [item.Name,item.SamAccountName,item.Description,item.DistinguishedName,item.GroupCategory,item.GroupScope].some(value=>String(value||'').toLocaleLowerCase('it').includes(lower)));
    const open = query ? true : treeExpanded.groups.has(category.id);
    const contents = matches.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map((item,index) => {
      const fake = {...item, DistinguishedName:item.DistinguishedName || item.Name};
      const id = 'group-' + btoa(unescape(encodeURIComponent(fake.DistinguishedName))).replace(/[^a-zA-Z0-9]/g,'').slice(0,48);
      return '<div class="directory-node group-node" style="--tree-depth:0"><div class="directory-row ' + (index%2?'directory-row-alt':'') + '"><span class="tree-toggle-spacer"></span><span class="directory-icon">♧</span><div class="directory-label"><strong>' + escapeHtml(item.Name) + '</strong><small>' + escapeHtml(item.GroupCategory || '') + ' · ' + escapeHtml(item.GroupScope || '') + ' · ' + escapeHtml(item.MemberCount ?? 0) + ' membri</small><small class="dn-caption">' + escapeHtml(item.DistinguishedName || '') + '</small></div><span class="directory-tag ' + (isBuiltin(item)?'default-tag':'custom-tag') + '">' + escapeHtml(item.ScriptAssystGroupType || 'Personalizzato') + '</span></div></div>';
    }).join('');
    const id = 'group-category-' + category.id;
    return '<section class="tree-section"><button class="tree-section-head" data-tree-toggle="' + id + '" data-tree-type="groups" aria-expanded="' + open + '"><span class="tree-section-chevron">' + (open?'−':'+') + '</span><span class="tree-section-icon">▰</span><span class="tree-section-copy"><strong>' + category.title + '</strong><small>' + category.description + '</small></span><span class="tree-count">' + matches.length + '</span></button>' + (open ? '<div class="tree-section-body">' + (contents || '<div class="empty">Nessun gruppo in questa categoria.</div>') + '</div>' : '') + '</section>';
  }).join('');
}
function treePage(page) {
  const title = page === 'ous' ? 'Unità organizzative' : 'Gruppi';
  const query = state.queries[page] || '';
  const rows = Array.isArray(state.data[page]) ? state.data[page] : [];
  const error = state.errors[page];
  const loading = state.loading[page];
  let body = '';
  if (loading && state.data[page] === null) body = '<div class="empty">Caricamento dati dal backend…</div>';
  else if (error) body = '<div class="empty">Errore: ' + escapeHtml(error) + '</div>';
  else if (page === 'ous') body = buildOuTree(rows, query);
  else body = buildGroupTree(rows, query);
  const controls = '<div class="tree-controls"><span class="panel-sub">' + rows.length + (page === 'ous' ? ' unità organizzative' : ' gruppi') + ' · dati Active Directory</span><div><button class="tree-action" data-tree-expand="' + page + '">Espandi tutto</button><button class="tree-action" data-tree-collapse="' + page + '">Comprimi tutto</button></div></div>';
  return '<div class="page-toolbar"><div class="panel-sub">' + escapeHtml(title) + ' · struttura gerarchica</div><input class="search" id="page-search" value="' + escapeHtml(query) + '" placeholder="' + escapeHtml(page === 'ous' ? 'Cerca una OU…' : 'Cerca un gruppo…') + '" aria-label="Cerca"></div>' + controls + '<div class="directory-tree">' + body + '</div>';
}

function requestPage(page, query = '') {
  const config = pageConfig[page];
  if (!config) return;
  state.loading[page] = true;
  state.errors[page] = null;
  render();
  send(config.operation, query);
}
function tablePage(page) {
  if (page === 'groups' || page === 'ous') return treePage(page);
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
let modalState = null;
function closeModal() {
  document.querySelector('#sa-modal-root')?.remove();
  modalState = null;
}
function showModal(title, subtitle, body, actions) {
  document.querySelector('#sa-modal-root')?.remove();
  const root = document.createElement('div');
  root.id = 'sa-modal-root';
  root.innerHTML = '<div class="modal-backdrop" data-modal-close="true"><section class="modal-card" role="dialog" aria-modal="true" aria-labelledby="sa-modal-title">' +
    '<div class="modal-heading"><div><div class="modal-kicker">SCRIPTASSYST · ACTIVE DIRECTORY</div><h2 id="sa-modal-title">' + escapeHtml(title) + '</h2><p>' + escapeHtml(subtitle || '') + '</p></div>' +
    '<button class="modal-x" data-modal-cancel aria-label="Chiudi">×</button></div><div class="modal-body">' + body + '</div><div class="modal-actions">' + actions + '</div></section></div>';
  document.body.appendChild(root);
  root.querySelector('.modal-card').addEventListener('click', e => e.stopPropagation());
  root.querySelector('[data-modal-close]')?.addEventListener('click', closeModal);
  root.querySelectorAll('[data-modal-cancel]').forEach(el => el.addEventListener('click', closeModal));
  return root;
}
function openPasswordModal(identity, account, afterEnable = false) {
  const root = showModal(afterEnable ? 'Account abilitato' : 'Reimposta password',
    afterEnable ? 'Account abilitato e sbloccato. Imposta ora una nuova password.' : 'Inserisci la nuova password per questo account.',
    '<label class="modal-label" for="sa-password">Nuova password</label><input class="modal-input" id="sa-password" type="password" autocomplete="new-password" placeholder="Nuova password" />' +
    '<label class="modal-label" for="sa-password-repeat">Conferma password</label><input class="modal-input" id="sa-password-repeat" type="password" autocomplete="new-password" placeholder="Ripeti la password" />' +
    '<div class="modal-hint">La policy password del dominio Active Directory verrà applicata.</div>',
    '<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-password-next">Continua</button>');
  root.querySelector('#sa-password').focus();
  root.querySelector('#sa-password-next').addEventListener('click', () => {
    const password = root.querySelector('#sa-password').value;
    const repeated = root.querySelector('#sa-password-repeat').value;
    if (!password) { root.querySelector('#sa-modal-error')?.remove(); root.querySelector('.modal-body').insertAdjacentHTML('beforeend','<div id="sa-modal-error" class="modal-error">Inserisci una password.</div>'); return; }
    if (password !== repeated) { root.querySelector('#sa-modal-error')?.remove(); root.querySelector('.modal-body').insertAdjacentHTML('beforeend','<div id="sa-modal-error" class="modal-error">Le password non coincidono.</div>'); return; }
    showPasswordChangeChoice(identity, account, password);
  });
}
function showPasswordChangeChoice(identity, account, password) {
  const root = showModal('Cambio password al prossimo accesso?', 'Vuoi obbligare ' + account + ' a cambiare password al prossimo accesso?',
    '<div class="choice-panel"><strong>Impostazione di sicurezza</strong><p>Sì: l’utente dovrà scegliere una nuova password al prossimo accesso.<br>No: la password impostata resterà valida senza richiesta immediata di cambio.</p></div>',
    '<button class="secondary" id="sa-change-cancel">Annulla</button><button class="secondary" id="sa-change-no">No</button><button class="primary" id="sa-change-yes">Sì</button>');
  const submit = change => {
    closeModal();
    send('resetPassword', state.queries.users || '', {operation:'resetPassword',identity,password,changePasswordAtLogon:change});
  };
  root.querySelector('#sa-change-yes').addEventListener('click', () => submit(true));
  root.querySelector('#sa-change-no').addEventListener('click', () => submit(false));
  root.querySelector('#sa-change-cancel').addEventListener('click', closeModal);
}
function openOuPicker(identity, account) {
  modalState = { identity, account };
  if (!Array.isArray(state.data.ous)) {
    const root = showModal('Sposta utente in una OU', 'Caricamento della struttura Active Directory…',
      '<div class="modal-loading">Lettura delle unità organizzative dal dominio…</div>',
      '<button class="secondary" data-modal-cancel>Annulla</button>');
    send('ous');
    return;
  }
  renderOuPicker();
}
function renderOuPicker() {
  if (!modalState) return;
  const { identity, account } = modalState;
  const ous = Array.isArray(state.data.ous) ? [...state.data.ous] : [];
  const user = (state.data.users || []).find(item => (item.DistinguishedName || item.SamAccountName) === identity);
  const currentParent = user?.DistinguishedName?.split(',').slice(1).join(',') || '';
  const root = showModal('Sposta utente in una OU', 'Seleziona la destinazione per ' + account + '.',
    '<div class="ou-current">Posizione attuale <strong>' + escapeHtml(currentParent || 'Non disponibile') + '</strong></div>' +
    '<div class="ou-tree" role="tree">' + ous.map(ou => {
      const depth = (ou.DistinguishedName.match(/OU=/gi) || []).length - 1;
      return '<button class="ou-tree-item" role="treeitem" style="--ou-depth:' + Math.max(0,depth) + '" data-ou-dn="' + escapeHtml(ou.DistinguishedName) + '">' +
        '<span class="ou-tree-icon">▤</span><span><strong>' + escapeHtml(ou.Name) + '</strong><small>' + escapeHtml(ou.DistinguishedName) + '</small></span><span class="ou-tree-check">Seleziona</span></button>';
    }).join('') + (ous.length ? '' : '<div class="modal-loading">Nessuna OU restituita dal backend.</div>') + '</div><div class="modal-hint">La selezione indica la OU di destinazione; confermerai prima dello spostamento.</div>',
    '<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-move-confirm" disabled>Sposta qui</button>');
  const confirmButton = root.querySelector('#sa-move-confirm');
  root.querySelectorAll('[data-ou-dn]').forEach(button => button.addEventListener('click', () => {
    root.querySelectorAll('[data-ou-dn]').forEach(item => item.classList.remove('selected'));
    button.classList.add('selected');
    modalState.destinationOU = button.dataset.ouDn;
    confirmButton.disabled = false;
  }));
  confirmButton.addEventListener('click', () => {
    if (!modalState?.destinationOU) return;
    const destinationOU = modalState.destinationOU;
    const confirmed = showModal('Conferma spostamento', 'Stai per spostare ' + account + '.',
      '<div class="choice-panel"><strong>OU di destinazione</strong><p>' + escapeHtml(destinationOU) + '</p></div>',
      '<button class="secondary" id="sa-move-back">Indietro</button><button class="primary" id="sa-move-execute">Conferma spostamento</button>');
    confirmed.querySelector('#sa-move-back').addEventListener('click', renderOuPicker);
    confirmed.querySelector('#sa-move-execute').addEventListener('click', () => {
      closeModal();
      send('moveUser', state.queries.users || '', {operation:'moveUser',identity,destinationOU});
    });
  });
}
function runUserAction(operation, identity) {
  const user = (state.data.users || []).find(item => (item.DistinguishedName || item.SamAccountName) === identity);
  if (!user) { showModal('Utente non trovato', 'I dati visualizzati potrebbero non essere aggiornati.', '<p>Aggiorna la tabella Utenti e riprova.</p>', '<button class="primary" data-modal-cancel>Chiudi</button>'); return; }
  const account = user.SamAccountName || user.Name || identity;
  if (operation === 'disableUser') {
    const root = showModal('Disabilita account', 'Conferma la disabilitazione dell’account.',
      '<div class="choice-panel"><strong>' + escapeHtml(account) + '</strong><p>L’accesso dell’utente verrà bloccato.</p></div>',
      '<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-action-confirm">Disabilita account</button>');
    root.querySelector('#sa-action-confirm').addEventListener('click', () => { closeModal(); send(operation, state.queries.users || '', {operation,identity}); });
  } else if (operation === 'enableUser') {
    const root = showModal('Abilita e sblocca account', 'L’account verrà abilitato e sbloccato. Subito dopo potrai impostare una nuova password.',
      '<div class="choice-panel"><strong>' + escapeHtml(account) + '</strong><p>Al termine ti chiederemo di inserire e confermare una nuova password.</p></div>',
      '<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-action-confirm">Abilita e sblocca</button>');
    root.querySelector('#sa-action-confirm').addEventListener('click', () => { closeModal(); send(operation, state.queries.users || '', {operation,identity}); });
  } else if (operation === 'moveUser') {
    openOuPicker(identity, account);
  } else if (operation === 'resetPassword') {
    if (user.Enabled !== true) { showModal('Account disabilitato', 'Prima di reimpostare la password, abilita l’account.', '<p>Usa l’azione Abilita. ScriptAssyst eseguirà anche lo sblocco dell’account.</p>', '<button class="primary" data-modal-cancel>Ho capito</button>'); return; }
    openPasswordModal(identity, account);
  }
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
  content.querySelectorAll('[data-tree-toggle]').forEach(button => button.addEventListener('click', () => {
    const type = button.dataset.treeType;
    const id = button.dataset.treeToggle;
    const expanded = button.getAttribute('aria-expanded') === 'true';
    if (type === 'groups') {
      if (id.startsWith('group-category-')) {
        const key = id.replace('group-category-','');
        if (expanded) treeExpanded.groups.delete(key); else treeExpanded.groups.add(key);
      }
    } else {
      const node = button.closest('.directory-node');
      const dn = node?.querySelector('.directory-row .directory-label small')?.textContent;
      if (dn) { if (expanded) treeExpanded.ous.delete(dn); else treeExpanded.ous.add(dn); }
    }
    render();
  }));
  content.querySelectorAll('[data-tree-expand]').forEach(button => button.addEventListener('click', () => {
    const page = button.dataset.treeExpand;
    if (page === 'groups') treeExpanded.groups = new Set(['predefiniti','personalizzati']);
    else (state.data.ous || []).forEach(item => treeExpanded.ous.add(item.DistinguishedName));
    render();
  }));
  content.querySelectorAll('[data-tree-collapse]').forEach(button => button.addEventListener('click', () => {
    const page = button.dataset.treeCollapse;
    if (page === 'groups') treeExpanded.groups.clear(); else treeExpanded.ous.clear();
    render();
  }));
  const search = document.querySelector('#page-search');
  if (search) search.addEventListener('input', event => {
    const page = state.page;
    state.queries[page] = event.target.value;
    if (state.searchTimer) clearTimeout(state.searchTimer);
    state.searchTimer = setTimeout(() => {
      if (page === 'groups' || page === 'ous') render();
      else requestPage(page, state.queries[page]);
    }, 250);
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
      const affected = result.data.user?.SamAccountName || result.data.user?.Name || 'account';
      state.data.users = null;
      requestPage('users', state.queries.users || '');
      send('dashboard');
      if (result.operation === 'enableUser') {
        openPasswordModal(result.data.user?.DistinguishedName || '', affected, true);
      } else {
        showModal('Operazione completata', result.data.message || 'Operazione completata.', '<div class="choice-panel"><strong>' + escapeHtml(affected) + '</strong><p>Le modifiche sono state inviate ad Active Directory.</p></div>', '<button class="primary" data-modal-cancel>Chiudi</button>');
      }
    } else {
      showModal('Operazione non completata', 'Active Directory ha rifiutato la richiesta.', '<div class="modal-error">' + escapeHtml(result.error || 'Errore non specificato') + '</div>', '<button class="primary" data-modal-cancel>Chiudi</button>');
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
    if (page === 'ous' && modalState && !modalState.destinationOU) renderOuPicker();
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
