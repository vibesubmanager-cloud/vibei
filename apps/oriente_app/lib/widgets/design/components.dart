import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import 'branded_image.dart';

export 'branded_image.dart';

class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.background,
  });

  final Widget child;
  final EdgeInsets padding;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          background ??
              ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          SafeArea(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class ChoiceCard extends StatefulWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
    this.icon = Icons.circle_outlined,
    this.heroKind,
    this.emphasized = false,
    this.fadeOut = false,
    this.selectScale = 1,
    this.compact = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final HeroImageKind? heroKind;
  final VoidCallback onTap;
  final bool emphasized;
  final bool fadeOut;
  final double selectScale;
  /// Smaller padding / hero for screens that must fit without scrolling.
  final bool compact;

  @override
  State<ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<ChoiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: VeTokens.durFast,
      lowerBound: 0,
      upperBound: 1,
      value: 0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elevated = theme.cardColor;
    final on = theme.colorScheme.onSurface;
    final reduce = MediaQuery.of(context).disableAnimations;
    final narrow = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(18) > 28;

    return Semantics(
      button: true,
      label: widget.title,
      hint: '${widget.description}. Double tap to select.',
      child: AnimatedOpacity(
        duration: VeTokens.durMed,
        opacity: widget.fadeOut ? 0 : 1,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, _) {
            final press = reduce ? 0.0 : _press.value;
            final scale = (1 - press * 0.03) * widget.selectScale;
            return Transform.scale(
              scale: scale,
              child: Material(
                color: elevated,
                elevation: widget.emphasized ? 2 : 0,
                borderRadius: BorderRadius.circular(VeTokens.radiusCard),
                child: InkWell(
                  borderRadius: BorderRadius.circular(VeTokens.radiusCard),
                  onTapDown: (_) {
                    _press.forward();
                  },
                  onTapCancel: () => _press.reverse(),
                  onTap: () {
                    _press.reverse();
                    widget.onTap();
                  },
                  focusColor: VeTokens.focusRing.withValues(alpha: 0.25),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: widget.compact ? 104 : 150,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(widget.compact ? 12 : 20),
                      child: narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: _heroOrIcon(on, reduce)),
                                SizedBox(height: widget.compact ? 8 : 14),
                                _textBlock(theme),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ExcludeSemantics(
                                  child: SizedBox(
                                    width: widget.compact ? 88 : 120,
                                    child: _heroOrIcon(on, reduce),
                                  ),
                                ),
                                SizedBox(width: widget.compact ? 12 : 16),
                                Expanded(child: _textBlock(theme)),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _textBlock(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget.title,
          style: widget.compact
              ? theme.textTheme.titleLarge?.copyWith(fontSize: 20)
              : theme.textTheme.titleLarge,
        ),
        SizedBox(height: widget.compact ? 4 : 8),
        Text(
          widget.description,
          style: widget.compact
              ? theme.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.25)
              : theme.textTheme.bodyMedium,
          maxLines: widget.compact ? 3 : null,
          overflow: widget.compact ? TextOverflow.ellipsis : TextOverflow.visible,
        ),
      ],
    );
  }

  Widget _heroOrIcon(Color on, bool reduce) {
    if (widget.heroKind != null) {
      return FloatingHeroImage(
        kind: widget.heroKind!,
        size: widget.compact ? 76 : 108,
        pressProgress: reduce ? 0 : _press.value,
        reducedMotion: reduce,
      );
    }
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.emphasized ? VeTokens.accentGradient : null,
        color: widget.emphasized ? null : on.withValues(alpha: 0.08),
      ),
      child: Icon(
        widget.icon,
        size: 32,
        color: widget.emphasized ? Colors.white : on,
      ),
    );
  }
}

class BigTapButton extends StatefulWidget {
  const BigTapButton({
    super.key,
    required this.listening,
    required this.onTap,
    this.micLevel = 0,
  });

  final bool listening;
  final VoidCallback onTap;
  final double micLevel;

  @override
  State<BigTapButton> createState() => _BigTapButtonState();
}

