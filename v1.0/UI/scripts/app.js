const state = {
  page: 'overview',
  mode: 'dashboard',
  status: null,
  metrics: null,
  data: { users: null, groups: null, ous: null, gpos: null, tasks: null },
  availableGroups: null,
  loading: {},
  errors: {},
  queries: { users: '', groups: '', ous: '', gpos: '', tasks: '' },
  sort: { users: { key: 'Name', direction: 'asc' }, gpo: { key: 'DisplayName', direction: 'asc' }, tasks: { key: 'TaskName', direction: 'asc' } },
  selectedUser: null,
  selectedGroup: null,
  selectedOu: null
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
let groupMemberSelections = new Set();
let groupMemberSearchTimeout = null;
const groupMemberRemoteCache = new Map();

function renderMemberSearchResults(results, items) {
  const chosen = groupMemberSelections;
  results.innerHTML = items.map(item => '<button type="button" class="member-search-result ' +
    (chosen.has(item.DistinguishedName) ? 'selected' : '') + '" data-search-member-dn="' +
    escapeHtml(item.DistinguishedName) + '"><span><strong>' + escapeHtml(item.Name) +
    '</strong><small>' + escapeHtml(item.SamAccountName || item.ObjectClass) +
    '</small><small class="dn-caption">' + escapeHtml(item.DistinguishedName) +
    '</small></span><span>' + (chosen.has(item.DistinguishedName) ? 'Aggiunto' : 'Aggiungi') +
    '</span></button>').join('') || '<p class="modal-hint">Nessun risultato trovato.</p>';
  results.querySelectorAll('[data-search-member-dn]').forEach(button => button.addEventListener('click', () => {
    const dn = button.dataset.searchMemberDn;
    if (groupMemberSelections.has(dn)) groupMemberSelections.delete(dn);
    else groupMemberSelections.add(dn);
    button.classList.toggle('selected', groupMemberSelections.has(dn));
    button.lastElementChild.textContent = groupMemberSelections.has(dn) ? 'Aggiunto' : 'Aggiungi';
  }));
}

function searchCachedDirectoryMembers(query) {
  const term = String(query || '').trim().toLocaleLowerCase('it');
  const users = Array.isArray(state.data.users) ? state.data.users : [];
  const seen = new Set();
  return users.filter(item => {
    const dn = String(item.DistinguishedName || '');
    const key = dn.toLocaleLowerCase('it');
    if (!dn || seen.has(key)) return false;
    seen.add(key);
    return [item.Name, item.SamAccountName, item.DistinguishedName, item.Department, item.Title, item.Mail]
      .some(value => String(value || '').toLocaleLowerCase('it').includes(term));
  }).map(item => ({...item, ObjectClass:'user'})).slice(0, 30);
}

function openGroupMembers(identity) {
  const root = showModal(
    'Caricamento membri',
    'Lettura da Active Directory',
    '<div class="modal-hint">Recupero dei membri del gruppo…</div>',
    '<button class="secondary" data-modal-cancel>Annulla</button>'
  );
  root.dataset.groupDn = identity;
  send('groupMembers', '', { identity });
}
function showMemberSearchResults(results, items, heading) {
  const holder = document.createElement('div');
  renderMemberSearchResults(holder, items);
  results.replaceChildren();
  if (heading) {
    const note = document.createElement('p');
    note.className = 'modal-hint';
    note.textContent = heading;
    results.appendChild(note);
  }
  results.append(...holder.childNodes);
}
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
    '</div>' + (hasChildren && open ? '<div class="directory-children">' + childHtml + '</div>' : '') + (type === 'ous' ? '<div class="ou-row-actions"><button class="text-button ou-open" data-ou-open="' + escapeHtml(item.DistinguishedName) + '">Apri contenuto</button><button class="text-button" data-edit-ou="' + escapeHtml(item.DistinguishedName) + '">Modifica</button><button class="text-button" data-delete-ou="' + escapeHtml(item.DistinguishedName) + '">Elimina</button></div>' : '') + '</div>';
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
      return '<div class="directory-node group-node" style="--tree-depth:0"><div class="directory-row ' + (index%2?'directory-row-alt':'') + '"><span class="tree-toggle-spacer"></span><span class="directory-icon">♧</span><div class="directory-label"><strong>' + escapeHtml(item.Name) + '</strong><small>' + escapeHtml(item.GroupCategory || '') + ' · ' + escapeHtml(item.GroupScope || '') + ' · ' + escapeHtml(item.MemberCount ?? 0) + ' membri</small><small class="dn-caption">' + escapeHtml(item.DistinguishedName || '') + '</small></div><span class="directory-tag ' + (isBuiltin(item)?'default-tag':'custom-tag') + '">' + escapeHtml(item.ScriptAssystGroupType || 'Personalizzato') + '</span>' + (!isBuiltin(item) ? '<span class="group-actions"><button class="text-button" data-group-members="' + escapeHtml(item.DistinguishedName) + '">Membri</button><button class="text-button" data-edit-group="' + escapeHtml(item.DistinguishedName) + '">Modifica</button><button class="text-button" data-delete-group="' + escapeHtml(item.DistinguishedName) + '">Elimina</button></span>' : '<button class="text-button" data-group-members="' + escapeHtml(item.DistinguishedName) + '">Membri</button>') + '</div></div>';
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
  const controls = '<div class="tree-controls"><span class="panel-sub">' + rows.length + (page === 'ous' ? ' unità organizzative' : ' gruppi') + ' · dati Active Directory</span><div>' + (page === 'groups' ? '<button class="primary" data-create-group>Nuovo gruppo</button> ' : '<button class="primary" data-create-ou>Nuova OU</button> ') + '<button class="tree-action" data-tree-expand="' + page + '">Espandi tutto</button><button class="tree-action" data-tree-collapse="' + page + '">Comprimi tutto</button></div></div>';
  return '<div class="page-toolbar"><div class="panel-sub">' + escapeHtml(title) + ' · struttura gerarchica</div><input class="search" id="page-search" value="' + escapeHtml(query) + '" placeholder="' + escapeHtml(page === 'ous' ? 'Cerca una OU…' : 'Cerca un gruppo…') + '" aria-label="Cerca"></div>' + controls + '<div class="directory-tree">' + body + '</div>';
}

