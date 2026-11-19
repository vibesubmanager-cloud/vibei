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
      apikeys: "API keys",
    };
    pageTitle.textContent = titles[page] || page;
    content.innerHTML = '<p class="muted">Loading…</p>';
    try {
      if (page === "dashboard") await renderDashboard();
      else if (page === "users") await renderUsers();
      else if (page === "activities") await renderActivities();
      else if (page === "usage") await renderUsage();
      else if (page === "apikeys") await renderApiKeys();
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

  async function renderApiKeys() {
    const s = await api.aiSettings();
    content.innerHTML = `
      <div class="panel">
        <div class="panel-head">
          <strong>Gemini API key</strong>
          <span class="pill ${s.api_key_set ? "ok" : "bad"}">${
            s.api_key_set ? "key saved" : "no key"
          }</span>
        </div>
        <p class="muted">
          Store a Google Gemini key here. The describe test always uses Gemini.
          ${s.api_key_masked ? " Current: <code>" + escapeHtml(s.api_key_masked) + "</code>" : ""}
        </p>
        <label for="ai-provider">Provider</label>
        <select id="ai-provider">
          <option value="gemini" selected>gemini</option>
        </select>
        <label for="ai-model">Model</label>
        <select id="ai-model">
          ${(s.recommended_models || ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash"])
            .map((m) => {
              const cur = s.model || "gemini-3.8-flash";
              const sel = m === cur ? " selected" : "";
              return `<option value="${escapeHtml(m)}"${sel}>${escapeHtml(m)}</option>`;
            })
            .join("")}
        </select>
        <p class="muted" style="margin-top:6px">
          <code>gemini-2.0-flash</code> is shut down — use <code>gemini-3.8-flash</code>.
        </p>
        <label for="ai-api-key">API key (leave blank to keep existing)</label>
        <input id="ai-api-key" type="password" autocomplete="off" placeholder="AIza…" />
        <div class="toolbar" style="margin-top:14px">
          <button id="save-ai-key">Save key</button>
          <button class="secondary" id="test-ai-key">Test connection</button>
        </div>
        <p id="ai-key-msg" class="muted" style="margin-top:10px"></p>
      </div>

      <div class="panel" style="margin-top:12px">
        <div class="panel-head"><strong>Test: describe an image (Gemini)</strong></div>
        <p class="muted">Upload a photo — Gemini will return a short description if the key works.</p>
        <label for="describe-file">Image</label>
        <input id="describe-file" type="file" accept="image/*" />
        <div class="toolbar" style="margin-top:14px">
          <button id="run-describe">Describe image</button>
        </div>
        <pre id="describe-result" class="result-box" style="margin-top:12px;white-space:pre-wrap"></pre>
      </div>
    `;

    const msg = $("ai-key-msg");
    const result = $("describe-result");

    $("save-ai-key").addEventListener("click", async () => {
      msg.textContent = "Saving…";
      msg.className = "muted";
      try {
        const out = await api.saveAiSettings({
          provider: "gemini",
          model: $("ai-model").value.trim() || "gemini-3.8-flash",
          api_key: $("ai-api-key").value.trim(),
        });
        msg.textContent = out.api_key_set
          ? "Saved. Key is stored on the server. Model: " + (out.model || "")
          : "Saved model/provider (no new key sent).";
        msg.className = "ok-text";
        $("ai-api-key").value = "";
      } catch (err) {
        msg.textContent = err.message || "Save failed";
        msg.className = "error";
      }
    });

    $("test-ai-key").addEventListener("click", async () => {
      msg.textContent = "Testing Gemini…";
      msg.className = "muted";
      try {
        // Persist selected model before testing so the server uses it.
        await api.saveAiSettings({
          provider: "gemini",
          model: $("ai-model").value.trim() || "gemini-3.8-flash",
          api_key: $("ai-api-key").value.trim(),
        });
        $("ai-api-key").value = "";
        const out = await api.testAi();
        msg.textContent = out.ok
          ? "Connection OK — " +
            (out.model || "") +
            (out.reply ? " · " + out.reply : "")
          : "Test failed";
        msg.className = out.ok ? "ok-text" : "error";
      } catch (err) {
        msg.textContent = err.message || "Test failed";
        msg.className = "error";
      }
    });

    $("run-describe").addEventListener("click", async () => {
      const file = $("describe-file").files?.[0];
      if (!file) {
        result.textContent = "Choose an image first.";
        return;
      }
      result.textContent = "Uploading to Gemini…";
      try {
        const b64 = await fileToBase64(file);
        const out = await api.describeTest(b64);
        result.textContent =
          (out.description || "(empty)") +
          "\n\n— " +
          (out.provider || "gemini") +
          " / " +
          (out.model || "") +
          " · " +
          (out.latency_ms ?? "?") +
          " ms";
      } catch (err) {
        result.textContent = "Error: " + (err.message || "describe failed");
      }
    });
  }

  function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ""));
      reader.onerror = () => reject(new Error("Could not read file"));
      reader.readAsDataURL(file);
    });
  }

  boot();
})();
