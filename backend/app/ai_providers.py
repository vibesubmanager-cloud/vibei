"""Real AI provider adapters. Keys come from encrypted settings only."""

from __future__ import annotations

import json

import httpx

from .settings_store import get_int, get_setting


class ProviderError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _timeout() -> float:
    return float(get_int("provider_timeout_sec", 25))


def test_connection() -> dict:
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key:
        raise ProviderError("not_configured", "AI API key is not set")
    if not model:
        raise ProviderError("not_configured", "AI model ID is not set")
    if provider in ("google", "gemini"):
        model = normalize_gemini_model(model)
    prompt = "Reply with exactly: ok"
    try:
        text = _chat(provider, key, model, prompt, image_b64=None)
    except httpx.TimeoutException as e:
        raise ProviderError(
            "timeout",
            "Gemini timed out — model may be overloaded. Try again or switch model.",
        ) from e
    return {"ok": True, "provider": provider, "model": model, "reply": text[:200]}


def describe_image(
    image_b64: str,
    scene_context: str,
    language: str,
    previous_description: str = "",
    view_changed: bool = False,
) -> str:
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key or not model:
        raise ProviderError("not_configured", "Online features are not set up")
    prompt = get_setting("prompt_describe")
    if previous_description:
        prompt += f"\nPrevious description (do not repeat): {previous_description}"
    if view_changed:
        prompt += "\nThe camera view has changed. Describe the new view fully."
    if scene_context:
        prompt += f"\nScene context: {scene_context}"
    if language:
        prompt += f"\nRespond in language: {language}"
    return _chat(provider, key, model, prompt, image_b64=image_b64)


def describe_image_stream(
    image_b64: str,
    scene_context: str,
    language: str,
    previous_description: str = "",
    view_changed: bool = False,
):
    """Yield text deltas from provider streaming APIs (OpenAI first)."""
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key or not model:
        raise ProviderError("not_configured", "Online features are not set up")
    prompt = get_setting("prompt_describe")
    if previous_description:
        prompt += f"\nPrevious description (do not repeat): {previous_description}"
    if view_changed:
        prompt += "\nThe camera view has changed. Describe the new view fully."
    if scene_context:
        prompt += f"\nScene context: {scene_context}"
    if language:
        prompt += f"\nRespond in language: {language}"
    if provider in ("openai", "openai_compatible"):
        yield from _openai_stream(key, model, prompt, image_b64)
        return
    # Non-streaming providers: yield whole answer once.
    yield describe_image(
        image_b64,
        scene_context,
        language,
        previous_description=previous_description,
        view_changed=view_changed,
    )