class _BigTapButtonState extends State<BigTapButton>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _ripple;
  bool _wasListening = false;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didUpdateWidget(covariant BigTapButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_wasListening) {
      _ripple.repeat();
    } else if (!widget.listening && _wasListening) {
      _ripple.stop();
      _ripple.value = 0;
    }
    _wasListening = widget.listening;
  }

  @override
  void dispose() {
    _breath.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final w = MediaQuery.sizeOf(context).width * 0.68;
    final size = w.clamp(220.0, 320.0);

    return Semantics(
      button: true,
      label: widget.listening
          ? 'Listening. Double tap to cancel'
          : 'Tap and speak. Double tap to start listening.',
      hint: 'Say find a bottle, describe, or read this.',
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _ripple]),
          builder: (context, child) {
            return CustomPaint(
              painter: _OrbPainter(
                listening: widget.listening,
                breath: reduce ? 0.5 : _breath.value,
                ripple: reduce ? 0 : _ripple.value,
                mic: widget.micLevel,
                reduceMotion: reduce,
              ),
              child: Center(child: child),
            );
          },
          // Stable child: animation rebuilds paint only; onTap never restarts listen.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              width: size * 0.78,
              height: size * 0.78,
              child: Center(
                child: Text(
                  widget.listening ? 'Listening…' : 'Tap and speak',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.15,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.listening,
    required this.breath,
    required this.ripple,
    required this.mic,
    required this.reduceMotion,
  });

  final bool listening;
  final double breath;
  final double ripple;
  final double mic;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * (0.34 + (reduceMotion ? 0 : breath * 0.012));

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          (listening ? VeTokens.accentEnd : VeTokens.accentStart)
              .withValues(alpha: 0.45),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.55));
    canvas.drawCircle(c, r * 1.45, glow);

    if (listening && !reduceMotion) {
      for (var i = 0; i < 3; i++) {
        final p = (ripple + i / 3) % 1.0;
        final rr = r + p * (28 + mic * 20);
        canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = VeTokens.accentEnd.withValues(alpha: (1 - p) * 0.4),
        );
      }
    } else if (listening && reduceMotion) {
      canvas.drawCircle(
        c,
        r + 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = VeTokens.accentEnd.withValues(alpha: 0.35),
      );
    }

    final orb = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: listening
            ? const [Color(0xFF22D3EE), Color(0xFF34D399)]
            : const [VeTokens.accentStart, VeTokens.accentEnd],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, orb);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.listening != listening ||
      oldDelegate.breath != breath ||
      oldDelegate.ripple != ripple ||
      oldDelegate.mic != mic ||
      oldDelegate.reduceMotion != reduceMotion;
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.online,
    this.tone = StatusPillTone.neutral,
  });

  final String label;
  final bool? online;
  final StatusPillTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    switch (tone) {
      case StatusPillTone.success:
        bg = VeTokens.success.withValues(alpha: 0.2);
        fg = VeTokens.success;
      case StatusPillTone.danger:
        bg = VeTokens.danger.withValues(alpha: 0.2);
        fg = VeTokens.danger;
      case StatusPillTone.accent:
        bg = VeTokens.accentStart.withValues(alpha: 0.2);
        fg = theme.colorScheme.onSurface;
      case StatusPillTone.neutral:
        bg = theme.colorScheme.onSurface.withValues(alpha: 0.08);
        fg = theme.colorScheme.onSurface;
    }
    if (online != null) {
      bg = online!
          ? VeTokens.success.withValues(alpha: 0.22)
          : theme.colorScheme.onSurface.withValues(alpha: 0.1);
      fg = online! ? VeTokens.success : theme.colorScheme.onSurface;
    }

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(VeTokens.radiusPill),
          border: Border.all(color: fg.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (online != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online! ? VeTokens.success : fg.withValues(alpha: 0.5),
                  border: online!
                      ? null
                      : Border.all(color: fg, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusPillTone { neutral, accent, success, danger }

class CaptionPanel extends StatelessWidget {
  const CaptionPanel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(VeTokens.radiusCard),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.outlined = false,
    this.semanticHint,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool outlined;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    VoidCallback? tap;
    if (onPressed != null) {
      tap = () {
        onPressed!();
      };
    }
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      hint: semanticHint,
      child: SizedBox(
        height: VeTokens.targetPrimary,
        width: double.infinity,
        child: outlined
            ? OutlinedButton(onPressed: tap, child: child)
            : FilledButton(
                style: danger
                    ? FilledButton.styleFrom(
                        backgroundColor: VeTokens.danger,
                        foregroundColor: Colors.white,
                      )
                    : null,
                onPressed: tap,
                child: child,
              ),
      ),
    );
  }
}

/// Elegant four-corner reticle for camera task screens.
class TargetReticle extends StatelessWidget {
  const TargetReticle({
    super.key,
    this.progress = 0.35,
    this.found = false,
  });

  final double progress;
  final bool found;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ReticlePainter(progress: progress, found: found),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.progress, required this.found});

  final double progress;
  final bool found;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = 48.0 * (1.15 - progress.clamp(0, 1) * 0.35);
    final len = 28.0 + progress * 8;
    final color = found ? VeTokens.success : Colors.white.withValues(alpha: 0.85);
    final paint = Paint()
      ..color = color
      ..strokeWidth = found ? 4 : 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), paint);
      canvas.drawLine(o, o + Offset(0, dy * len), paint);
    }

    corner(Offset(inset, inset), 1, 1);
    corner(Offset(size.width - inset, inset), -1, 1);
    corner(Offset(inset, size.height - inset), 1, -1);
    corner(Offset(size.width - inset, size.height - inset), -1, -1);

    if (found) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: size.width * 0.28,
            height: size.height * 0.22,
          ),
          const Radius.circular(16),
        ),
        Paint()
          ..color = VeTokens.success.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.found != found;
}

class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key});

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = reduce ? 0.35 : _c.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              gradient: RadialGradient(
                center: Alignment(-0.4 + t * 0.3, -0.6 + t * 0.2),
                radius: 1.15,
                colors: [
                  VeTokens.accentStart.withValues(alpha: 0.28),
                  VeTokens.accentEnd.withValues(alpha: 0.08),
                  bg,
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}