function requestPage(page, query = '') {
  const config = pageConfig[page];
  if (!config) return;
  const needsInitialRender = !Array.isArray(state.data[page]);
  state.loading[page] = true;
  state.errors[page] = null;
  // Keep the existing page visible during refresh; only render a loading state on first load.
  if (needsInitialRender) render();
  send(config.operation, query);
}
function tablePage(page) {
  if (page === 'groups' || page === 'ous') return treePage(page);
  const config = pageConfig[page];
  const query = state.queries[page] || '';
  const data = state.data[page];
  const error = state.errors[page];
  const loading = state.loading[page];
  let rows = Array.isArray(data) ? [...data] : [];
  // The users dataset is loaded in bulk; filter it locally to avoid an AD round-trip per search.
  const localQuery = page === 'users' ? String(query || '').trim().toLocaleLowerCase('it') : '';
  if (localQuery) {
    rows = rows.filter(row => Object.values(row).some(value =>
      String(value ?? '').toLocaleLowerCase('it').includes(localQuery)
    ));
  }
  const sort = state.sort[page] || { key: config.columns[0][0], direction: 'asc' };
  rows.sort((a, b) => {
    const av = a[sort.key]; const bv = b[sort.key];
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    let result;
    if (typeof av === 'boolean' || typeof bv === 'boolean') result = Number(Boolean(av)) - Number(Boolean(bv));
    else if (typeof av === 'number' && typeof bv === 'number') result = av - bv;
    else {
      const ad = Date.parse(av); const bd = Date.parse(bv);
      result = !Number.isNaN(ad) && !Number.isNaN(bd) && /time|date|logon/i.test(sort.key) ? ad - bd : String(av).localeCompare(String(bv), 'it', { numeric: true, sensitivity: 'base' });
    }
    return sort.direction === 'asc' ? result : -result;
  });
  const header = config.columns.map(col => {
    const key = col[0];
    if (key === 'Actions') return '<th>' + escapeHtml(col[1]) + '</th>';
    const active = sort.key === key;
    const arrow = active ? (sort.direction === 'asc' ? ' ▲' : ' ▼') : ' ↕';
    return '<th><button class="sort-header" data-sort-key="' + escapeHtml(key) + '" title="Ordina per ' + escapeHtml(col[1]) + '">' + escapeHtml(col[1]) + arrow + '</button></th>';
  }).join('');
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
      if (page === 'users' && key === 'Name') {
        const identity = escapeHtml(row.DistinguishedName || row.SamAccountName || '');
        return '<td><button class="text-button user-inspect" data-inspect-user="' + identity + '" title="Ispeziona attributi" aria-label="Ispeziona ' + escapeHtml(row.Name) + '">⌕</button> ' + escapeHtml(value ?? '—') + '</td>';
      }
      if (page === 'users' && key === 'Actions') {
        const identity = escapeHtml(row.DistinguishedName || row.SamAccountName || '');
        const stateAction = row.Enabled === true
          ? '<button class="text-button" data-user-action="disableUser" data-identity="' + identity + '">Disabilita</button>'
          : '<button class="text-button" data-user-action="enableUser" data-identity="' + identity + '">Abilita</button>';
        const resetAction = row.Enabled === true
          ? '<button class="text-button" data-user-action="resetPassword" data-identity="' + identity + '">Reset password</button>'
          : '<span class="panel-sub">Reset non disponibile</span>';
        return '<td><button class="text-button" data-edit-user="' + identity + '">Modifica</button> <button class="text-button" data-copy-user="' + identity + '">Copia</button> ' + stateAction + ' <button class="text-button" data-user-action="moveUser" data-identity="' + identity + '">Sposta OU</button> ' + resetAction + ' <button class="text-button danger-text" data-delete-user="' + identity + '">Elimina</button></td>';
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
    ' · dati ricevuti dal backend</div><div class="toolbar-actions">' + (page === 'users' ? '<button class="primary" data-create-user>Nuovo utente</button>' : '') + '<input class="search" id="page-search" value="' + escapeHtml(query) +
    '" placeholder="' + escapeHtml(config.search) + '" aria-label="' + escapeHtml(config.search) + '"></div></div>' +
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
  root.innerHTML = '<div class="modal-backdrop"><section class="modal-card" role="dialog" aria-modal="true" aria-labelledby="sa-modal-title">' +
    '<div class="modal-heading"><div><div class="modal-kicker">SCRIPTASSYST · ACTIVE DIRECTORY</div><h2 id="sa-modal-title">' + escapeHtml(title) + '</h2><p>' + escapeHtml(subtitle || '') + '</p></div>' +
    '<button class="modal-x" data-modal-cancel aria-label="Chiudi">×</button></div><div class="modal-body">' + body + '</div><div class="modal-actions">' + actions + '</div></section></div>';
  document.body.appendChild(root);
  root.querySelector('.modal-card').addEventListener('click', e => e.stopPropagation());
  root.querySelectorAll('[data-modal-cancel]').forEach(el => el.addEventListener('click', closeModal));
  return root;
}
function openPasswordModal(identity, account, afterEnable = false, errorMessage = '') {
  window.__scriptAssystPasswordIdentity = identity;
  window.__scriptAssystPasswordAccount = account;
  const root = showModal(afterEnable ? 'Abilita, cambia password e sblocca' : 'Reimposta password',
    afterEnable ? 'L’account verrà abilitato e sbloccato solo dopo il cambio password riuscito.' : 'Inserisci la nuova password per questo account.',
    '<label class="modal-label" for="sa-password">Nuova password</label><input class="modal-input" id="sa-password" type="password" autocomplete="new-password" placeholder="Nuova password" />' +
    '<label class="modal-label" for="sa-password-repeat">Conferma password</label><input class="modal-input" id="sa-password-repeat" type="password" autocomplete="new-password" placeholder="Ripeti la password" />' +
    '<div class="modal-hint">La policy password del dominio Active Directory verrà applicata.</div>' + (errorMessage ? '<div id="sa-modal-error" class="modal-error">' + escapeHtml(errorMessage) + '</div>' : ''),
    '<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-password-next">Continua</button>');
  root.querySelector('#sa-password').focus();
  root.querySelector('#sa-password-next').addEventListener('click', () => {
    const password = root.querySelector('#sa-password').value;
    const repeated = root.querySelector('#sa-password-repeat').value;
    if (!password) { root.querySelector('#sa-modal-error')?.remove(); root.querySelector('.modal-body').insertAdjacentHTML('beforeend','<div id="sa-modal-error" class="modal-error">Inserisci una password.</div>'); return; }
    if (password !== repeated) { root.querySelector('#sa-modal-error')?.remove(); root.querySelector('.modal-body').insertAdjacentHTML('beforeend','<div id="sa-modal-error" class="modal-error">Le password non coincidono.</div>'); return; }
    showPasswordChangeChoice(identity, account, password, afterEnable);
  });
}
function showPasswordChangeChoice(identity, account, password, afterEnable = false) {
  const root = showModal('Cambio password al prossimo accesso?', 'Vuoi obbligare ' + account + ' a cambiare password al prossimo accesso?',
    '<div class="choice-panel"><strong>Impostazione di sicurezza</strong><p>Sì: l’utente dovrà scegliere una nuova password al prossimo accesso.<br>No: la password impostata resterà valida senza richiesta immediata di cambio.</p></div>',
    '<button class="secondary" id="sa-change-cancel">Annulla</button><button class="secondary" id="sa-change-no">No</button><button class="primary" id="sa-change-yes">Sì</button>');
  const submit = change => {
    closeModal();
    window.__scriptAssystPasswordIdentity = identity;
    window.__scriptAssystPasswordAccount = account;
    send(afterEnable ? 'enableUser' : 'resetPassword', state.queries.users || '', {operation:afterEnable ? 'enableUser' : 'resetPassword',identity,password,changePasswordAtLogon:change});
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
    openPasswordModal(identity, account, true);
  } else if (operation === 'moveUser') {
    openOuPicker(identity, account);
  } else if (operation === 'resetPassword') {
    if (user.Enabled !== true) { showModal('Account disabilitato', 'Prima di reimpostare la password, abilita l’account.', '<p>Usa l’azione Abilita. ScriptAssyst eseguirà anche lo sblocco dell’account.</p>', '<button class="primary" data-modal-cancel>Ho capito</button>'); return; }
    openPasswordModal(identity, account);
  }
}

function startCreateUserFlow(){
  if(!Array.isArray(state.availableGroups)) send('availableGroups');
  modalState={flow:'createUserOU',destinationOU:''};
  const ous=Array.isArray(state.data.ous)?state.data.ous:null;
  if(ous){renderCreateUserOuPicker();return;}
  showModal('Seleziona OU','Caricamento della struttura Active Directory…','<div class="modal-loading">Lettura delle unità organizzative dal dominio…</div>','<button class="secondary" data-modal-cancel>Annulla</button>');
  send('ous');
}
function renderCreateUserOuPicker(){
  if(!modalState||modalState.flow!=='createUserOU')return;
  const ous=Array.isArray(state.data.ous)?state.data.ous:[];
  const byDn=new Map(ous.map(ou=>[String(ou.DistinguishedName||'').toLowerCase(),ou]));
  const children=new Map(),roots=[];
  ous.forEach(ou=>{
    const parent=String(ou.DistinguishedName||'').split(/,(?=(?:[^\\]|\\.)*$)/).slice(1).join(',').toLowerCase();
    if(byDn.has(parent)){if(!children.has(parent))children.set(parent,[]);children.get(parent).push(ou);}else roots.push(ou);
  });
  const selected=modalState.destinationOU;
  const renderNode=(ou,depth=0)=>{
    const dn=String(ou.DistinguishedName||''),kids=children.get(dn.toLowerCase())||[];
    return '<div class="create-ou-node" style="--ou-depth:'+depth+'"><button type="button" class="create-ou-choice '+(selected===dn?'selected':'')+'" data-create-ou-dn="'+escapeHtml(dn)+'"><span class="ou-tree-icon">▤</span><span><strong>'+escapeHtml(ou.Name)+'</strong><small>'+escapeHtml(dn)+'</small></span><span class="ou-tree-check">'+(selected===dn?'Selezionata':'Seleziona')+'</span></button>'+(kids.length?'<div class="create-ou-children">'+kids.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(k=>renderNode(k,depth+1)).join('')+'</div>':'')+'</div>';
  };
  const body='<p class="modal-hint">Scegli l’unità organizzativa in cui creare il nuovo account.</p><input class="modal-input" id="sa-create-ou-search" type="search" placeholder="Cerca OU per nome o DN…"><div class="create-ou-tree" id="sa-create-ou-tree">'+(roots.length?roots.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(ou=>renderNode(ou)).join(''):'<div class="modal-hint">Nessuna OU restituita dal dominio.</div>')+'</div>';
  const root=showModal('Seleziona OU','La selezione verrà passata al modulo di creazione utente.',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-create-ou-confirm" '+(selected?'':'disabled')+'>Continua</button>');
  root.querySelectorAll('[data-create-ou-dn]').forEach(button=>button.addEventListener('click',()=>{
    modalState.destinationOU=button.dataset.createOuDn;
    root.querySelectorAll('[data-create-ou-dn]').forEach(x=>x.classList.toggle('selected',x===button));
    root.querySelectorAll('[data-create-ou-dn] .ou-tree-check').forEach(x=>x.textContent='Seleziona');
    button.querySelector('.ou-tree-check').textContent='Selezionata';
    root.querySelector('#sa-create-ou-confirm').disabled=false;
  }));
  root.querySelector('#sa-create-ou-search').addEventListener('input',event=>{
    const term=event.target.value.toLocaleLowerCase('it');
    root.querySelectorAll('[data-create-ou-dn]').forEach(button=>{
      const node=button.closest('.create-ou-node');
      const match=!term||button.textContent.toLocaleLowerCase('it').includes(term);
      node.hidden=!match;
      if(match) node.parentElement.closest('.create-ou-node')?.removeAttribute('hidden');
    });
  });
  root.querySelector('#sa-create-ou-confirm').addEventListener('click',()=>{
    const destination=modalState?.destinationOU;
    if(!destination)return;
    modalState={flow:'createUserForm',destinationOU:destination};
    openUserForm('createUser','',{path:destination,groups:[]});
  });
}
function formField(id,label,value='',type='text',required=false,description=''){return '<div class="form-field"><label class="modal-label" for="'+id+'">'+label+(required?' *':'')+'</label><input class="modal-input" id="'+id+'" type="'+type+'" value="'+escapeHtml(value||'')+'" '+(required?'required':'')+'>'+(description?'<small class="field-description">'+escapeHtml(description)+'</small>':'')+'</div>';}
function openUserForm(operation,identity,detail=null){
  const row=(state.data.users||[]).find(x=>(x.DistinguishedName||x.SamAccountName)===identity)||{};
  const isCopy=operation==='copyUser', isUpdate=operation==='updateUser', isCreate=operation==='createUser';
  const title=isCopy?'Copia utente':isUpdate?'Modifica utente':'Crea utente';
  const source=detail||row;
  const destination=isCreate?(modalState?.destinationOU||source.path||''):(isCopy?'':(source.DistinguishedName||'').split(',').slice(1).join(','));
  const body='<div class="choice-panel"><strong>OU di destinazione</strong><p>'+escapeHtml(destination||'Non selezionata')+'</p>'+(isCreate?'<button type="button" class="text-button" id="sa-change-create-ou">Cambia OU</button>':'')+'</div><div class="form-grid">'+formField('sa-given','Nome',source.GivenName,'text',isCreate,'Nome proprio della persona, ad esempio Mario.')+formField('sa-surname','Cognome',source.Surname,'text',isCreate,'Cognome della persona.')+formField('sa-display','Nome visualizzato',source.DisplayName||source.Name,'text',false,'Nome completo mostrato negli elenchi e nelle rubriche.')+formField('sa-account',isCopy?'Nuovo nome account':'Nome account',isCopy?'':source.SamAccountName,'text',!isUpdate,'SamAccountName usato per accedere al dominio, ad esempio mario.rossi.')+formField('sa-upn','User Principal Name',isCopy?'':source.UserPrincipalName,'text',false,'Facoltativo: se lasciato vuoto, ScriptAssyst lo genera dal nome account e dal dominio.')+formField('sa-department','Reparto',source.Department,'text',false,'Reparto o unità aziendale a cui appartiene l’utente.')+formField('sa-title','Titolo',source.Title,'text',false,'Ruolo o qualifica professionale, ad esempio Tecnico IT.')+formField('sa-email','E-mail',source.Mail||source.Email,'text',false,'Indirizzo e-mail aziendale dell’utente.')+formField('sa-description','Descrizione',source.Description,'text',false,'Nota interna facoltativa per identificare lo scopo o il tipo di account.')+(!isUpdate?formField('sa-new-password','Password iniziale','','password',true,'Password temporanea conforme ai requisiti del dominio. Al primo accesso sarà richiesto il cambio password.'):'')+'</div><h3 class="modal-section-title">Gruppi da assegnare</h3><label class="modal-label" for="sa-manual-groups">Aggiunta manuale gruppi (CN, DN o nome, uno per riga)</label><textarea class="modal-input" id="sa-manual-groups" placeholder="CN=NomeGruppo,OU=Gruppi,DC=homelab,DC=local"></textarea><small class="field-description">Facoltativo: inserisci un gruppo per riga usando il nome, il CN o il Distinguished Name completo. Puoi anche selezionare i gruppi dal browser qui sotto.</small><div id="sa-create-selected-groups" class="group-members-list"><p class="modal-hint">Nessun gruppo selezionato.</p></div><button type="button" class="secondary" id="sa-choose-create-groups">Mostra selezione gruppi</button><div class="group-ou-browser" id="sa-create-group-browser" hidden></div><div class="modal-hint">La password deve rispettare la policy del dominio Active Directory.</div>';
  const root=showModal(title,isCopy?'Crea un account distinto copiando gli attributi selezionati.':isUpdate?'Aggiorna gli attributi dell’account.':'Completa i dati del nuovo account.',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-save-user">Salva</button>');
  const selectedGroups=new Map((detail?.groups||[]).map(g=>[g.DistinguishedName,g]));
  const drawSelected=()=>{const target=root.querySelector('#sa-create-selected-groups');target.innerHTML=selectedGroups.size?[...selectedGroups.values()].map(g=>'<div class="group-option"><span><strong>'+escapeHtml(g.Name||g.DistinguishedName)+'</strong><small>'+escapeHtml(g.DistinguishedName)+'</small></span><button type="button" class="text-button" data-remove-create-group="'+escapeHtml(g.DistinguishedName)+'">Rimuovi</button></div>').join(''):'<p class="modal-hint">Nessun gruppo selezionato.</p>';target.querySelectorAll('[data-remove-create-group]').forEach(b=>b.addEventListener('click',()=>{selectedGroups.delete(b.dataset.removeCreateGroup);drawSelected();}));};
  const accountInput=root.querySelector('#sa-account'), upnInput=root.querySelector('#sa-upn');
  let upnManuallyEdited=Boolean(upnInput.value.trim());
  upnInput.addEventListener('input',()=>{upnManuallyEdited=true;});
  accountInput.addEventListener('input',()=>{if(!upnManuallyEdited||!upnInput.value.trim()){
    const domain=String(state.status?.domain||'').trim();
    if(domain && domain.includes('.')) upnInput.value=accountInput.value.trim()+'@'+domain.toLowerCase();
  }});
  if(isCreate)root.querySelector('#sa-change-create-ou').addEventListener('click',()=>{modalState={flow:'createUserOU',destinationOU:destination};renderCreateUserOuPicker();});
  const groupPicker=root.querySelector('#sa-create-group-browser');
  const groupButton=root.querySelector('#sa-choose-create-groups');
  const renderGroupPicker=()=>{
    const all=Array.isArray(state.availableGroups)?state.availableGroups:[];
    const getPath=dn=>String(dn||'').split(/,(?=(?:[^\\]|\\.)*$)/).filter(x=>/^OU=/i.test(x)).map(x=>x.slice(3).replace(/\\,/g,',')).reverse();
    const tree={children:new Map(),groups:[]};
    all.forEach(g=>{const path=getPath(g.DistinguishedName);let n=tree;path.forEach(name=>{if(!n.children.has(name))n.children.set(name,{name,children:new Map(),groups:[]});n=n.children.get(name);});n.groups.push(g);});
    const option=g=>'<label class="group-option"><input type="checkbox" data-create-group-dn="'+escapeHtml(g.DistinguishedName)+'" '+(selectedGroups.has(g.DistinguishedName)?'checked':'')+'><span><strong>'+escapeHtml(g.Name)+'</strong><small>'+escapeHtml(g.Description||g.DistinguishedName)+'</small></span></label>';
    const nodeHtml=n=>[...n.children.values()].map(child=>'<section class="group-ou-card"><button type="button" class="group-ou-toggle" data-create-group-ou><span class="group-ou-chevron">›</span><span class="group-ou-name">'+escapeHtml(child.name)+'</span><span class="group-ou-count">'+child.groups.length+'</span></button><div class="group-ou-content" hidden>'+nodeHtml(child)+child.groups.map(option).join('')+'</div></section>').join('');
    const unplaced=tree.groups.length?'<section class="group-ou-card"><button type="button" class="group-ou-toggle" data-create-group-ou><span class="group-ou-chevron">›</span><span class="group-ou-name">Altri gruppi</span><span class="group-ou-count">'+tree.groups.length+'</span></button><div class="group-ou-content" hidden>'+tree.groups.map(option).join('')+'</div></section>':'';
    groupPicker.innerHTML='<input class="modal-input" id="sa-create-group-search" type="search" placeholder="Cerca gruppo, descrizione o OU…"><div id="sa-create-group-tree">'+nodeHtml(tree)+unplaced+'</div>';
    groupPicker.querySelectorAll('[data-create-group-ou]').forEach(b=>b.addEventListener('click',()=>{const p=b.nextElementSibling;p.hidden=!p.hidden;b.classList.toggle('is-open',!p.hidden);}));
    groupPicker.querySelectorAll('[data-create-group-dn]').forEach(input=>input.addEventListener('change',()=>{const g=all.find(x=>x.DistinguishedName===input.dataset.createGroupDn);if(!g)return;if(input.checked)selectedGroups.set(g.DistinguishedName,g);else selectedGroups.delete(g.DistinguishedName);drawSelected();}));
    groupPicker.querySelector('#sa-create-group-search').addEventListener('input',e=>{const term=e.target.value.toLocaleLowerCase('it');groupPicker.querySelectorAll('[data-create-group-dn]').forEach(input=>{const g=all.find(x=>x.DistinguishedName===input.dataset.createGroupDn);const match=!term||[g?.Name,g?.Description,g?.DistinguishedName].some(v=>String(v||'').toLocaleLowerCase('it').includes(term));input.closest('.group-option').hidden=!match;});groupPicker.querySelectorAll('.group-ou-content').forEach(panel=>{panel.hidden=!term;});});
  };
  groupButton.addEventListener('click',()=>{
    if(!Array.isArray(state.availableGroups)){groupPicker.hidden=false;groupPicker.dataset.waiting='true';groupPicker.innerHTML='<p class="modal-hint">Caricamento gruppi dal dominio…</p>';send('availableGroups');return;}
    if(groupPicker.dataset.waiting==='true'){groupPicker.dataset.waiting='false';renderGroupPicker();return;}
    groupPicker.hidden=!groupPicker.hidden;
    groupButton.textContent=groupPicker.hidden?'Mostra selezione gruppi':'Nascondi selezione gruppi';
    if(!groupPicker.hidden)renderGroupPicker();
  });
  if(!Array.isArray(state.availableGroups))send('availableGroups');
  root.querySelector('#sa-save-user').addEventListener('click',()=>{
    const val=id=>root.querySelector('#'+id)?.value||'';
    if(!isUpdate&&(!val('sa-account').trim()||!destination||!val('sa-new-password'))) { root.querySelector('.modal-body').insertAdjacentHTML('beforeend','<div class="modal-error">Nome account, OU e password iniziale sono obbligatori.</div>');return; }
    const payload={operation,identity:isUpdate||isCopy?identity:val('sa-account').trim(),givenName:val('sa-given'),surname:val('sa-surname'),displayName:val('sa-display'),userPrincipalName:val('sa-upn'),path:destination,department:val('sa-department'),title:val('sa-title'),email:val('sa-email'),description:val('sa-description'),password:val('sa-new-password'),groups:[...new Set([...selectedGroups.keys(),...val('sa-manual-groups').split(/\r?\n/).map(x=>x.trim()).filter(Boolean)])],groupName:val('sa-account').trim(),changePasswordAtLogon:true};
    root.querySelectorAll('input,textarea,button').forEach(el=>{if(!el.hasAttribute('data-modal-cancel'))el.disabled=true;});
     root.dataset.pendingOperation=operation;
     root.querySelector('.modal-actions').insertAdjacentHTML('afterbegin','<span class="modal-hint" id="sa-save-progress">Salvataggio in corso…</span>');
     window.__scriptAssystPendingForm = {operation, payload};
     send(operation,'',payload);
  });
  drawSelected();
}
function openCreateGroupPicker(selectedGroups,onChanged){
  const render=term=>{
    const all=Array.isArray(state.data.groups)?state.data.groups:[];
    const filtered=all.filter(g=>!term||[g.Name,g.Description,g.DistinguishedName].some(v=>String(v||'').toLocaleLowerCase('it').includes(term.toLocaleLowerCase('it'))));
    const paths=new Map();
    const getPath=dn=>String(dn||'').split(/,(?=(?:[^\\]|\\.)*$)/).filter(x=>/^OU=/i.test(x)).map(x=>x.slice(3).replace(/\\,/g,',')).reverse();
    filtered.forEach(g=>{let node=paths;const p=getPath(g.DistinguishedName);p.forEach(x=>{if(!node.has(x))node.set(x,new Map());node=node.get(x);});});
    const renderNode=(map,path=[])=>[...map.entries()].map(([name,children])=>'<section class="group-ou-card"><button type="button" class="group-ou-toggle" data-picker-ou="'+escapeHtml([...path,name].join('/'))+'"><span class="group-ou-chevron">›</span><span class="group-ou-name">'+escapeHtml(name)+'</span></button><div class="group-ou-content" hidden>'+renderNode(children,[...path,name])+filtered.filter(g=>getPath(g.DistinguishedName).join('/')===[...path,name].join('/')).map(group=>'<label class="group-option"><input type="checkbox" data-create-group-dn="'+escapeHtml(group.DistinguishedName)+'" '+(selectedGroups.has(group.DistinguishedName)?'checked':'')+'><span><strong>'+escapeHtml(group.Name)+'</strong><small>'+escapeHtml(group.Description||group.DistinguishedName)+'</small></span></label>').join('')+'</div></section>').join('');
    const unplaced=filtered.filter(g=>getPath(g.DistinguishedName).length===0);
    return renderNode(paths)+ (unplaced.length?'<section class="group-ou-card"><button type="button" class="group-ou-toggle" data-picker-other><span class="group-ou-chevron">›</span><span class="group-ou-name">Altri gruppi</span><span class="group-ou-count">'+unplaced.length+'</span></button><div class="group-ou-content" hidden>'+unplaced.map(group=>'<label class="group-option"><input type="checkbox" data-create-group-dn="'+escapeHtml(group.DistinguishedName)+'" '+(selectedGroups.has(group.DistinguishedName)?'checked':'')+'><span><strong>'+escapeHtml(group.Name)+'</strong><small>'+escapeHtml(group.Description||group.DistinguishedName)+'</small></span></label>').join('')+'</div></section>':'');
  };
  const root=showModal('Seleziona gruppi','Seleziona i gruppi da assegnare al nuovo utente.','<input class="modal-input" id="sa-create-group-search" type="search" placeholder="Cerca gruppo, descrizione o OU…"><div class="group-ou-browser" id="sa-create-group-browser"></div>','<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-create-group-confirm">Conferma gruppi</button>');
  const browser=root.querySelector('#sa-create-group-browser'),search=root.querySelector('#sa-create-group-search');
  const refresh=()=>{browser.innerHTML=render(search.value.trim());browser.querySelectorAll('[data-picker-ou],[data-picker-other]').forEach(button=>button.addEventListener('click',()=>{const panel=button.nextElementSibling;panel.hidden=!panel.hidden;button.classList.toggle('is-open',!panel.hidden);}));browser.querySelectorAll('[data-create-group-dn]').forEach(input=>input.addEventListener('change',()=>{const group=(state.data.groups||[]).find(g=>g.DistinguishedName===input.dataset.createGroupDn)||{Name:input.dataset.createGroupDn,DistinguishedName:input.dataset.createGroupDn};if(input.checked)selectedGroups.set(group.DistinguishedName,group);else selectedGroups.delete(group.DistinguishedName);}));};
  if(!Array.isArray(state.data.groups)){showModal('Caricamento gruppi','Lettura dei gruppi dal dominio…','<div class="modal-loading">Caricamento…</div>','<button class="secondary" data-modal-cancel>Annulla</button>');send('groups');return;}
  refresh();search.addEventListener('input',refresh);
  root.querySelector('#sa-create-group-confirm').addEventListener('click',()=>{closeModal();onChanged();});
}
function startCreateGroupFlow(){modalState={flow:'createGroupOU',destinationOU:''};if(Array.isArray(state.data.ous)){renderCreateGroupOuPicker();return;}showModal('Seleziona OU','Caricamento della struttura Active Directory…','<div class="modal-loading">Lettura delle unità organizzative dal dominio…</div>','<button class="secondary" data-modal-cancel>Annulla</button>');send('ous');}
function renderCreateGroupOuPicker(){
 if(!modalState||modalState.flow!=='createGroupOU')return;const ous=Array.isArray(state.data.ous)?state.data.ous:[],byDn=new Map(ous.map(o=>[String(o.DistinguishedName||'').toLowerCase(),o])),children=new Map(),roots=[];
 ous.forEach(o=>{const p=String(o.DistinguishedName||'').split(/,(?=(?:[^\\]|\\.)*$)/).slice(1).join(',').toLowerCase();if(byDn.has(p)){if(!children.has(p))children.set(p,[]);children.get(p).push(o);}else roots.push(o);});
 const selected=modalState.destinationOU;const node=(o,d=0)=>{const dn=String(o.DistinguishedName||''),kids=children.get(dn.toLowerCase())||[];return '<div class="create-ou-node" style="--ou-depth:'+d+'"><button type="button" class="create-ou-choice '+(selected===dn?'selected':'')+'" data-create-group-ou-dn="'+escapeHtml(dn)+'"><span class="ou-tree-icon">▤</span><span><strong>'+escapeHtml(o.Name)+'</strong><small>'+escapeHtml(dn)+'</small></span><span class="ou-tree-check">'+(selected===dn?'Selezionata':'Seleziona')+'</span></button>'+(kids.length?'<div class="create-ou-children">'+kids.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(x=>node(x,d+1)).join('')+'</div>':'')+'</div>';};
 const body='<p class="modal-hint">Scegli la OU che conterrà il nuovo gruppo.</p><input class="modal-input" id="sa-create-group-ou-search" type="search" placeholder="Cerca OU per nome o DN…"><div class="create-ou-tree">'+(roots.length?roots.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(o=>node(o)).join(''):'<div class="modal-hint">Nessuna OU restituita dal dominio.</div>')+'</div>';
 const root=showModal('Seleziona OU','Prima scegli la posizione del gruppo, poi inserisci i dati.',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-create-group-ou-confirm" '+(selected?'':'disabled')+'>Continua</button>');
 root.querySelectorAll('[data-create-group-ou-dn]').forEach(b=>b.addEventListener('click',()=>{modalState.destinationOU=b.dataset.createGroupOuDn;root.querySelectorAll('[data-create-group-ou-dn]').forEach(x=>{x.classList.toggle('selected',x===b);x.querySelector('.ou-tree-check').textContent=x===b?'Selezionata':'Seleziona';});root.querySelector('#sa-create-group-ou-confirm').disabled=false;}));
 root.querySelector('#sa-create-group-ou-search').addEventListener('input',e=>{const t=e.target.value.toLocaleLowerCase('it');root.querySelectorAll('[data-create-group-ou-dn]').forEach(b=>{const n=b.closest('.create-ou-node'),m=!t||b.textContent.toLocaleLowerCase('it').includes(t);n.hidden=!m;if(m)n.parentElement.closest('.create-ou-node')?.removeAttribute('hidden');});});
 root.querySelector('#sa-create-group-ou-confirm').addEventListener('click',()=>{const path=modalState?.destinationOU;if(!path)return;modalState={flow:'createGroupForm',destinationOU:path};openGroupForm();});
}
function openGroupForm(identity=''){
 const row=(state.data.groups||[]).find(x=>x.DistinguishedName===identity)||{},editing=Boolean(identity),destination=editing?(row.DistinguishedName||'').split(',').slice(1).join(','):(modalState?.destinationOU||'');
 const body='<div class="choice-panel"><strong>OU di destinazione</strong><p>'+escapeHtml(destination||'Non selezionata')+'</p>'+(!editing?'<button type="button" class="text-button" id="sa-change-group-ou">Cambia OU</button>':'')+'</div>'+formField('sa-group-name','Nome gruppo',row.Name,'text',true)+formField('sa-group-description','Descrizione',row.Description,'text',false,'Spiega brevemente a cosa serve il gruppo; è facoltativa ma aiuta a riconoscerlo in futuro.')+(!editing?'<label class="modal-label" for="sa-group-category">Categoria</label><select class="modal-input" id="sa-group-category"><option value="Security">Security</option><option value="Distribution">Distribution</option></select><small class="field-description">Security: autorizzazioni e controllo accessi. Distribution: liste di distribuzione e posta.</small><label class="modal-label" for="sa-group-scope">Ambito</label><select class="modal-input" id="sa-group-scope"><option value="Global">Global</option><option value="Universal">Universal</option><option value="DomainLocal">DomainLocal</option></select><small class="field-description">Global: membri dello stesso dominio; Universal: membri da più domini della foresta; DomainLocal: assegna permessi a risorse del dominio.</small>':'');
 const root=showModal(editing?'Modifica gruppo':'Nuovo gruppo','Le modifiche saranno applicate in Active Directory.',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-save-group">Salva</button>');
 if(!editing)root.querySelector('#sa-change-group-ou').addEventListener('click',()=>{modalState={flow:'createGroupOU',destinationOU:destination};renderCreateGroupOuPicker();});
 root.querySelector('#sa-save-group').addEventListener('click',()=>{const name=root.querySelector('#sa-group-name').value.trim();if(!name||(!editing&&!destination))return;const payload={operation:editing?'updateGroup':'createGroup',identity,groupName:name,path:destination,description:root.querySelector('#sa-group-description').value,groupCategory:root.querySelector('#sa-group-category')?.value||row.GroupCategory||'Security',groupScope:root.querySelector('#sa-group-scope')?.value||row.GroupScope||'Global'};closeModal();send(payload.operation,'',payload);});
}
function confirmDeleteGroup(identity){
 const row=(state.data.groups||[]).find(x=>x.DistinguishedName===identity);
 showModal('Verifica appartenenze','Controllo degli utenti che perderanno il gruppo…','<div class="modal-loading">Lettura dei membri del gruppo da Active Directory…</div>','<button class="secondary" data-modal-cancel>Annulla</button>');
 send('groupDeletePreview','',{identity});
}

function openOUForm(operation, identity='') {
  const existing=(state.data.ous||[]).find(o=>o.DistinguishedName===identity)||null;
  const title=operation==='createOU'?'Crea unità organizzativa':'Modifica unità organizzativa';
  const body='<label class="modal-label" for="sa-ou-name">Nome OU</label><input class="modal-input" id="sa-ou-name" maxlength="64" required value="'+escapeHtml(existing?.Name||'')+'" placeholder="Es. Utenti"><label class="modal-label" for="sa-ou-description">Descrizione</label><textarea class="modal-input" id="sa-ou-description" rows="3" placeholder="Descrizione facoltativa">'+escapeHtml(existing?.Description||'')+'</textarea>'+(operation==='createOU'?'<label class="modal-label">OU padre</label><p class="modal-hint">Seleziona la radice del dominio oppure una OU esistente.</p><div class="create-ou-tree" id="sa-ou-parent-tree"></div>':'<p class="modal-hint">'+escapeHtml(identity)+'</p>');
  const root=showModal(title,existing?.DistinguishedName||'Nuova OU',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-save-ou">Salva</button>');
  let selectedParent='';
  if(operation==='createOU'){
    const browser=root.querySelector('#sa-ou-parent-tree');
    const ous=Array.isArray(state.data.ous)?state.data.ous:[];
    const byDn=new Map(ous.map(o=>[String(o.DistinguishedName||'').toLowerCase(),o]));
    const children=new Map(),roots=[];
    ous.forEach(ou=>{
      const parent=String(ou.DistinguishedName||'').split(/,(?=(?:[^\\]|\\.)*$)/).slice(1).join(',').toLowerCase();
      if(byDn.has(parent)){if(!children.has(parent))children.set(parent,[]);children.get(parent).push(ou);}else roots.push(ou);
    });
    const rootKey='__domain_root__';
    const node=(ou,depth=0)=>{
      const dn=String(ou.DistinguishedName||''),kids=children.get(dn.toLowerCase())||[];
      return '<div class="create-ou-node" style="--ou-depth:'+depth+'"><button type="button" class="create-ou-choice" data-ou-parent-choice="'+escapeHtml(dn)+'"><span class="ou-tree-icon">▤</span><span><strong>'+escapeHtml(ou.Name)+'</strong><small>'+escapeHtml(dn)+'</small></span><span class="ou-tree-check">Seleziona</span></button>'+(kids.length?'<div class="create-ou-children">'+kids.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(k=>node(k,depth+1)).join('')+'</div>':'')+'</div>';
    };
    browser.innerHTML='<div class="create-ou-node"><button type="button" class="create-ou-choice selected" data-ou-parent-choice="" aria-pressed="true"><span class="ou-tree-icon">⌂</span><span><strong>Radice del dominio</strong><small>OU creata direttamente nel dominio</small></span><span class="ou-tree-check">Selezionata</span></button></div>'+roots.sort((a,b)=>a.Name.localeCompare(b.Name,'it')).map(ou=>node(ou)).join('');
    browser.querySelectorAll('[data-ou-parent-choice]').forEach(button=>button.addEventListener('click',()=>{
      selectedParent=button.dataset.ouParentChoice||'';
      browser.querySelectorAll('[data-ou-parent-choice]').forEach(b=>{b.classList.toggle('selected',b===button);b.querySelector('.ou-tree-check').textContent=b===button?'Selezionata':'Seleziona';b.setAttribute('aria-pressed',String(b===button));});
    }));
  }
  root.querySelector('#sa-save-ou').addEventListener('click',()=>{
    const name=root.querySelector('#sa-ou-name').value.trim();
    if(!name){root.querySelector('#sa-ou-name').focus();return;}
    const description=root.querySelector('#sa-ou-description').value.trim();
    const path=operation==='createOU'?selectedParent:'';
    closeModal();
    send(operation,'',{identity,groupName:name,description,path});
  });
}
function confirmDeleteOU(identity) {
  const ou=(state.data.ous||[]).find(o=>o.DistinguishedName===identity);
  if(!ou)return;
  const root=showModal('Elimina unità organizzativa',ou.Name,'<div class="choice-panel"><strong>Eliminazione di '+escapeHtml(ou.Name)+'</strong><p>Puoi eliminare questa unità organizzativa solo se non contiene utenti, gruppi, computer o sotto-OU e se la protezione dall’eliminazione è disattivata.</p><p>L’operazione è definitiva e non può essere annullata.</p><small class="dn-caption">'+escapeHtml(identity)+'</small></div>','<button class="secondary" data-modal-cancel>Annulla</button><button class="danger" id="sa-confirm-delete-ou">Elimina unità organizzativa</button>');
  root.querySelector('#sa-confirm-delete-ou').addEventListener('click',()=>{closeModal();send('deleteOU','',{identity});});
}

function confirmDeleteUser(identity) {
  const user=(state.data.users||[]).find(u=>(u.DistinguishedName||u.SamAccountName)===identity);
  if(!user)return;
  const account=user.SamAccountName||user.Name||identity;
  const root=showModal('Elimina utente', 'Conferma l’eliminazione definitiva dell’account.', '<div class="modal-error"><strong>'+escapeHtml(account)+'</strong><p>L’account verrà eliminato da Active Directory. L’operazione non è reversibile.</p><small>'+escapeHtml(identity)+'</small></div>', '<button class="secondary" data-modal-cancel>Annulla</button><button class="danger" id="sa-delete-user-confirm">Elimina utente</button>');
  root.querySelector('#sa-delete-user-confirm').addEventListener('click',()=>{closeModal();send('deleteUser','',{operation:'deleteUser',identity});});
}
function showResultModal(title,subtitle,body){showModal(title,subtitle,body,'<button class="primary" data-modal-cancel>Chiudi</button>');}

function guided() {
  const selectedPage = state.page !== 'overview';
  const intro = '<section class="panel guided-card"><div class="step-count">ASSISTENTE OPERATIVO</div>' +
    (selectedPage
      ? '<div class="guided-toolbar"><button class="secondary" data-guided-home>← Tutte le procedure</button><span class="guided-current">Passaggio 2 di 2 · Area operativa</span></div><h2>' + escapeHtml(pages[state.page] || 'Area operativa') + '</h2><p>Consulta i dati aggiornati dal dominio. Usa la ricerca per trovare una voce; seleziona un’azione solo dopo aver verificato nome e account.</p>'
      : '<h2>Che cosa devi fare?</h2><p>Scegli l’obiettivo. Aprire una procedura carica i dati reali da Active Directory; da lì puoi cercare le voci e usare le azioni disponibili. Le operazioni che modificano il dominio richiedono conferma.</p>') +
    (selectedPage ? '' :
    '<div class="guided-steps"><div><b>1</b><span><strong>Scegli un’area</strong><small>Utenti, gruppi, OU o criteri</small></span></div><div><b>2</b><span><strong>Cerca e verifica</strong><small>Controlla nome, account e percorso</small></span></div><div><b>3</b><span><strong>Esegui l’azione</strong><small>Conferma prima delle modifiche</small></span></div></div>' +
    '<div class="workflow-list">' +
    '<button class="workflow" data-page="users"><b>01</b><span><strong>Gestire un utente</strong><small>Cercare account, consultare dettagli, creare o modificare, abilitare/disabilitare, reimpostare password e spostare OU</small></span><span class="workflow-arrow">›</span></button>' +
    '<button class="workflow" data-page="groups"><b>02</b><span><strong>Gestire un gruppo</strong><small>Consultare gruppi e membri, modificare appartenenze o creare ed eliminare gruppi</small></span><span class="workflow-arrow">›</span></button>' +
    '<button class="workflow" data-page="ous"><b>03</b><span><strong>Organizzare le OU</strong><small>Esplorare la struttura, creare o modificare OU e verificare la protezione prima di eliminare</small></span><span class="workflow-arrow">›</span></button>' +
    '<button class="workflow" data-page="gpo"><b>04</b><span><strong>Controllare i criteri GPO</strong><small>Consultare stato, proprietario e data di modifica</small></span><span class="workflow-arrow">›</span></button>' +
    '<button class="workflow" data-page="tasks"><b>05</b><span><strong>Consultare le attività pianificate</strong><small>Cercare attività, percorso e stato</small></span><span class="workflow-arrow">›</span></button></div>' +
    '<div class="guided-note"><strong>Prima di confermare</strong><span>Verifica sempre l’oggetto selezionato. Le modifiche in Active Directory possono avere effetti immediati sugli utenti e sui permessi.</span></div>') +
    '</section>';
  return intro + (selectedPage
    ? '<div class="guided-results">' + tablePage(state.page) + '</div>'
    : '<div class="guided-footer"><span>Modalità guidata</span><span>Le procedure usano i dati restituiti dal backend, senza dati dimostrativi.</span></div>');
}
function render() {
  document.querySelector('#page-title').textContent = state.mode === 'guided' ? 'Modalità guidata' : pages[state.page];
  content.innerHTML = state.mode === 'guided' ? guided() :
    state.page === 'overview' ? overview() : tablePage(state.page);
  content.querySelectorAll('[data-guided-home]').forEach(el => el.addEventListener('click', () => {
    state.page = 'overview';
    render();
  }));
  content.querySelectorAll('[data-page]').forEach(el => el.addEventListener('click', () => {
    state.page = el.dataset.page;
    if (state.mode !== 'guided') state.mode = 'dashboard';
    document.querySelectorAll('.nav-item').forEach(x => x.classList.toggle('active', x.dataset.page === state.page));
    document.querySelectorAll('.mode').forEach(x => x.classList.toggle('active', x.dataset.mode === state.mode));
    render();
    if (state.page === 'overview') send('dashboard');
    else if (pageConfig[state.page]) requestPage(state.page, state.queries[state.page] || '');
  }));
  content.querySelectorAll('[data-user-action]').forEach(button => button.addEventListener('click', () => runUserAction(button.dataset.userAction, button.dataset.identity)));
  content.querySelectorAll('[data-inspect-user]').forEach(button => button.addEventListener('click', () => { state.selectedUser=button.dataset.inspectUser; send('userDetails','',{identity:button.dataset.inspectUser}); }));
  content.querySelectorAll('[data-edit-user]').forEach(button => button.addEventListener('click', () => openUserForm('updateUser',button.dataset.editUser)));
  content.querySelectorAll('[data-copy-user]').forEach(button => button.addEventListener('click', () => openUserForm('copyUser',button.dataset.copyUser)));
  content.querySelectorAll('[data-delete-user]').forEach(button => button.addEventListener('click', () => confirmDeleteUser(button.dataset.deleteUser)));
  content.querySelectorAll('[data-create-user]').forEach(button => button.addEventListener('click', startCreateUserFlow));
  content.querySelectorAll('[data-create-group]').forEach(button => button.addEventListener('click', startCreateGroupFlow));
  content.querySelectorAll('[data-group-members]').forEach(button => button.addEventListener('click', () => openGroupMembers(button.dataset.groupMembers)));
  content.querySelectorAll('[data-edit-group]').forEach(button => button.addEventListener('click', () => openGroupForm(button.dataset.editGroup)));
  content.querySelectorAll('[data-delete-group]').forEach(button => button.addEventListener('click', () => confirmDeleteGroup(button.dataset.deleteGroup)));
  content.querySelectorAll('[data-ou-open]').forEach(button => button.addEventListener('click', () => send('ouContents','',{identity:button.dataset.ouOpen})));
  content.querySelectorAll('[data-create-ou]').forEach(button => button.addEventListener('click', () => openOUForm('createOU')));
  content.querySelectorAll('[data-edit-ou]').forEach(button => button.addEventListener('click', () => openOUForm('updateOU',button.dataset.editOu)));
  content.querySelectorAll('[data-delete-ou]').forEach(button => button.addEventListener('click', () => confirmDeleteOU(button.dataset.deleteOu)));
  content.querySelectorAll('[data-sort-key]').forEach(button => button.addEventListener('click', () => {
    const page = state.page;
    const current = state.sort[page] || { key: button.dataset.sortKey, direction: 'asc' };
    state.sort[page] = { key: button.dataset.sortKey, direction: current.key === button.dataset.sortKey && current.direction === 'asc' ? 'desc' : 'asc' };
    render();
  }));
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
    const input = event.target;
    state.queries[page] = input.value;
    const caretStart = input.selectionStart;
    const caretEnd = input.selectionEnd;
    if (state.searchTimer) clearTimeout(state.searchTimer);
    state.searchTimer = setTimeout(() => {
      if (page === 'groups' || page === 'ous' || (page === 'users' && Array.isArray(state.data.users))) {
        render();
        // render() rebuilds the page DOM; restore focus and caret so local search remains typeable.
        const refreshedSearch = document.querySelector('#page-search');
        if (refreshedSearch && state.page === page) {
          refreshedSearch.focus({ preventScroll: true });
          try { refreshedSearch.setSelectionRange(caretStart, caretEnd); } catch (_) {}
        }
      } else {
        requestPage(page, state.queries[page]);
      }
    }, 120);
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
      if (result.operation === 'enableUser' || result.operation === 'resetPassword') {
        closeModal();
        showModal('Operazione completata', result.data.message || 'Operazione completata.', '<div class="choice-panel"><strong>' + escapeHtml(affected) + '</strong><p>Password aggiornata' + (result.operation === 'enableUser' ? ', account abilitato e sbloccato' : '') + '.</p></div>', '<button class="primary" data-modal-cancel>Chiudi</button>');
      } else {
        showModal('Operazione completata', result.data.message || 'Operazione completata.', '<div class="choice-panel"><strong>' + escapeHtml(affected) + '</strong><p>Le modifiche sono state inviate ad Active Directory.</p></div>', '<button class="primary" data-modal-cancel>Chiudi</button>');
      }
    } else if (result.operation === 'enableUser' || result.operation === 'resetPassword') {
      openPasswordModal(window.__scriptAssystPasswordIdentity || '', window.__scriptAssystPasswordAccount || 'utente', result.operation === 'enableUser', result.error || 'Password non accettata. Inseriscine un’altra oppure annulla.');
    } else {
      showModal('Operazione non completata', 'Active Directory ha rifiutato la richiesta.', '<div class="modal-error">' + escapeHtml(result.error || 'Errore non specificato') + '</div>', '<button class="primary" data-modal-cancel>Chiudi</button>');
    }
    return;
  }
  if (result.operation === 'groupDeletePreview') {
    if (!result.success || !result.data) {
      showResultModal('Impossibile verificare i membri','Il gruppo non è stato eliminato.','<div class="modal-error">'+escapeHtml(result.error||'Errore non specificato')+'</div>');
      return;
    }
    const data=result.data, users=Array.isArray(data.users)?data.users:[];
    const list=users.length?'<div class="group-members-list">'+users.map(u=>'<div class="group-option"><span><strong>'+escapeHtml(u.Name||u.SamAccountName||'Utente')+'</strong><small>'+escapeHtml(u.SamAccountName||'')+'</small><small class="dn-caption">'+escapeHtml(u.DistinguishedName||'')+'</small></span></div>').join('')+'</div>':'<p class="modal-hint">Nessun utente diretto o annidato rilevato nel gruppo.</p>';
    const body='<div class="choice-panel"><strong>'+escapeHtml(data.name||'Gruppo')+'</strong><div class="group-delete-warning"><span class="group-delete-warning-icon" aria-hidden="true">⚠</span><strong>Eliminando il gruppo, gli utenti elencati perderanno l’appartenenza a questo gruppo.</strong></div><p>L’eliminazione rimuoverà questo gruppo da Active Directory.</p><strong>'+users.length+' '+(users.length===1?'utente coinvolto':'utenti coinvolti')+'</strong></div>'+list+'<p class="modal-hint">Sono inclusi anche gli utenti appartenenti tramite gruppi annidati. L’eliminazione non è reversibile.</p>';
    const root=showModal('Conferma eliminazione gruppo',data.name||'','<div class="group-delete-impact">'+body+'</div>','<button class="secondary" data-modal-cancel>Annulla</button><button class="danger" id="sa-delete-group-confirm">Elimina gruppo</button>');
    root.querySelector('#sa-delete-group-confirm').addEventListener('click',()=>{closeModal();send('deleteGroup','',{operation:'deleteGroup',identity:data.identity});});
    return;
  }
  if (['userDetails','groupMembers','ouContents'].includes(result.operation) && !result.success) {
    showResultModal('Impossibile caricare i dettagli','La richiesta al backend non è riuscita.','<div class="modal-error">'+escapeHtml(result.error||'Errore non specificato')+'</div>');
    return;
  }
  if (result.operation === 'userDetails' && result.success && result.data) {
     const u=result.data.user||{}, groups=result.data.groups||[];
     let available=Array.isArray(result.data.availableGroups)?result.data.availableGroups:[];
     const formatAdDate=value=>{
       if(value===null||value===undefined||value==='') return '—';
       if(typeof value==='string'){const match=value.match(/^\/Date\((\d+)(?:[+-]\d+)?\)\/$/);if(match)value=Number(match[1]);}
       const date=value instanceof Date?value:new Date(value);
       return Number.isNaN(date.getTime())?'—':date.toLocaleString('it-IT',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'});
     };
     const dateKeys=new Set(['Creato','Ultima modifica','Ultimo accesso','Ultima modifica password','Ultimo tentativo errato']);
     const attrs=[['Nome',u.Name],['Account',u.SamAccountName],['Creato',u.Created||u.WhenCreated],['Ultima modifica',u.Modified||u.WhenChanged],['Ultimo accesso',u.LastLogonDate],['Ultima modifica password',u.PasswordLastSet],['Tentativi password errati',u.BadPwdCount],['Ultimo tentativo errato',u.LastBadPasswordAttempt],['Bloccato',u.LockedOut?'Sì':'No'],['E-mail',u.Mail],['Descrizione',u.Description],['Distinguished name',u.DistinguishedName]];
     const getOuPath=dn=>String(dn||'').split(/,(?=(?:[^\\]|\\.)*$)/).filter(x=>/^OU=/i.test(x)).map(x=>x.slice(3).replace(/\\,/g,',')).reverse();
     const currentList=()=>groups.map(g=>'<label class="group-option current-group-option"><input type="checkbox" checked data-current-member-dn="'+escapeHtml(g.DistinguishedName)+'"><span><strong>'+escapeHtml(g.Name)+'</strong><small>'+escapeHtml(g.DistinguishedName)+'</small></span></label>').join('')||'<p class="modal-hint">Nessun gruppo di appartenenza restituito da Active Directory.</p>';
     const expandedGroupOUs=new Set();
     const filteredTree=(items,term)=>{
       const rootNode={name:'',children:new Map(),groups:[]};
       const normalizedTerm=String(term||'').toLocaleLowerCase('it');
       const filteredItems=items.filter(g=>!normalizedTerm||[g.Name,g.Description,g.DistinguishedName].some(v=>String(v||'').toLocaleLowerCase('it').includes(normalizedTerm)));
       filteredItems.forEach(g=>{
         const path=getOuPath(g.DistinguishedName);let node=rootNode;
         path.forEach(name=>{if(!node.children.has(name))node.children.set(name,{name,children:new Map(),groups:[]});node=node.children.get(name);});
         node.groups.push(g);
       });
       const countGroups=node=>{if(node._count!==undefined)return node._count;node._count=node.groups.length+[...node.children.values()].reduce((n,c)=>n+countGroups(c),0);return node._count;};
       const groupOptions=groups=>groups.map(g=>'<label class="group-option"><input type="checkbox" data-available-group-dn="'+escapeHtml(g.DistinguishedName)+'"><span><strong>'+escapeHtml(g.Name)+'</strong><small>'+escapeHtml(g.Description||g.DistinguishedName)+'</small></span></label>').join('');
       const renderNode=node=>{
         const key=node.name;
         const open=Boolean(normalizedTerm)||expandedGroupOUs.has(key);
         const childrenHtml=open?[...node.children.values()].map(renderNode).join('')+groupOptions(node.groups):'';
         return '<section class="group-ou-card"><button type="button" class="group-ou-toggle '+(open?'is-open':'')+'" data-group-ou-toggle data-group-ou-name="'+escapeHtml(key)+'" aria-expanded="'+open+'"><span class="group-ou-chevron">'+(open?'⌄':'›')+'</span><span class="group-ou-name">'+escapeHtml(node.name)+'</span><span class="group-ou-count">'+countGroups(node)+'</span></button><div class="group-ou-content" '+(open?'':'hidden')+'>'+childrenHtml+'</div></section>';
       };
       const ous=[...rootNode.children.values()].map(renderNode).join('');
       const unplaced=rootNode.groups.length?'<section class="group-ou-card other-groups-card"><button type="button" class="group-ou-toggle '+(normalizedTerm||expandedGroupOUs.has('__other__')?'is-open':'')+'" data-group-ou-toggle data-group-ou-name="__other__" aria-expanded="'+(normalizedTerm||expandedGroupOUs.has('__other__'))+'"><span class="group-ou-chevron">'+(normalizedTerm||expandedGroupOUs.has('__other__')?'⌄':'›')+'</span><span class="group-ou-name">Altri gruppi</span><span class="group-ou-count">'+rootNode.groups.length+'</span></button><div class="group-ou-content" '+(normalizedTerm||expandedGroupOUs.has('__other__')?'':'hidden')+'>'+(normalizedTerm||expandedGroupOUs.has('__other__')?groupOptions(rootNode.groups):'')+'</div></section>':'';
       return ous+unplaced||'<p class="modal-hint">Nessun gruppo trovato.</p>';
     };
     const body='<div class="detail-grid">'+attrs.map(([k,v])=>'<div class="detail-item"><small>'+escapeHtml(k)+'</small><strong>'+escapeHtml(dateKeys.has(k)?formatAdDate(v):(v??'—'))+'</strong></div>').join('')+'</div><h3 class="modal-section-title">Gruppi attuali</h3><p class="modal-hint">Questi sono i gruppi a cui l’utente appartiene adesso. Deseleziona quelli da rimuovere.</p><div class="group-members-list current-groups-list">'+currentList()+'</div><h3 class="modal-section-title">Aggiungi gruppi personalizzati</h3><p class="modal-hint">Qui compaiono solo i gruppi non predefiniti di Windows. Apri una OU o cerca per nome, descrizione o CN/DN. Seleziona i gruppi da assegnare.</p><input class="modal-input" id="sa-group-search" type="search" placeholder="Cerca nome gruppo, CN o OU..."><div class="group-ou-browser" id="sa-group-browser"><p class="modal-hint">Preparazione elenco gruppi…</p></div><label class="modal-label" for="sa-add-user-groups">Aggiunta manuale (CN, DN o nome, uno per riga)</label><textarea class="modal-input" id="sa-add-user-groups" placeholder="CN=NomeGruppo,OU=Gruppi,DC=homelab,DC=local"></textarea><div class="modal-hint">Usa l’aggiunta manuale per gruppi predefiniti Windows o gruppi non presenti nell’elenco.</div><button class="secondary" id="sa-save-members">Salva appartenenze</button>';
     const root=showModal('Dettaglio utente',u.SamAccountName||'',body,'<button class="secondary" data-modal-cancel>Chiudi</button>');
     const browser=root.querySelector('#sa-group-browser'),search=root.querySelector('#sa-group-search');
     const wireTree=()=>browser.querySelectorAll('[data-group-ou-toggle]').forEach(button=>button.addEventListener('click',()=>{
       const key=button.dataset.groupOuName;
       if(search.value.trim()) return;
       if(expandedGroupOUs.has(key)) expandedGroupOUs.delete(key); else expandedGroupOUs.add(key);
       refreshTree();
     }));
     const refreshTree=()=>{
       const selected=new Set([...browser.querySelectorAll('[data-available-group-dn]:checked')].map(input=>input.dataset.availableGroupDn));
       browser.innerHTML=filteredTree(available,search.value.trim());
       browser.querySelectorAll('[data-available-group-dn]').forEach(input=>{input.checked=selected.has(input.dataset.availableGroupDn);});
       wireTree();
     };
     refreshTree();search.addEventListener('input',refreshTree);
     browser.addEventListener('sa-available-groups-loaded',()=>{available=Array.isArray(state.availableGroups)?state.availableGroups:[];refreshTree();});
     if(!Array.isArray(state.availableGroups)) send('availableGroups');
     root.querySelector('#sa-save-members').addEventListener('click',()=>{
       const keep=[...root.querySelectorAll('[data-current-member-dn]:checked')].map(x=>x.dataset.currentMemberDn);
       const add=[...root.querySelectorAll('[data-available-group-dn]:checked')].map(x=>x.dataset.availableGroupDn);
       const manual=root.querySelector('#sa-add-user-groups').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);
       closeModal();send('updateUserGroups','',{operation:'updateUserGroups',identity:u.DistinguishedName,groups:[...new Set(keep.concat(add,manual))]});
     });
     return;
   }
  if (result.operation === 'groupMembers' && result.success && result.data) {
    const members=result.data.members||[]; groupMemberSelections=new Set();
    const body='<h3 class="modal-section-title">Membri attuali</h3><div class="group-members-list">'+(members.map(m=>'<label><input type="checkbox" checked data-member-dn="'+escapeHtml(m.DistinguishedName)+'"> <span>'+escapeHtml(m.Name)+' <small>'+escapeHtml(m.ObjectClass)+'</small><small class="dn-caption">'+escapeHtml(m.DistinguishedName)+'</small></span></label>').join('')||'<p class="modal-hint">Il gruppo non contiene membri.</p>')+'</div><h3 class="modal-section-title">Aggiungi membri</h3><p class="modal-hint">Cerca per nome o account e seleziona un risultato, oppure inserisci direttamente un DN completo. Puoi aggiungere utenti e gruppi.</p><input class="modal-input" id="sa-member-search" type="search" placeholder="Cerca nome o account (almeno 2 caratteri)…" autocomplete="off"><div id="sa-member-search-results" class="member-search-results"></div><label class="modal-label" for="sa-add-members">DN da aggiungere manualmente</label><textarea class="modal-input" id="sa-add-members" placeholder="CN=Mario Rossi,OU=Utenti,DC=homelab,DC=local (uno per riga)"></textarea><div class="modal-hint">I risultati selezionati e i DN manuali vengono aggiunti al gruppo al salvataggio.</div>';
    const root=showModal('Membri del gruppo',result.data.name||result.data.group||'',body,'<button class="secondary" data-modal-cancel>Annulla</button><button class="primary" id="sa-save-group-members">Salva membri</button>');
    const search=root.querySelector('#sa-member-search'),results=root.querySelector('#sa-member-search-results');let searchTimer=null;
    search.addEventListener('input',()=>{
      clearTimeout(searchTimer);
      clearTimeout(groupMemberSearchTimeout);
      const q=search.value.trim();
      if(q.length<2){results.innerHTML='<p class="modal-hint">Digita almeno 2 caratteri per cercare.</p>';return;}
      const key=q.toLocaleLowerCase('it');
      const local=searchCachedDirectoryMembers(q);
      if(local.length){showMemberSearchResults(results,local,'Risultati dalla cache locale.');return;}
      if(groupMemberRemoteCache.has(key)){showMemberSearchResults(results,groupMemberRemoteCache.get(key),'Risultati memorizzati dalla ricerca AD.');return;}
      results.innerHTML='<p class="modal-hint">Nessun risultato locale. Ricerca in Active Directory…</p>';
      searchTimer=setTimeout(()=>{
        send('searchDirectoryMembers',q,{operation:'searchDirectoryMembers'});
        groupMemberSearchTimeout=setTimeout(()=>{
          const current=document.querySelector('#sa-member-search-results');
          if(current&&search.value.trim().toLocaleLowerCase('it')===key&&current.textContent.includes('Ricerca in Active Directory'))
            current.innerHTML='<div class="modal-error">La ricerca non ha ricevuto risposta entro 15 secondi. Verifica la connessione al dominio e riprova.</div>';
        },15000);
      },180);
    });
    root.querySelector('#sa-save-group-members').addEventListener('click',()=>{const keep=[...root.querySelectorAll('[data-member-dn]:checked')].map(x=>x.dataset.memberDn),manual=root.querySelector('#sa-add-members').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean),members=[...new Set(keep.concat([...groupMemberSelections],manual))];closeModal();send('updateGroupMembers','',{operation:'updateGroupMembers',identity:result.data.group,members});});
    root.dataset.groupDn=result.data.group;
    return;
  }
  if (result.operation === 'searchDirectoryMembers') {
    const responseQuery=String(result.query||'').trim();
    const responseKey=responseQuery.toLocaleLowerCase('it');
    const root=document.querySelector('.modal-card');if(!root||!root.dataset.groupDn)return;
    const results=root.querySelector('#sa-member-search-results');if(!results)return;
    if(result.success&&Array.isArray(result.data)) groupMemberRemoteCache.set(responseKey,result.data);
    if(root.querySelector('#sa-member-search').value.trim().toLocaleLowerCase('it')!==responseKey)return;
    clearTimeout(groupMemberSearchTimeout);
    if(!result.success||!Array.isArray(result.data)){results.innerHTML='<div class="modal-error">'+escapeHtml(result.error||'Ricerca non riuscita')+'</div>';return;}
    showMemberSearchResults(results,result.data,result.data.length?'Risultati da Active Directory.':'Nessun risultato in Active Directory.');
    return;
  }
  if (result.operation === 'ouContents' && result.success && result.data) {
    const objs=result.data.objects||[];
    const body='<div class="ou-contents-list">'+objs.map(o=>'<div class="ou-content-row"><strong>'+escapeHtml(o.Name)+'</strong><span>'+escapeHtml(o.ObjectClass)+'</span><small>'+escapeHtml(o.Description||o.DistinguishedName)+'</small>'+(String(o.ObjectClass).toLowerCase()==='organizationalunit'?'<button class="text-button" data-open-child-ou="'+escapeHtml(o.DistinguishedName)+'">Apri questa OU</button>':'')+'</div>').join('')+'</div>';
    showResultModal('Contenuto OU',result.data.ou,body);
    document.querySelectorAll('[data-open-child-ou]').forEach(button=>button.addEventListener('click',()=>{closeModal();send('ouContents','',{identity:button.dataset.openChildOu});}));
    return;
  }
  if (['createOU','updateOU','deleteOU','createUser','updateUser','copyUser','createGroup','deleteGroup','updateGroup','updateGroupMembers','updateUserGroups','deleteUser'].includes(result.operation)) {
    const userMutation = ['createUser','updateUser','copyUser','deleteUser'].includes(result.operation);
    const groupMutation = ['createGroup','deleteGroup','updateGroup','updateGroupMembers','updateUserGroups'].includes(result.operation);
    const ouMutation = ['createOU','updateOU','deleteOU'].includes(result.operation);
    if (userMutation && document.querySelector('#sa-modal-root')?.dataset.pendingOperation === result.operation) {
      const formRoot = document.querySelector('#sa-modal-root');
      if (result.success) {
        closeModal();
        window.__scriptAssystPendingForm = null;
        showResultModal('Operazione completata', result.data?.message || 'Modifiche applicate.', '<p>Active Directory ha confermato l’operazione.</p>');
      } else {
        formRoot.querySelectorAll('input,textarea,button').forEach(el=>{el.disabled=false;});
        formRoot.querySelector('#sa-save-progress')?.remove();
        delete formRoot.dataset.pendingOperation;
        const oldError=formRoot.querySelector('#sa-form-error'); if(oldError) oldError.remove();
        formRoot.querySelector('.modal-body')?.insertAdjacentHTML('beforeend','<div id="sa-form-error" class="modal-error">'+escapeHtml(result.error||'Operazione non completata. Correggi i dati e riprova.')+'</div>');
      }
    } else if (result.success) {
      showResultModal('Operazione completata', result.data?.message || 'Modifiche applicate.', '<p>Active Directory ha confermato l’operazione.</p>');
    } else {
      showResultModal('Operazione non completata','Active Directory ha rifiutato la richiesta.','<div class="modal-error">'+escapeHtml(result.error||'Errore non specificato')+'</div>');
    }
    if (ouMutation) { state.data.ous = null; if (state.page === 'ous') requestPage('ous', state.queries.ous || ''); }
    if (state.page === 'users' && userMutation) requestPage('users', state.queries.users || '');
    else if (state.page === 'groups' && groupMutation) requestPage('groups', state.queries.groups || '');
    if (state.page === 'overview') send('dashboard');
    return;
  }
  if (result.operation === 'availableGroups') {
    if(result.success && Array.isArray(result.data)) {
      state.availableGroups=result.data;
      document.querySelector('#sa-group-browser')?.dispatchEvent(new Event('sa-available-groups-loaded'));
      const picker=document.querySelector('#sa-create-group-browser');
      if(picker && picker.dataset.waiting==='true') document.querySelector('#sa-choose-create-groups')?.click();
    } else {
      state.availableGroups=[];
      const picker=document.querySelector('#sa-create-group-browser');
      if(picker && picker.dataset.waiting==='true') picker.innerHTML='<div class="modal-error">'+escapeHtml(result.error||'Impossibile caricare i gruppi')+'</div>';
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
    if (page === 'ous' && modalState?.flow === 'createGroupOU') { renderCreateGroupOuPicker(); return; }
    if (page === 'ous' && modalState?.flow === 'createUserOU') { renderCreateUserOuPicker(); return; }
    if (page === 'ous' && modalState?.flow === 'createUserOU') renderCreateUserOuPicker();
    else if (page === 'ous' && modalState && !modalState.destinationOU) renderOuPicker();
  } else {
    state.errors[page] = result.error || 'Risposta non valida dal backend.';
    state.data[page] = null;
  }
  if (state.page === page) render();
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