def _openai_stream(key: str, model: str, prompt: str, image_b64: str | None):
    content: list | str
    if image_b64:
        content = [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
            },
        ]
    else:
        content = prompt
    body = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 800,
        "stream": True,
    }
    with httpx.Client(timeout=_timeout()) as client:
        with client.stream(
            "POST",
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json=body,
        ) as r:
            if r.status_code >= 400:
                raise ProviderError("provider_error", f"OpenAI HTTP {r.status_code}")
            for line in r.iter_lines():
                if not line:
                    continue
                if line.startswith("data: "):
                    payload = line[6:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        data = json.loads(payload)
                        delta = (
                            data.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content")
                            or ""
                        )
                        if delta:
                            yield delta
                    except Exception:
                        continue


def read_image(image_b64: str, language: str) -> str:
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key or not model:
        raise ProviderError("not_configured", "Online features are not set up")
    prompt = get_setting("prompt_read")
    if language:
        prompt += f"\nLanguage: {language}"
    return _chat(provider, key, model, prompt, image_b64=image_b64)


def locate_target(image_b64: str, target: str, language: str = "en") -> dict:
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key or not model:
        raise ProviderError("not_configured", "Online features are not set up")
    prompt = get_setting("prompt_locate")
    prompt += f"\nTarget to locate: {target}"
    if language:
        prompt += f"\nLanguage for description: {language}"
    raw = _chat(provider, key, model, prompt, image_b64=image_b64)
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.startswith("json"):
            raw = raw[4:]
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise ProviderError("provider_error", f"Invalid JSON from model: {e}") from e
    allowed = {
        "top-left",
        "top-center",
        "top-right",
        "middle-left",
        "center",
        "middle-right",
        "bottom-left",
        "bottom-center",
        "bottom-right",
    }
    matches_out = []
    for m in data.get("matches") or []:
        if not isinstance(m, dict):
            continue
        grid = str(m.get("grid") or "").lower().strip()
        if grid not in allowed:
            continue
        conf = m.get("confidence", 0.5)
        try:
            conf_f = float(conf)
        except (TypeError, ValueError):
            conf_f = 0.5
        matches_out.append(
            {
                "grid": grid,
                "description": str(m.get("description") or "")[:200],
                "confidence": max(0.0, min(1.0, conf_f)),
            }
        )
    found = bool(data.get("found")) and len(matches_out) > 0
    return {"found": found, "matches": matches_out}


def understand_voice(transcript: str, context: dict) -> dict:
    provider = get_setting("ai_provider", "openai").lower()
    key = get_setting("ai_api_key", "")
    model = get_setting("ai_model", "")
    if not key or not model:
        raise ProviderError("not_configured", "Online features are not set up")
    prompt = get_setting("prompt_voice")
    prompt += f"\nUtterance: {transcript}\nContext: {json.dumps(context)}\nReturn JSON only."
    raw = _chat(provider, key, model, prompt, image_b64=None)
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.startswith("json"):
            raw = raw[4:]
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise ProviderError("provider_error", f"Invalid JSON from model: {e}") from e
    return {
        "intent": data.get("intent", "clarify"),
        "params": data.get("params") or {},
        "reply": data.get("reply") or "",
    }


def _chat(provider: str, key: str, model: str, prompt: str, image_b64: str | None) -> str:
    if provider in ("openai", "openai_compatible"):
        return _openai(key, model, prompt, image_b64)
    if provider in ("anthropic", "claude"):
        return _anthropic(key, model, prompt, image_b64)
    if provider in ("google", "gemini"):
        return _gemini(key, model, prompt, image_b64)
    raise ProviderError("not_configured", f"Unknown provider: {provider}")


def _openai(key: str, model: str, prompt: str, image_b64: str | None) -> str:
    content: list | str
    if image_b64:
        content = [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
            },
        ]
    else:
        content = prompt
    body = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 800,
    }
    with httpx.Client(timeout=_timeout()) as client:
        r = client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json=body,
        )
    if r.status_code >= 400:
        raise ProviderError("provider_error", f"OpenAI HTTP {r.status_code}")
    data = r.json()
    return data["choices"][0]["message"]["content"].strip()


def _anthropic(key: str, model: str, prompt: str, image_b64: str | None) -> str:
    content = []
    if image_b64:
        content.append(
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": image_b64,
                },
            }
        )
    content.append({"type": "text", "text": prompt})
    body = {
        "model": model,
        "max_tokens": 800,
        "messages": [{"role": "user", "content": content}],
    }
    with httpx.Client(timeout=_timeout()) as client:
        r = client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json=body,
        )
    if r.status_code >= 400:
        raise ProviderError("provider_error", f"Anthropic HTTP {r.status_code}")
    data = r.json()
    parts = data.get("content") or []
    texts = [p.get("text", "") for p in parts if p.get("type") == "text"]
    return "\n".join(texts).strip()


