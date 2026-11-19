# VIVEI Design System

Calm, premium, dark-first UI for blind and low-vision users. Presentation only — logic stays unchanged.

## Brand

- Display name: `kAppName` in `lib/branding/app_name.dart` and localized `appTitle`.
- Logo: real asset `assets/images/brand_logo.png` via `ViveiLogo` / `VeveLogo` (drawn CustomPainter removed).
- Choice heroes: `assets/images/option_phone.png`, `assets/images/option_glasses.png`.
- Paths declared in `lib/branding/brand_assets.dart`; precached at startup.
- Android launcher + native splash generated from `brand_logo.png` on `#0B1020`.

## Image usage

| Asset | Where |
| --- | --- |
| `brand_logo.png` | Welcome, Home top, Settings header, splash, launcher |
| `option_phone.png` | “Use phone” ChoiceCard hero; Home status badge when phone |
| `option_glasses.png` | “Use smart glasses” ChoiceCard hero; Home badge when glasses |

Transparent PNGs sit over a soft accent radial glow + shadow (no visible image box). Dark / high-contrast themes add a subtle backing disc when needed (especially black frames).

Card layout: image ~35–45% width beside text; stacks above text on narrow / large text.

## Image animations

| Target | Motion | Reduce-motion |
| --- | --- | --- |
| Logo | Fade + scale-in; one soft glow pulse; decorative tap bounce + light haptic (not TalkBack-focusable) | Fade only |
| Card heroes | Idle float ±5 dp / ~4.5 s; glow breathing | Static + fade |
| Phone | Soft scan line across screen bounds every few seconds | Off |
| Glasses | Gradient glint + slight tilt | Off |
| Press | Card + image scale / tilt + soft haptic | Scale fade only |
| Selection | Chosen card scales up; other fades; ~380 ms easeOutCubic | Fade |

No flashy loops faster than once / 5 s except slow float and glow breath. `RepaintBoundary` around animated images; one idle controller per hero; dispose cleanly. Decode with `cacheWidth` / `cacheHeight` × DPR, `FilterQuality.high`.

## Tokens (`lib/design/tokens.dart`)

| Token | Value |
| --- | --- |
| bgDark | `#0B1020` |
| surfaceDark | `#141B34` |
| surfaceElevatedDark | `#1C2547` |
| textPrimaryDark | `#F5F7FF` (≥7:1 on bg) |
| textSecondaryDark | `#B8C0E0` (≥4.5:1 large) |
| accent | `#7C5CFF` → `#22D3EE` |
| focusRing | `#FFD166` |
| success / danger | `#34D399` / `#FF6B6B` |
| Light bg / text | `#F7F5F1` / `#0B1020` |
| High contrast | black / white / `#FFE600` accents |

Typography: **Atkinson Hyperlegible** (bundled). Scale: display 40, title 32, heading 24, body 18, label 16 (sp). Spacing: 8-pt grid. Radius: cards/buttons 28, pills fully round. Motion: 200–400 ms; easeOutCubic entrances; fades only when reduce-motion.

## Themes (`lib/design/theme.dart` + `theme_controller.dart`)

Settings → Appearance: **System / Dark / Light / High contrast** (persisted).

## Components (`lib/widgets/design/`)

| Component | Role |
| --- | --- |
| `ScreenScaffold` | Safe padded shell + optional glow background |
| `ViveiLogo` / `VeveLogo` | Real brand logo + optional wordmark |
| `FloatingHeroImage` | Phone / glasses hero with glow + motion |
| `CameraSourceBadge` | Small chosen-camera badge on Home |
| `ChoiceCard` | Large selectable card (≥150 dp), optional hero |
| `BigTapButton` | Breathing gradient orb + listening ripples |
| `StatusPill` | Compact status / connectivity |
| `CaptionPanel` | High-contrast live spoken guidance |
| `PillButton` | Primary / outlined / danger ≥64 dp |
| `TargetReticle` | Four-corner camera brackets |
| `GlowBackground` | Slow drifting accent glow |
| `CameraTaskScaffold` | Full-bleed preview + scrims + caption + Stop |

## Accessibility

- TalkBack labels/hints/roles on every control; live regions for Ready / Listening / captions.
- Card heroes and logo tap are decorative (`ExcludeSemantics` / non-button); cards keep button semantics.
- Logo header label: “VIVEI logo” once.
- Touch targets ≥64 dp primary, ≥56 dp secondary.
- Focus rings use `focusRing` / HC yellow; never color-only status.
- Text scales with system size (test at 2.0×).
