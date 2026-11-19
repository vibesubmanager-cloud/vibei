import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'components.dart';

/// Presentation shell for active camera / task screens.
class CameraTaskScaffold extends StatelessWidget {
  const CameraTaskScaffold({
    super.key,
    required this.title,
    required this.status,
    required this.onStop,
    required this.preview,
    this.connectivity,
    this.reticleProgress = 0.4,
    this.targetFound = false,
    this.showReticle = true,
    this.stopLabel = 'Stop',
    this.stopHint = 'Stop the current task and return home',
  });

  final String title;
  final String status;
  final VoidCallback onStop;
  final Widget preview;
  final Widget? connectivity;
  final double reticleProgress;
  final bool targetFound;
  final bool showReticle;
  final String stopLabel;
  final String stopHint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Keep preview in its own paint boundary so UI animations do not
          // rebuild the camera platform view.
          Positioned.fill(
            child: RepaintBoundary(child: preview),
          ),
          // Top / bottom scrims
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC0B1020), Color(0x000B1020)],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE60B1020), Color(0x000B1020)],
                ),
              ),
            ),
          ),
          if (showReticle)
            Positioned.fill(
              child: TargetReticle(
                progress: reticleProgress,
                found: targetFound,
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StatusPill(
                              label: title,
                              tone: StatusPillTone.accent,
                            ),
                          ),
                        ),
                      ),
                      ?connectivity,
                    ],
                  ),
                  const Spacer(),
                  CaptionPanel(text: status),
                  const SizedBox(height: VeTokens.space),
                  PillButton(
                    label: stopLabel,
                    danger: true,
                    onPressed: onStop,
                    semanticHint: stopHint,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calm full-screen state when no camera preview is shown.
class OrbStatusScaffold extends StatelessWidget {
  const OrbStatusScaffold({
    super.key,
    required this.title,
    required this.status,
    required this.onStop,
    this.stopLabel = 'Stop',
  });

  final String title;
  final String status;
  final VoidCallback onStop;
  final String stopLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      background: const GlowBackground(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          const Spacer(),
          const Center(child: ViveiLogo(height: 72, showWordmark: false)),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const Spacer(),
          PillButton(label: stopLabel, danger: true, onPressed: onStop),
        ],
      ),
    );
  }
}