# Shut-down / renamed Gemini IDs → current multimodal Flash.
_GEMINI_MODEL_ALIASES = {
    "gemini-2.0-flash": "gemini-3.8-flash",
    "gemini-2.0-flash-001": "gemini-3.8-flash",
    "gemini-2.0-flash-exp": "gemini-3.8-flash",
    "gemini-2.0-flash-lite": "gemini-3.5-flash-lite",
    "gemini-2.0-flash-lite-001": "gemini-3.5-flash-lite",
    "gemini-1.5-flash": "gemini-3.8-flash",
    "gemini-1.5-flash-latest": "gemini-3.8-flash",
    "gemini-1.5-pro": "gemini-3.8-flash",
    "gemini-pro": "gemini-3.8-flash",
    "gemini-pro-vision": "gemini-3.8-flash",
}

# Tried in order when the primary model returns 429/503 (capacity).
_GEMINI_FALLBACKS = (
    "gemini-3.8-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash-lite",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
)


def normalize_gemini_model(model: str) -> str:
    name = (model or "").strip()
    if name.startswith("models/"):
        name = name[len("models/") :]
    if not name:
        return "gemini-3.8-flash"
    return _GEMINI_MODEL_ALIASES.get(name, name)


def _gemini_error_message(status: int, body: str) -> str:
    try:
        data = json.loads(body) if body else {}
        msg = (data.get("error") or {}).get("message") or body
    except Exception:
        msg = body or ""
    msg = (msg or "").strip()
    if len(msg) > 280:
        msg = msg[:277] + "…"
    return f"Gemini HTTP {status}" + (f": {msg}" if msg else "")


def _gemini_models_to_try(primary: str) -> list[str]:
    primary = normalize_gemini_model(primary)
    out: list[str] = []
    for name in (primary, *_GEMINI_FALLBACKS):
        if name and name not in out:
            out.append(name)
    return out


def _gemini_extract_text(data: dict) -> str:
    cands = data.get("candidates") or []
    if not cands:
        feedback = data.get("promptFeedback") or {}
        reason = feedback.get("blockReason") or feedback.get("block_reason")
        if reason:
            raise ProviderError("provider_error", f"Gemini blocked the prompt ({reason})")
        raise ProviderError("provider_error", "Empty Gemini response")
    parts_out = cands[0].get("content", {}).get("parts") or []
    text = "\n".join(p.get("text", "") for p in parts_out).strip()
    if not text:
        raise ProviderError("provider_error", "Empty Gemini response")
    return text


def _gemini(key: str, model: str, prompt: str, image_b64: str | None) -> str:
    parts = [{"text": prompt}]
    if image_b64:
        raw_b64 = image_b64
        mime = "image/jpeg"
        if raw_b64.strip().startswith("data:") and "," in raw_b64:
            header, raw_b64 = raw_b64.split(",", 1)
            if "image/" in header:
                mime = header.split(";")[0].split(":", 1)[1].strip() or mime
        parts.append({"inline_data": {"mime_type": mime, "data": raw_b64}})
    body = {"contents": [{"parts": parts}]}
    last_err: ProviderError | None = None
    timeout = min(_timeout(), 20.0)

    with httpx.Client(timeout=timeout) as client:
        for attempt_model in _gemini_models_to_try(model):
            url = (
                "https://generativelanguage.googleapis.com/v1beta/models/"
                f"{attempt_model}:generateContent?key={key}"
            )
            try:
                r = client.post(url, json=body)
            except httpx.TimeoutException:
                last_err = ProviderError(
                    "timeout",
                    f"Gemini timed out on {attempt_model}. Try again shortly.",
                )
                continue
            except httpx.HTTPError as exc:
                last_err = ProviderError("provider_error", f"Gemini network error: {exc}")
                continue

            if r.status_code in (429, 503):
                last_err = ProviderError(
                    "provider_error",
                    _gemini_error_message(r.status_code, r.text),
                )
                continue
            if r.status_code >= 400:
                raise ProviderError(
                    "provider_error",
                    _gemini_error_message(r.status_code, r.text),
                )
            try:
                data = r.json()
            except Exception as e:
                raise ProviderError("provider_error", f"Invalid Gemini JSON: {e}") from e
            return _gemini_extract_text(data)

    if last_err:
        raise last_err
    raise ProviderError("provider_error", "Gemini request failed")
