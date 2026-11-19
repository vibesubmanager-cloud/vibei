import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../branding/app_name.dart';
import '../../branding/brand_assets.dart';
import '../../design/tokens.dart';

/// Real company logo (replaces drawn mark). Decorative tap is not focusable.
class ViveiLogo extends StatefulWidget {
  const ViveiLogo({
    super.key,
    this.height = 56,
    this.showWordmark = true,
    this.monochrome = false,
    this.semanticAsHeader = true,
  });

  final double height;
  final bool showWordmark;
  final bool monochrome;
  final bool semanticAsHeader;

  @override
  State<ViveiLogo> createState() => _ViveiLogoState();
}

typedef VeveLogo = ViveiLogo;

class _ViveiLogoState extends State<ViveiLogo> with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _pulse;
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: VeTokens.durMed);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final reduce = MediaQuery.of(context).disableAnimations;
      if (reduce) {
        _enter.value = 1;
        return;
      }
      await _enter.forward();
      if (!mounted) return;
      await _pulse.forward();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return;
    _bounce
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final imgH = widget.height;
    final cacheH = (imgH * dpr).round().clamp(64, 1024);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hc = theme.scaffoldBackgroundColor == Colors.black &&
        theme.colorScheme.primary == VeTokens.accentHc;

    final logo = AnimatedBuilder(
      animation: Listenable.merge([_enter, _pulse, _bounce]),
      builder: (context, child) {
        final enterT = Curves.easeOutCubic.transform(_enter.value);
        final pulse =
            1 + 0.06 * math.sin(_pulse.value * math.pi); // one soft pulse
        final bounce = 1 + 0.08 * math.sin(_bounce.value * math.pi);
        return Opacity(
          opacity: enterT,
          child: Transform.scale(
            scale: (0.92 + 0.08 * enterT) * pulse * bounce,
            child: child,
          ),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isDark || hc)
            Container(
              width: imgH * 1.15,
              height: imgH * 1.15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    VeTokens.accentEnd.withValues(alpha: hc ? 0.35 : 0.28),
                    VeTokens.accentStart.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          Image.asset(
            BrandAssets.logo,
            height: imgH,
            cacheHeight: cacheH,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative tap — excluded from TalkBack focus as a button.
        ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            child: logo,
          ),
        ),
        if (widget.showWordmark) ...[
          SizedBox(width: widget.height * 0.14),
          Text(
            kAppName,
            style: TextStyle(
              fontFamily: VeTokens.fontFamily,
              fontSize: widget.height * 0.38,
              fontWeight: FontWeight.w700,
              letterSpacing: widget.height * 0.06,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );

    if (!widget.semanticAsHeader) {
      return content;
    }
    return Semantics(
      label: '$kAppName logo',
      image: true,
      header: true,
      excludeSemantics: true,
      child: content,
    );
  }
}

enum HeroImageKind { phone, glasses }

/// Floating choice hero with glow, idle drift, and kind-specific sweeps.
class FloatingHeroImage extends StatefulWidget {
  const FloatingHeroImage({
    super.key,
    required this.kind,
    required this.size,
    this.pressProgress = 0,
    this.reducedMotion = false,
  });

  final HeroImageKind kind;
  final double size;
  final double pressProgress;
  final bool reducedMotion;

  String get asset =>
      kind == HeroImageKind.phone ? BrandAssets.phone : BrandAssets.glasses;

  @override
  State<FloatingHeroImage> createState() => _FloatingHeroImageState();
}

class _FloatingHeroImageState extends State<FloatingHeroImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    if (!widget.reducedMotion) {
      _idle.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant FloatingHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion && _idle.isAnimating) {
      _idle.stop();
      _idle.value = 0.5;
    } else if (!widget.reducedMotion && !_idle.isAnimating) {
      _idle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = (widget.size * dpr).round().clamp(96, 1200);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final needDisc = isDark ||
        (theme.scaffoldBackgroundColor == const Color(0xFF000000));

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, child) {
          final t = widget.reducedMotion ? 0.5 : _idle.value;
          final dy = widget.reducedMotion ? 0.0 : (t - 0.5) * 10; // ±5 dp
          final breath = 0.85 + 0.15 * (widget.reducedMotion ? 0.5 : t);
          final tilt = widget.reducedMotion
              ? 0.0
              : (widget.kind == HeroImageKind.glasses
                      ? (t - 0.5) * 0.04
                      : 0.0) +
                  widget.pressProgress * -0.06;
          final scale = 1 - widget.pressProgress * 0.04;

          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: tilt,
              child: Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: widget.size * 1.2,
                      height: widget.size * 1.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            VeTokens.accentStart
                                .withValues(alpha: 0.22 * breath),
                            VeTokens.accentEnd
                                .withValues(alpha: 0.12 * breath),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: VeTokens.accentStart
                                .withValues(alpha: 0.18 * breath),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    if (needDisc)
                      Container(
                        width: widget.size * 0.92,
                        height: widget.size * 0.92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: _HeroVisual(
          kind: widget.kind,
          asset: widget.asset,
          size: widget.size,
          cache: cache,
          reducedMotion: widget.reducedMotion,
          idle: _idle,
        ),
      ),
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({
    required this.kind,
    required this.asset,
    required this.size,
    required this.cache,
    required this.reducedMotion,
    required this.idle,
  });

  final HeroImageKind kind;
  final String asset;
  final double size;
  final int cache;
  final bool reducedMotion;
  final AnimationController idle;

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: cache,
      cacheHeight: cache,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

    if (reducedMotion) return img;

    if (kind == HeroImageKind.phone) {
      return AnimatedBuilder(
        animation: idle,
        builder: (context, child) {
          // Soft scan every ~5s via idle phase (one sweep per half cycle).
          final phase = idle.value;
          final showSweep = phase > 0.15 && phase < 0.55;
          final y = ((phase - 0.15) / 0.4).clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (showSweep)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment(0, -0.85 + y * 1.6),
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.symmetric(horizontal: size * 0.18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            VeTokens.accentEnd.withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: VeTokens.accentEnd.withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: img,
      );
    }

    // Glasses: gradient glint masked by image alpha via ShaderMask.
    return AnimatedBuilder(
      animation: idle,
      builder: (context, child) {
        final phase = idle.value;
        final show = phase > 0.2 && phase < 0.65;
        final x = ((phase - 0.2) / 0.45).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (show)
              IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) {
                    return LinearGradient(
                      begin: Alignment(-1.2 + x * 2.4, -0.2),
                      end: Alignment(-0.6 + x * 2.4, 0.2),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.35, 0.5, 0.65],
                    ).createShader(rect);
                  },
                  child: Image.asset(
                    asset,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    cacheWidth: cache,
                    cacheHeight: cache,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        );
      },
      child: img,
    );
  }
}

/// Compact status badge of the chosen camera source.
class CameraSourceBadge extends StatelessWidget {
  const CameraSourceBadge({
    super.key,
    required this.isGlasses,
    this.size = 36,
  });

  final bool isGlasses;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = (size * dpr).round().clamp(48, 256);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isGlasses ? BrandAssets.glasses : BrandAssets.phone;
    return ExcludeSemantics(
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size + 6,
              height: size + 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    VeTokens.accentStart.withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            if (isDark)
              Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            Image.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              cacheWidth: cache,
              cacheHeight: cache,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
