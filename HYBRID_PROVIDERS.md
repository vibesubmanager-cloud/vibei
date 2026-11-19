# Hybrid online providers

1. **Cloud vision** — `BackendCloudVisionProvider` in `packages/oriente_platform`, wired from `apps/oriente_app/lib/providers.dart`. Calls Flask `/api/v1/vision/*` only (no API keys in the app).
2. **Voice** — `BackendVoiceUnderstandingProvider` calls `/api/v1/voice/understand` and maps intent JSON to phrases the offline `IntentParser` understands.
3. **Base URL** — build with `--dart-define=VIBEI_API_BASE=https://YOUR-SERVICE`. Empty base → online status "not configured"; offline features unchanged.
4. **Failures** — not configured, quota, timeout, no internet, server error all return null / fall back offline. No spoken "no internet"; online-detail may say "Online features are not set up" when honestly not configured.
