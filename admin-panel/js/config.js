/**
 * Point this at your Render Flask backend.
 * After deploy, set e.g.:
 *   window.VIBEI_API_BASE = "https://vibei-api.onrender.com";
 */
window.VIBEI_API_BASE =
  window.VIBEI_API_BASE ||
  localStorage.getItem("vibei_api_base") ||
  "http://127.0.0.1:5000";
