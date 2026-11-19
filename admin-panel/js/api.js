(function () {
  const TOKEN_KEY = "vibei_admin_token";

  function base() {
    return (window.VIBEI_API_BASE || "").replace(/\/$/, "");
  }

  function getToken() {
    return localStorage.getItem(TOKEN_KEY) || "";
  }

  function setToken(token) {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  }

  async function request(path, options = {}) {
    const headers = Object.assign(
      { "Content-Type": "application/json" },
      options.headers || {}
    );
    const token = getToken();
    if (token) headers.Authorization = "Bearer " + token;

    const res = await fetch(base() + path, {
      method: options.method || "GET",
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    let data = null;
    const text = await res.text();
    try {
      data = text ? JSON.parse(text) : null;
    } catch (_) {
      data = { message: text };
    }

    if (!res.ok) {
      const err = new Error((data && data.message) || res.statusText);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  window.VibeiAdminApi = {
    getToken,
    setToken,
    getBase: base,
    setBase(url) {
      localStorage.setItem("vibei_api_base", url.replace(/\/$/, ""));
      window.VIBEI_API_BASE = url.replace(/\/$/, "");
    },
    login(email, password) {
      return request("/api/v1/admin/login", {
        method: "POST",
        body: { email, password },
      });
    },
    me() {
      return request("/api/v1/admin/me");
    },
    dashboard() {
      return request("/api/v1/admin/dashboard");
    },
    users() {
      return request("/api/v1/admin/users");
    },
    user(id) {
      return request("/api/v1/admin/users/" + id);
    },
    setDisabled(id, disabled) {
      return request("/api/v1/admin/users/" + id + "/disable", {
        method: "POST",
        body: { disabled },
      });
    },
    activities(category) {
      const q = category ? "?category=" + encodeURIComponent(category) : "";
      return request("/api/v1/admin/activities" + q);
    },
    usage() {
      return request("/api/v1/admin/usage");
    },
  };
})();
