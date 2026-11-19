import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../branding/app_name.dart';
import '../design/tokens.dart';
import '../providers.dart';
import '../widgets/design/components.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _glassesSource = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _glassesSource = p.getString('deviceSource') == 'glasses');
    });
  }

  void _onBigTap() {
    ref.read(appControllerProvider.notifier).onBigButton();
  }

  void _onCancel() {
    ref.read(appControllerProvider.notifier).cancel();
  }

  void _onSettings() {
    ref.read(appControllerProvider.notifier).openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final listening = ref.watch(
      appControllerProvider.select((s) => s.phase == UiPhase.listening),
    );
    final partial = ref.watch(
      appControllerProvider.select((s) => s.partialTranscript),
    );
    final statusLine = ref.watch(
      appControllerProvider.select((s) => s.statusLine),
    );
    final theme = Theme.of(context);
    final statusText = listening ? 'Listening…' : 'Ready';

    return ScreenScaffold(
      background: const GlowBackground(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: VeTokens.targetSecondary,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const ViveiLogo(height: 44, showWordmark: false),
                          Positioned(
                            right: 0,
                            child: Semantics(
                              button: true,
                              label: 'Settings',
                              hint:
                                  'Open settings for speech rate, privacy, theme, and models',
                              child: IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: VeTokens.targetSecondary,
                                  minHeight: VeTokens.targetSecondary,
                                ),
                                iconSize: 28,
                                onPressed: _onSettings,
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CameraSourceBadge(
                            isGlasses: _glassesSource,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              statusText,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (partial.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Heard: $partial',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Center(
                      child: RepaintBoundary(
                        child: BigTapButton(
                          key: const ValueKey('big_tap_button'),
                          listening: listening,
                          onTap: _onBigTap,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      label: statusLine,
                      child: const SizedBox.shrink(),
                    ),
                    PillButton(
                      label: 'Cancel',
                      outlined: true,
                      onPressed: _onCancel,
                      semanticHint: 'Stop the current action and return home',
                    ),
                    Semantics(
                      label: kAppName,
                      excludeSemantics: true,
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
