(function () {
  const api = window.VibeiAdminApi;
  const $ = (id) => document.getElementById(id);

  const loginView = $("login-view");
  const appView = $("app-view");
  const loginError = $("login-error");
  const pageTitle = $("page-title");
  const adminEmail = $("admin-email");
  const content = $("content");

  let currentPage = "dashboard";

  function showLogin() {
    loginView.classList.remove("hidden");
    appView.classList.add("hidden");
  }

  function showApp() {
    loginView.classList.add("hidden");
    appView.classList.remove("hidden");
  }

  function setActiveNav(page) {
    document.querySelectorAll(".nav-btn").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.page === page);
    });
  }

  function fmt(iso) {
    if (!iso) return "—";
    try {
      return new Date(iso).toLocaleString();
    } catch (_) {
      return iso;
    }
  }

  function escapeHtml(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function boot() {
    $("api-base-input").value = api.getBase();
    if (!api.getToken()) {
      showLogin();
      return;
    }
    try {
      const me = await api.me();
      adminEmail.textContent = me.email;
      showApp();
      go("dashboard");
    } catch (_) {
      api.setToken("");
      showLogin();
    }
  }

  $("login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    loginError.textContent = "";
    const email = $("email").value.trim();
    const password = $("password").value;
    const base = $("api-base-input").value.trim();
    if (base) api.setBase(base);
    try {
      const data = await api.login(email, password);
      api.setToken(data.access_token);
      adminEmail.textContent = data.admin.email;
      showApp();
      go("dashboard");
    } catch (err) {
      loginError.textContent = err.message || "Login failed";
    }
  });

  $("logout-btn").addEventListener("click", () => {
    api.setToken("");
    showLogin();
  });

  document.querySelectorAll(".nav-btn").forEach((btn) => {
    btn.addEventListener("click", () => go(btn.dataset.page));
  });

  async function go(page) {
    currentPage = page;
    setActiveNav(page);
    const titles = {
      dashboard: "Dashboard",
      users: "Users",
      activities: "Activities",
      usage: "AI / API usage",
    };
    pageTitle.textContent = titles[page] || page;
    content.innerHTML = '<p class="muted">Loading…</p>';
    try {
      if (page === "dashboard") await renderDashboard();
      else if (page === "users") await renderUsers();
      else if (page === "activities") await renderActivities();
      else if (page === "usage") await renderUsage();
    } catch (err) {
      content.innerHTML =
        '<p class="error">' + escapeHtml(err.message || "Failed") + "</p>";
      if (err.status === 401) {
        api.setToken("");
        showLogin();
      }
    }
  }

  async function renderDashboard() {
    const d = await api.dashboard();
    content.innerHTML = `
      <div class="stats">
        <div class="stat"><div class="label">Total users</div><div class="value">${d.users.total}</div></div>
        <div class="stat"><div class="label">Active (24h)</div><div class="value">${d.users.active_24h}</div></div>
        <div class="stat"><div class="label">Signups (7d)</div><div class="value">${d.users.signups_7d}</div></div>
        <div class="stat"><div class="label">AI requests (24h)</div><div class="value">${d.ai_requests_24h}</div></div>
        <div class="stat"><div class="label">Object detection (24h)</div><div class="value">${d.object_detection_24h}</div></div>
        <div class="stat"><div class="label">Scene description (24h)</div><div class="value">${d.scene_description_24h}</div></div>
      </div>
      <div class="panel">
        <div class="panel-head"><strong>Usage by feature (24h)</strong></div>
        <table>
          <thead><tr><th>Feature</th><th>Count</th></tr></thead>
          <tbody>
            ${Object.entries(d.usage_24h || {})
              .map(
                ([k, v]) =>
                  `<tr><td>${escapeHtml(k)}</td><td>${v}</td></tr>`
              )
              .join("") || '<tr><td colspan="2">No usage yet</td></tr>'}
          </tbody>
        </table>
      </div>
      <div class="panel" style="margin-top:12px">
        <div class="panel-head"><strong>Activity by category (24h)</strong></div>
        <table>
          <thead><tr><th>Category</th><th>Count</th></tr></thead>
          <tbody>
            ${Object.entries(d.activity_24h || {})
              .map(
                ([k, v]) =>
                  `<tr><td>${escapeHtml(k)}</td><td>${v}</td></tr>`
              )
              .join("") || '<tr><td colspan="2">No activity yet</td></tr>'}
          </tbody>
        </table>
      </div>
    `;
  }

  async function renderUsers() {
    const data = await api.users();
    content.innerHTML = `
      <div class="panel">
        <div class="panel-head">
          <strong>All app users</strong>
          <span class="muted">${data.users.length} shown</span>
        </div>
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Email</th>
              <th>Status</th>
              <th>Last login</th>
              <th>Last seen</th>
              <th>AI uses</th>
              <th>Object detect</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            ${data.users
              .map(
                (u) => `
              <tr>
                <td>${u.id}</td>
                <td>${escapeHtml(u.email)}</td>
                <td><span class="pill ${u.disabled ? "bad" : "ok"}">${
                  u.disabled ? "disabled" : "active"
                }</span></td>
                <td>${fmt(u.last_login_at)}</td>
                <td>${fmt(u.last_seen_at)}</td>
                <td>${u.ai_total || 0}</td>
                <td>${u.object_detection_total || 0}</td>
                <td>
                  <button class="secondary" data-user="${u.id}">Details</button>
                  <button class="${u.disabled ? "secondary" : "danger"}" data-toggle="${u.id}" data-disabled="${u.disabled}">
                    ${u.disabled ? "Enable" : "Disable"}
                  </button>
                </td>
              </tr>`
              )
              .join("")}
          </tbody>
        </table>
      </div>
      <div id="user-detail" style="margin-top:12px"></div>
    `;

    content.querySelectorAll("[data-user]").forEach((btn) => {
      btn.addEventListener("click", () => showUserDetail(Number(btn.dataset.user)));
    });
    content.querySelectorAll("[data-toggle]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = Number(btn.dataset.toggle);
        const currentlyDisabled = btn.dataset.disabled === "true";
        await api.setDisabled(id, !currentlyDisabled);
        renderUsers();
      });
    });
  }

  async function showUserDetail(id) {
    const box = $("user-detail");
    box.innerHTML = '<p class="muted">Loading user…</p>';
    const data = await api.user(id);
    box.innerHTML = `
      <div class="panel">
        <div class="panel-head"><strong>${escapeHtml(data.user.email)}</strong> — recent activity</div>
        <table>
          <thead><tr><th>When</th><th>Category</th><th>Action</th><th>OK</th></tr></thead>
          <tbody>
            ${data.recent_activity
              .map(
                (a) => `
              <tr>
                <td>${fmt(a.created_at)}</td>
                <td><span class="pill">${escapeHtml(a.category)}</span></td>
                <td>${escapeHtml(a.action)}</td>
                <td>${a.ok ? "yes" : "no"}</td>
              </tr>`
              )
              .join("") || '<tr><td colspan="4">No activity</td></tr>'}
          </tbody>
        </table>
      </div>
    `;
  }

  async function renderActivities() {
    const data = await api.activities();
    content.innerHTML = `
      <div class="panel">
        <div class="panel-head">
          <strong>Live activity feed</strong>
          <div class="toolbar">
            <select id="cat-filter">
              <option value="">All categories</option>
              <option value="auth">auth</option>
              <option value="object_search">object_search</option>
              <option value="object_detection">object_detection</option>
              <option value="text_search">text_search</option>
              <option value="scene_description">scene_description</option>
              <option value="ai_describe">ai_describe</option>
              <option value="ai_read">ai_read</option>
              <option value="ai_voice">ai_voice</option>
            </select>
            <button class="secondary" id="refresh-acts">Refresh</button>
          </div>
        </div>
        <table>
          <thead>
            <tr><th>When</th><th>User</th><th>Category</th><th>Action</th><th>Detail</th></tr>
          </thead>
          <tbody id="acts-body">
            ${rowsActivities(data.activities)}
          </tbody>
        </table>
      </div>
    `;
    $("refresh-acts").addEventListener("click", async () => {
      const cat = $("cat-filter").value;
      const d = await api.activities(cat);
      $("acts-body").innerHTML = rowsActivities(d.activities);
    });
    $("cat-filter").addEventListener("change", async () => {
      const d = await api.activities($("cat-filter").value);
      $("acts-body").innerHTML = rowsActivities(d.activities);
    });
  }

  function rowsActivities(list) {
    if (!list || !list.length) return '<tr><td colspan="5">No activities</td></tr>';
    return list
      .map(
        (a) => `
      <tr>
        <td>${fmt(a.created_at)}</td>
        <td>${escapeHtml(a.email || a.user_id || "—")}</td>
        <td><span class="pill">${escapeHtml(a.category)}</span></td>
        <td>${escapeHtml(a.action)}</td>
        <td><code>${escapeHtml(JSON.stringify(a.detail || {}))}</code></td>
      </tr>`
      )
      .join("");
  }

  async function renderUsage() {
    const data = await api.usage();
    content.innerHTML = `
      <div class="panel">
        <div class="panel-head"><strong>AI / cloud API usage events</strong></div>
        <table>
          <thead>
            <tr><th>When</th><th>User</th><th>Feature</th><th>OK</th><th>Latency</th><th>Error</th></tr>
          </thead>
          <tbody>
            ${data.events
              .map(
                (e) => `
              <tr>
                <td>${fmt(e.created_at)}</td>
                <td>${e.user_id ?? "—"}</td>
                <td>${escapeHtml(e.feature)}</td>
                <td><span class="pill ${e.ok ? "ok" : "bad"}">${e.ok ? "ok" : "fail"}</span></td>
                <td>${e.latency_ms} ms</td>
                <td>${escapeHtml(e.error_code || "")}</td>
              </tr>`
              )
              .join("") || '<tr><td colspan="6">No usage events</td></tr>'}
          </tbody>
        </table>
      </div>
    `;
  }

  boot();
})();
