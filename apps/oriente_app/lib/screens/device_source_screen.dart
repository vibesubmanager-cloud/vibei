import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../branding/app_name.dart';
import '../design/tokens.dart';
import '../providers.dart';
import '../widgets/design/components.dart';

enum DeviceSourceChoice { phone, glasses }

/// First screen: choose phone camera or smart glasses.
class DeviceSourceScreen extends ConsumerStatefulWidget {
  const DeviceSourceScreen({super.key, required this.onChosen});

  final ValueChanged<DeviceSourceChoice> onChosen;

  @override
  ConsumerState<DeviceSourceScreen> createState() => _DeviceSourceScreenState();
}

class _DeviceSourceScreenState extends ConsumerState<DeviceSourceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _select;
  DeviceSourceChoice? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: VeTokens.durMed);
    _select = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final reduce = MediaQuery.of(context).disableAnimations;
      if (reduce) {
        _enter.value = 1;
      } else {
        await _enter.forward();
      }
      await ref.read(orienteHostProvider).speak(
            'Welcome to $kAppName. Choose your camera. '
            'Double tap Use phone, or double tap Use smart glasses.',
          );
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _select.dispose();
    super.dispose();
  }

  Future<void> _pick(DeviceSourceChoice choice) async {
    if (_busy) return;
    _busy = true;
    setState(() => _selected = choice);
    final reduce = MediaQuery.of(context).disableAnimations;
    if (!reduce) {
      await _select.forward();
    }
    final host = ref.read(orienteHostProvider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'deviceSource',
      choice == DeviceSourceChoice.glasses ? 'glasses' : 'phone',
    );
    await host.setCameraSource(
      choice == DeviceSourceChoice.glasses ? 'glasses' : 'phone',
    );
    if (choice == DeviceSourceChoice.phone) {
      await host.speak('Phone camera selected.', interrupt: true);
    } else {
      await host.speak(
        'Smart glasses selected. Next, pair your glasses.',
        interrupt: true,
      );
    }
    widget.onChosen(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.of(context).disableAnimations;
    final selectT = Curves.easeOutCubic.transform(_select.value);

    Widget fadeRise(Widget child, {required double delay}) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: _enter,
        curve: Interval(delay, 1, curve: VeTokens.curveIn),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    }

    final phoneSelected = _selected == DeviceSourceChoice.phone;
    final glassesSelected = _selected == DeviceSourceChoice.glasses;

    return ScreenScaffold(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      background: const GlowBackground(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fadeRise(
            const Center(child: ViveiLogo(height: 52)),
            delay: 0,
          ),
          const SizedBox(height: 12),
          fadeRise(
            Semantics(
              header: true,
              child: Text(
                'Welcome to $kAppName',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
              ),
            ),
            delay: 0.08,
          ),
          const SizedBox(height: 4),
          fadeRise(
            Text(
              'Choose your camera.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 16,
              ),
            ),
            delay: 0.12,
          ),
          const Spacer(flex: 1),
          fadeRise(
            AnimatedBuilder(
              animation: _select,
              builder: (context, _) {
                return ChoiceCard(
                  title: 'Use phone',
                  description:
                      "Use your phone's camera and microphone to search for objects.",
                  heroKind: HeroImageKind.phone,
                  emphasized: true,
                  compact: true,
                  fadeOut: glassesSelected,
                  selectScale: phoneSelected ? 1 + 0.06 * selectT : 1,
                  onTap: () => _pick(DeviceSourceChoice.phone),
                );
              },
            ),
            delay: 0.18,
          ),
          const SizedBox(height: 10),
          fadeRise(
            AnimatedBuilder(
              animation: _select,
              builder: (context, _) {
                return ChoiceCard(
                  title: 'Use smart glasses',
                  description:
                      'Pair your glasses over Bluetooth, then stream their camera over Wi-Fi.',
                  heroKind: HeroImageKind.glasses,
                  compact: true,
                  fadeOut: phoneSelected,
                  selectScale: glassesSelected ? 1 + 0.06 * selectT : 1,
                  onTap: () => _pick(DeviceSourceChoice.glasses),
                );
              },
            ),
            delay: 0.28,
          ),
          const Spacer(flex: 1),
          Text(
            'You can change this later in Settings.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
