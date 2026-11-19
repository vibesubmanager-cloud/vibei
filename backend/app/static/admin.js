async function postJson(url, body) {
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    || document.querySelector('input[name="csrf_token"]')?.value;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRFToken": csrf || "",
    },
    body: JSON.stringify(body || {}),
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

document.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-test-ai]");
  if (btn) {
    e.preventDefault();
    btn.disabled = true;
    const out = document.querySelector("[data-ai-result]");
    if (out) out.textContent = "Testing…";
    const r = await postJson(btn.getAttribute("data-test-ai"));
    if (out) out.textContent = JSON.stringify(r.data, null, 2);
    btn.disabled = false;
  }
  const cbtn = e.target.closest("[data-test-cloudinary]");
  if (cbtn) {
    e.preventDefault();
    cbtn.disabled = true;
    const out = document.querySelector("[data-cloudinary-result]");
    if (out) out.textContent = "Testing…";
    const r = await postJson(cbtn.getAttribute("data-test-cloudinary"));
    if (out) out.textContent = JSON.stringify(r.data, null, 2);
    cbtn.disabled = false;
  }
});
