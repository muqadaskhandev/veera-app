(function () {
  const TOKEN_KEY = 'verra_admin_token';
  const PAGE_TITLES = {
    dashboard: 'Dashboard',
    users: 'Users',
    clients: 'Clients',
    subscriptions: 'Subscriptions',
    sessions: 'Sessions',
    invites: 'Invites',
    deliveries: 'Notification Deliveries',
    exercises: 'Exercise Library',
  };

  let currentPage = 'dashboard';
  let adminUser = null;

  const $ = (sel) => document.querySelector(sel);
  const loginView = $('#login-view');
  const shell = $('#shell');
  const pageContent = $('#page-content');
  const pageTitle = $('#page-title');
  const toast = $('#toast');

  function getToken() {
    return sessionStorage.getItem(TOKEN_KEY);
  }

  function setToken(token) {
    if (token) sessionStorage.setItem(TOKEN_KEY, token);
    else sessionStorage.removeItem(TOKEN_KEY);
  }

  function showToast(msg, type = 'success') {
    toast.textContent = msg;
    toast.className = `toast ${type}`;
    setTimeout(() => toast.classList.add('hidden'), 3500);
  }

  async function api(path, options = {}) {
    const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
    const token = getToken();
    if (token) headers.Authorization = `Bearer ${token}`;

    const res = await fetch(path, { ...options, headers });
    if (res.status === 401) {
      setToken(null);
      showLogin();
      throw new Error('Session expired');
    }
    if (!res.ok) {
      let reason = res.statusText;
      try {
        const body = await res.json();
        reason = body.reason || body.message || reason;
      } catch (_) {}
      throw new Error(reason);
    }
    if (res.status === 204) return null;
    return res.json();
  }

  function fmtDate(d) {
    if (!d) return '—';
    return new Date(d).toLocaleString();
  }

  function badge(text, kind) {
    return `<span class="badge badge-${kind}">${text}</span>`;
  }

  function roleBadge(role) {
    return badge(role, role);
  }

  function statusBadge(active) {
    return active ? badge('active', 'active') : badge('inactive', 'inactive');
  }

  function deliveryBadge(status) {
    return badge(status, status);
  }

  function showLogin() {
    loginView.classList.remove('hidden');
    shell.classList.add('hidden');
    adminUser = null;
  }

  function showApp() {
    loginView.classList.add('hidden');
    shell.classList.remove('hidden');
    $('#admin-email').textContent = adminUser?.email || '';
  }

  async function verifySession() {
    const token = getToken();
    if (!token) return false;
    try {
      adminUser = await api('/api/auth/me');
      if (adminUser.role !== 'admin') {
        setToken(null);
        throw new Error('Admin access required');
      }
      return true;
    } catch {
      setToken(null);
      return false;
    }
  }

  async function handleLogin(e) {
    e.preventDefault();
    const errEl = $('#login-error');
    errEl.classList.add('hidden');
    const email = $('#email').value.trim();
    const password = $('#password').value;

    try {
      const res = await api('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      });
      setToken(res.accessToken);
      adminUser = res.user;
      if (adminUser.role !== 'admin') {
        setToken(null);
        throw new Error('This account is not an admin');
      }
      showApp();
      navigate('dashboard');
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  }

  function navigate(page) {
    currentPage = page;
    document.querySelectorAll('.nav-item').forEach((el) => {
      el.classList.toggle('active', el.dataset.page === page);
    });
    pageTitle.textContent = PAGE_TITLES[page] || page;
    loadPage(page);
  }

  async function loadPage(page) {
    pageContent.innerHTML = '<div class="loading">Loading…</div>';
    try {
      switch (page) {
        case 'dashboard': await renderDashboard(); break;
        case 'users': await renderUsers(); break;
        case 'clients': await renderClients(); break;
        case 'subscriptions': await renderSubscriptions(); break;
        case 'sessions': await renderSessions(); break;
        case 'invites': await renderInvites(); break;
        case 'deliveries': await renderDeliveries(); break;
        case 'exercises': await renderExercises(); break;
      }
    } catch (err) {
      pageContent.innerHTML = `<div class="empty">Error: ${esc(err.message)}</div>`;
    }
  }

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  async function renderDashboard() {
    const data = await api('/api/admin/dashboard');
    pageContent.innerHTML = `
      <div class="stats-grid">
        ${statCard('Total Users', data.users.total, `${data.users.active} active · ${data.users.inactive} inactive`)}
        ${statCard('Trainers', data.users.trainers)}
        ${statCard('Clients', data.users.clients)}
        ${statCard('Admins', data.users.admins)}
        ${statCard('Subscriptions', data.subscriptions.active, `${data.subscriptions.total} total · ${data.subscriptions.expired} expired`)}
        ${statCard('Upcoming Sessions', data.sessions.upcoming, `${data.sessions.completedThisWeek} completed this week`)}
        ${statCard('Pending Deliveries', data.deliveries.pending, `${data.deliveries.failed} failed total`)}
        ${statCard('Invites', data.invites.redeemable, `${data.invites.redeemed} redeemed`)}
      </div>
      <div class="section">
        <div class="section-header">Recent signups</div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Joined</th></tr></thead>
            <tbody>
              ${data.recentUsers.length ? data.recentUsers.map(u => `
                <tr>
                  <td>${esc(u.displayName)}</td>
                  <td>${esc(u.email || '—')}</td>
                  <td>${roleBadge(u.role)}</td>
                  <td>${statusBadge(u.isActive)}</td>
                  <td>${fmtDate(u.createdAt)}</td>
                </tr>
              `).join('') : '<tr><td colspan="5" class="empty">No users yet</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
      <div class="section">
        <div class="section-header">Delivery summary (24h)</div>
        <div class="stats-grid" style="padding:16px;margin:0">
          ${statCard('Total', data.deliveries.last24Hours.total)}
          ${statCard('Delivered', data.deliveries.last24Hours.delivered)}
          ${statCard('Failed', data.deliveries.last24Hours.failed)}
          ${statCard('Sent', data.deliveries.sent)}
          ${statCard('Delivered (all)', data.deliveries.delivered)}
          ${statCard('Bounced', data.deliveries.bounced)}
        </div>
      </div>
    `;
  }

  function statCard(label, value, sub) {
    return `<div class="stat-card"><div class="label">${esc(label)}</div><div class="value">${esc(String(value))}</div>${sub ? `<div class="sub">${esc(sub)}</div>` : ''}</div>`;
  }

  async function renderUsers() {
    pageContent.innerHTML = `
      <div class="section">
        <div class="toolbar">
          <input type="search" id="user-search" placeholder="Search name or email…">
          <select id="user-role">
            <option value="">All roles</option>
            <option value="trainer">Trainer</option>
            <option value="client">Client</option>
            <option value="admin">Admin</option>
          </select>
          <button class="btn btn-ghost btn-sm" id="user-filter-btn">Apply</button>
          <button class="btn btn-primary btn-sm" id="user-create-toggle">Add user</button>
        </div>
        <div id="user-create-panel" class="panel-form hidden">
          <h3>Create user</h3>
          <div class="form-grid">
            <div><label>Email</label><input id="new-user-email" type="email"></div>
            <div><label>Password</label><input id="new-user-password" type="password"></div>
            <div><label>Display name</label><input id="new-user-name"></div>
            <div><label>Role</label>
              <select id="new-user-role">
                <option value="trainer">Trainer</option>
                <option value="client">Client</option>
                <option value="admin">Admin</option>
              </select>
            </div>
            <div id="new-user-trainer-wrap"><label>Trainer ID (clients)</label><input id="new-user-trainer-id" placeholder="Optional UUID"></div>
          </div>
          <div class="form-actions">
            <button class="btn btn-primary btn-sm" id="user-create-submit">Create</button>
            <button class="btn btn-ghost btn-sm" id="user-create-cancel">Cancel</button>
          </div>
        </div>
        <div id="users-table" class="loading">Loading…</div>
      </div>
    `;
    $('#user-create-toggle').addEventListener('click', () => {
      $('#user-create-panel').classList.toggle('hidden');
    });
    $('#user-create-cancel').addEventListener('click', () => {
      $('#user-create-panel').classList.add('hidden');
    });
    $('#user-create-submit').addEventListener('click', createUser);
    await loadUsers();
    $('#user-filter-btn').addEventListener('click', loadUsers);
    $('#user-search').addEventListener('keydown', (e) => { if (e.key === 'Enter') loadUsers(); });
  }

  async function createUser() {
    const payload = {
      email: $('#new-user-email').value.trim(),
      password: $('#new-user-password').value,
      displayName: $('#new-user-name').value.trim(),
      role: $('#new-user-role').value,
      isEmailVerified: true,
    };
    const trainerID = $('#new-user-trainer-id').value.trim();
    if (trainerID) payload.trainerID = trainerID;
    try {
      await api('/api/admin/users', { method: 'POST', body: JSON.stringify(payload) });
      showToast('User created');
      $('#user-create-panel').classList.add('hidden');
      await loadUsers();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function loadUsers() {
    const search = $('#user-search')?.value || '';
    const role = $('#user-role')?.value || '';
    const params = new URLSearchParams({ limit: '200' });
    if (search) params.set('search', search);
    if (role) params.set('role', role);

    const users = await api(`/api/admin/users?${params}`);
    const el = $('#users-table');
    el.className = 'table-wrap';
    el.innerHTML = `
      <table>
        <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Verified</th><th>Status</th><th>Last seen</th><th>Actions</th></tr></thead>
        <tbody>
          ${users.map(u => `
            <tr data-user-id="${u.id}">
              <td>${esc(u.displayName)}</td>
              <td>${esc(u.email || '—')}</td>
              <td>${roleBadge(u.role)}</td>
              <td>${u.isEmailVerified ? '✓' : '—'}</td>
              <td>${statusBadge(u.isActive)}</td>
              <td>${fmtDate(u.lastSeenAt)}</td>
              <td class="actions">
                ${u.isActive
                  ? `<button class="btn btn-danger btn-sm" data-action="deactivate" data-id="${u.id}">Deactivate</button>`
                  : `<button class="btn btn-success btn-sm" data-action="activate" data-id="${u.id}">Activate</button>`}
                <button class="btn btn-ghost btn-sm" data-action="edit" data-id="${u.id}">Edit</button>
                <button class="btn btn-danger btn-sm" data-action="delete" data-id="${u.id}">Delete</button>
              </td>
            </tr>
          `).join('') || '<tr><td colspan="7" class="empty">No users found</td></tr>'}
        </tbody>
      </table>
    `;
    el.querySelectorAll('[data-action]').forEach((btn) => {
      const action = btn.dataset.action;
      if (action === 'activate' || action === 'deactivate') {
        btn.addEventListener('click', () => toggleUserStatus(btn.dataset.id, action === 'activate'));
      } else if (action === 'edit') {
        btn.addEventListener('click', () => editUser(btn.dataset.id));
      } else if (action === 'delete') {
        btn.addEventListener('click', () => deleteUser(btn.dataset.id));
      }
    });
  }

  async function editUser(userId) {
    const detail = await api(`/api/admin/users/${userId}`);
    const u = detail.user;
    const displayName = prompt('Display name', u.displayName);
    if (displayName === null) return;
    const role = prompt('Role (trainer, client, admin)', u.role);
    if (role === null) return;
    const password = prompt('New password (leave blank to keep current)');
    const payload = { displayName, role };
    if (password) payload.password = password;
    try {
      await api(`/api/admin/users/${userId}`, { method: 'PATCH', body: JSON.stringify(payload) });
      showToast('User updated');
      await loadUsers();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function deleteUser(userId) {
    if (!confirm('Permanently delete this user and related data?')) return;
    try {
      await api(`/api/admin/users/${userId}`, { method: 'DELETE' });
      showToast('User deleted');
      await loadUsers();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function renderClients() {
    const rows = await api('/api/admin/clients?limit=200');
    pageContent.innerHTML = `
      <div class="section">
        <div class="table-wrap">
          <table>
            <thead><tr><th>Name</th><th>Email</th><th>Status</th><th>Sessions left</th><th>Trainer</th><th>Actions</th></tr></thead>
            <tbody>
              ${rows.map(r => `
                <tr>
                  <td>${esc(r.name)}</td>
                  <td>${esc(r.email || '—')}</td>
                  <td>${esc(r.status)}</td>
                  <td>${r.sessionsRemaining}</td>
                  <td><code>${esc(r.trainerID || '—')}</code></td>
                  <td class="actions">
                    <button class="btn btn-danger btn-sm" data-delete-client="${r.id}">Delete</button>
                  </td>
                </tr>
              `).join('') || '<tr><td colspan="6" class="empty">No clients</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
    pageContent.querySelectorAll('[data-delete-client]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        if (!confirm('Delete this client and all related data?')) return;
        try {
          await api(`/api/admin/clients/${btn.dataset.deleteClient}`, { method: 'DELETE' });
          showToast('Client deleted');
          await renderClients();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  async function toggleUserStatus(userId, isActive) {
    try {
      await api(`/api/admin/users/${userId}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ isActive }),
      });
      showToast(isActive ? 'User activated' : 'User deactivated');
      await loadUsers();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function renderSubscriptions() {
    const rows = await api('/api/admin/subscriptions?limit=100');
    pageContent.innerHTML = `
      <div class="section">
        <div class="table-wrap">
          <table>
            <thead><tr><th>User</th><th>Email</th><th>Product</th><th>Status</th><th>Expires</th><th>Created</th><th>Actions</th></tr></thead>
            <tbody>
              ${rows.map(r => `
                <tr>
                  <td>${esc(r.userName)}</td>
                  <td>${esc(r.userEmail || '—')}</td>
                  <td>${esc(r.productID)}</td>
                  <td>${r.isActive ? badge('active', 'active') : badge(r.status, 'inactive')}</td>
                  <td>${fmtDate(r.expiresAt)}</td>
                  <td>${fmtDate(r.createdAt)}</td>
                  <td class="actions">
                    <button class="btn btn-ghost btn-sm" data-edit-sub="${r.id}" data-status="${esc(r.status)}">Edit</button>
                  </td>
                </tr>
              `).join('') || '<tr><td colspan="7" class="empty">No subscriptions</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
    pageContent.querySelectorAll('[data-edit-sub]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const status = prompt('Status (active, expired, cancelled)', btn.dataset.status);
        if (status === null) return;
        const expiresRaw = prompt('Expires at (ISO date, optional)');
        const payload = { status };
        if (expiresRaw) payload.expiresAt = new Date(expiresRaw).toISOString();
        try {
          await api(`/api/admin/subscriptions/${btn.dataset.editSub}`, {
            method: 'PATCH',
            body: JSON.stringify(payload),
          });
          showToast('Subscription updated');
          await renderSubscriptions();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  async function renderSessions() {
    const rows = await api('/api/admin/sessions?limit=50');
    pageContent.innerHTML = `
      <div class="section">
        <div class="table-wrap">
          <table>
            <thead><tr><th>Client</th><th>Focus</th><th>Scheduled</th><th>Status</th><th>Actions</th></tr></thead>
            <tbody>
              ${rows.map(r => `
                <tr>
                  <td>${esc(r.clientName)}</td>
                  <td>${esc(r.focus)}</td>
                  <td>${fmtDate(r.scheduledAt)}</td>
                  <td>${r.isCompleted ? badge('completed', 'delivered') : r.isSkipped ? badge('skipped', 'inactive') : badge('scheduled', 'pending')}</td>
                  <td class="actions">
                    <button class="btn btn-ghost btn-sm" data-complete-session="${r.id}">Complete</button>
                    <button class="btn btn-danger btn-sm" data-delete-session="${r.id}">Delete</button>
                  </td>
                </tr>
              `).join('') || '<tr><td colspan="5" class="empty">No sessions</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
    pageContent.querySelectorAll('[data-complete-session]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        try {
          await api(`/api/admin/sessions/${btn.dataset.completeSession}`, {
            method: 'PATCH',
            body: JSON.stringify({ isCompleted: true }),
          });
          showToast('Session marked complete');
          await renderSessions();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
    pageContent.querySelectorAll('[data-delete-session]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        if (!confirm('Delete this session?')) return;
        try {
          await api(`/api/admin/sessions/${btn.dataset.deleteSession}`, { method: 'DELETE' });
          showToast('Session deleted');
          await renderSessions();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  async function renderInvites() {
    const trainers = await api('/api/admin/trainers?limit=100');
    const rows = await api('/api/admin/invites?limit=100');
    const trainerOptions = trainers.map(t => `<option value="${t.id}">${esc(t.name)} (${t.id})</option>`).join('');
    pageContent.innerHTML = `
      <div class="section">
        <div class="panel-form">
          <h3>Create invite</h3>
          <div class="form-grid">
            <div><label>Trainer</label><select id="invite-trainer">${trainerOptions}</select></div>
            <div><label>Client email</label><input id="invite-email" type="email"></div>
            <div><label>Client name</label><input id="invite-name"></div>
            <div><label>Expires in days</label><input id="invite-days" type="number" value="14"></div>
          </div>
          <div class="form-actions">
            <button class="btn btn-primary btn-sm" id="invite-create-btn">Create invite</button>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Code</th><th>Trainer ID</th><th>Invited email</th><th>Status</th><th>Expires</th><th>Redeemed</th><th>Actions</th></tr></thead>
            <tbody>
              ${rows.map(r => `
                <tr>
                  <td><code>${esc(r.code)}</code></td>
                  <td><code>${esc(r.trainerID)}</code></td>
                  <td>${esc(r.invitedEmail || '—')}</td>
                  <td>${r.isRedeemable ? badge('open', 'pending') : r.redeemedAt ? badge('redeemed', 'delivered') : badge('expired', 'inactive')}</td>
                  <td>${fmtDate(r.expiresAt)}</td>
                  <td>${fmtDate(r.redeemedAt)}</td>
                  <td class="actions">
                    ${r.isRedeemable ? `<button class="btn btn-danger btn-sm" data-delete-invite="${r.id}">Delete</button>` : '—'}
                  </td>
                </tr>
              `).join('') || '<tr><td colspan="7" class="empty">No invites</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
    $('#invite-create-btn').addEventListener('click', async () => {
      const payload = {
        trainerID: $('#invite-trainer').value,
        expiresInDays: parseInt($('#invite-days').value, 10) || 14,
        clientEmail: $('#invite-email').value.trim() || undefined,
        clientName: $('#invite-name').value.trim() || undefined,
      };
      try {
        const res = await api('/api/admin/invites', { method: 'POST', body: JSON.stringify(payload) });
        showToast(`Invite created: ${res.invite.code}`);
        await renderInvites();
      } catch (err) {
        showToast(err.message, 'error');
      }
    });
    pageContent.querySelectorAll('[data-delete-invite]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        if (!confirm('Delete this invite?')) return;
        try {
          await api(`/api/admin/invites/${btn.dataset.deleteInvite}`, { method: 'DELETE' });
          showToast('Invite deleted');
          await renderInvites();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  async function renderDeliveries() {
    pageContent.innerHTML = `
      <div class="section">
        <div class="toolbar">
          <select id="delivery-status">
            <option value="">All statuses</option>
            <option value="pending">Pending</option>
            <option value="sent">Sent</option>
            <option value="delivered">Delivered</option>
            <option value="failed">Failed</option>
            <option value="bounced">Bounced</option>
          </select>
          <select id="delivery-channel">
            <option value="">All channels</option>
            <option value="push">Push</option>
            <option value="sms">SMS</option>
            <option value="email">Email</option>
          </select>
          <button class="btn btn-ghost btn-sm" id="delivery-filter-btn">Apply</button>
        </div>
        <div id="deliveries-table" class="loading">Loading…</div>
      </div>
    `;
    await loadDeliveries();
    $('#delivery-filter-btn').addEventListener('click', loadDeliveries);
  }

  async function loadDeliveries() {
    const status = $('#delivery-status')?.value || '';
    const channel = $('#delivery-channel')?.value || '';
    const params = new URLSearchParams({ limit: '100' });
    if (status) params.set('status', status);
    if (channel) params.set('channel', channel);

    const rows = await api(`/api/admin/notifications/deliveries?${params}`);
    const el = $('#deliveries-table');
    el.className = 'table-wrap';
    el.innerHTML = `
      <table>
        <thead><tr><th>Channel</th><th>Kind</th><th>Recipient</th><th>Title</th><th>Status</th><th>Attempts</th><th>Sent</th><th>Actions</th></tr></thead>
        <tbody>
          ${rows.map(r => `
            <tr>
              <td>${esc(r.channel)}</td>
              <td>${esc(r.kind)}</td>
              <td>${esc(r.recipient)}</td>
              <td title="${esc(r.body)}">${esc(r.title)}</td>
              <td>${deliveryBadge(r.status)}</td>
              <td>${r.attemptCount}/${r.maxAttempts}</td>
              <td>${fmtDate(r.sentAt)}</td>
              <td class="actions">
                ${['failed', 'bounced', 'pending'].includes(r.status)
                  ? `<button class="btn btn-ghost btn-sm" data-retry="${r.id}">Retry</button>`
                  : '—'}
              </td>
            </tr>
          `).join('') || '<tr><td colspan="8" class="empty">No deliveries</td></tr>'}
        </tbody>
      </table>
    `;
    el.querySelectorAll('[data-retry]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        try {
          await api(`/api/admin/notifications/deliveries/${btn.dataset.retry}/retry`, { method: 'POST' });
          showToast('Retry queued');
          await loadDeliveries();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  async function renderExercises() {
    const rows = await api('/api/admin/exercises?limit=200');
    pageContent.innerHTML = `
      <div class="section">
        <div class="panel-form">
          <h3>Add exercise</h3>
          <div class="form-grid">
            <div><label>Name</label><input id="ex-name"></div>
            <div><label>Category</label>
              <select id="ex-category">
                <option value="strength">strength</option>
                <option value="conditioning">conditioning</option>
                <option value="accessory">accessory</option>
                <option value="mobility">mobility</option>
                <option value="cardio">cardio</option>
              </select>
            </div>
          </div>
          <label>Description</label>
          <textarea id="ex-description"></textarea>
          <div class="form-actions">
            <button class="btn btn-primary btn-sm" id="ex-create-btn">Add exercise</button>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Name</th><th>Category</th><th>Description</th><th>Actions</th></tr></thead>
            <tbody>
              ${rows.map(r => `
                <tr>
                  <td>${esc(r.name)}</td>
                  <td>${esc(r.category)}</td>
                  <td>${esc((r.description || '').slice(0, 80))}${(r.description || '').length > 80 ? '…' : ''}</td>
                  <td class="actions">
                    <button class="btn btn-ghost btn-sm" data-edit-exercise="${r.id}" data-name="${esc(r.name)}" data-category="${esc(r.category)}">Edit</button>
                    <button class="btn btn-danger btn-sm" data-delete-exercise="${r.id}">Delete</button>
                  </td>
                </tr>
              `).join('') || '<tr><td colspan="4" class="empty">No exercises</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
    $('#ex-create-btn').addEventListener('click', async () => {
      const payload = {
        name: $('#ex-name').value.trim(),
        category: $('#ex-category').value,
        description: $('#ex-description').value.trim() || undefined,
      };
      try {
        await api('/api/admin/exercises', { method: 'POST', body: JSON.stringify(payload) });
        showToast('Exercise created');
        await renderExercises();
      } catch (err) {
        showToast(err.message, 'error');
      }
    });
    pageContent.querySelectorAll('[data-edit-exercise]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const name = prompt('Name', btn.dataset.name);
        if (name === null) return;
        const category = prompt('Category', btn.dataset.category);
        if (category === null) return;
        try {
          await api(`/api/admin/exercises/${btn.dataset.editExercise}`, {
            method: 'PATCH',
            body: JSON.stringify({ name, category }),
          });
          showToast('Exercise updated');
          await renderExercises();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
    pageContent.querySelectorAll('[data-delete-exercise]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        if (!confirm('Delete this exercise?')) return;
        try {
          await api(`/api/admin/exercises/${btn.dataset.deleteExercise}`, { method: 'DELETE' });
          showToast('Exercise deleted');
          await renderExercises();
        } catch (err) {
          showToast(err.message, 'error');
        }
      });
    });
  }

  // Event listeners
  $('#login-form').addEventListener('submit', handleLogin);
  $('#logout-btn').addEventListener('click', () => { setToken(null); showLogin(); });
  $('#refresh-btn').addEventListener('click', () => loadPage(currentPage));
  document.querySelectorAll('.nav-item').forEach((el) => {
    el.addEventListener('click', () => navigate(el.dataset.page));
  });

  // Boot
  (async () => {
    if (await verifySession()) {
      showApp();
      navigate('dashboard');
    } else {
      showLogin();
    }
  })();
})();
