import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'branding/app_name.dart';
import 'branding/brand_assets.dart';
import 'design/theme.dart';
import 'design/theme_controller.dart';
import 'providers.dart';
import 'screens/device_source_screen.dart';
import 'screens/describe_screen.dart';
import 'screens/document_read_screen.dart';
import 'screens/glasses_config_screen.dart';
import 'screens/glasses_pair_screen.dart';
import 'screens/home_screen.dart';
import 'screens/last_attempt_trace_screen.dart';
import 'screens/nearby_objects_screen.dart';
import 'screens/object_search_screen.dart';
import 'screens/personal_object_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/text_vision_screen.dart';
import 'widgets/connectivity_indicator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final setupComplete = prefs.getBool('setupComplete') ?? false;
  final deviceSource = prefs.getString('deviceSource');
  final glassesPaired = prefs.getBool('glassesPaired') ?? false;
  runApp(
    ProviderScope(
      child: OrienteApp(
        setupComplete: setupComplete,
        savedDeviceSource: deviceSource,
        glassesPaired: glassesPaired,
      ),
    ),
  );
}

Future<void> _precacheBrand(BuildContext context) async {
  for (final path in BrandAssets.all) {
    try {
      await precacheImage(AssetImage(path), context);
    } catch (_) {
      // Missing asset: leave slot empty without crashing.
    }
  }
}

enum _BootPhase {
  pickDevice,
  pairGlasses,
  configureGlasses,
  setup,
  ready,
}

class OrienteApp extends ConsumerStatefulWidget {
  const OrienteApp({
    super.key,
    required this.setupComplete,
    required this.savedDeviceSource,
    required this.glassesPaired,
  });

  final bool setupComplete;
  final String? savedDeviceSource;
  final bool glassesPaired;

  @override
  ConsumerState<OrienteApp> createState() => _OrienteAppState();
}

class _OrienteAppState extends ConsumerState<OrienteApp>
    with WidgetsBindingObserver {
  late _BootPhase _phase;
  late bool _setupComplete;
  late bool _glassesPaired;
  bool _brandCached = false;

  static const _inject = MethodChannel('oriente/inject');
  String? _pendingInjectCmd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inject.setMethodCallHandler((call) async {
      if (call.method == 'onInject') {
        final cmd = call.arguments?.toString();
        if (cmd != null && cmd.trim().isNotEmpty) {
          _pendingInjectCmd = cmd.trim();
          await _drainInject();
        }
      } else if (call.method == 'volumeStop') {
        // Hardware volume-down stop during tasks (Vosk fallback).
        await ref.read(appControllerProvider.notifier).cancel();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollInject());
    _setupComplete = widget.setupComplete;
    _glassesPaired = widget.glassesPaired;
    if (widget.savedDeviceSource == null) {
      _phase = _BootPhase.pickDevice;
    } else if (widget.savedDeviceSource == 'glasses' && !_glassesPaired) {
      _phase = _BootPhase.pairGlasses;
    } else if (!_setupComplete) {
      _phase = _BootPhase.setup;
    } else {
      _phase = _BootPhase.ready;
    }
  }

  Future<void> _onDeviceChosen(DeviceSourceChoice choice) async {
    if (choice == DeviceSourceChoice.glasses) {
      setState(() => _phase = _BootPhase.pairGlasses);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('glassesPaired', false);
    setState(() {
      _glassesPaired = false;
      _phase = _setupComplete ? _BootPhase.ready : _BootPhase.setup;
    });
    unawaited(_drainInject());
  }

  Future<void> _onGlassesPaired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('glassesPaired', true);
    setState(() {
      _glassesPaired = true;
      _phase = _BootPhase.configureGlasses;
    });
  }

  void _onGlassesConfigured() {
    setState(() {
      _phase = _setupComplete ? _BootPhase.ready : _BootPhase.setup;
    });
    unawaited(_drainInject());
  }

  void _onSetupComplete() {
    setState(() {
      _setupComplete = true;
      _phase = _BootPhase.ready;
    });
    unawaited(_drainInject());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _pollInject() async {
    try {
      final cmd = await _inject.invokeMethod<String>('takeInjectCommand');
      if (cmd != null && cmd.trim().isNotEmpty) {
        _pendingInjectCmd = cmd.trim();
      }
    } catch (_) {}
    await _drainInject();
  }

  Future<void> _drainInject() async {
    final cmd = _pendingInjectCmd;
    if (cmd == null || cmd.isEmpty) return;
    if (_phase != _BootPhase.ready) return;
    _pendingInjectCmd = null;
    ref.read(showAttemptTraceProvider.notifier).state = false;
    await ref.read(appControllerProvider.notifier).injectVoiceCommand(cmd);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do NOT cancel on `inactive` — Android fires it during ASR / overlays and
    // was killing Tap-and-speak mid-session. Only background / lock / detach.
    if (state == AppLifecycleState.resumed) {
      unawaited(_pollInject());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(activityScopeProvider).stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiPhase = ref.watch(appControllerProvider.select((s) => s.phase));
    final forcePicker = ref.watch(forceDevicePickerProvider);
    final veMode = ref.watch(veThemeModeProvider);
    if (forcePicker && _phase == _BootPhase.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(forceDevicePickerProvider.notifier).state = false;
        setState(() => _phase = _BootPhase.pickDevice);
      });
    }

    Widget home;
    switch (_phase) {
      case _BootPhase.pickDevice:
        home = DeviceSourceScreen(onChosen: _onDeviceChosen);
      case _BootPhase.pairGlasses:
        home = GlassesPairScreen(
          onPaired: _onGlassesPaired,
          onBack: () {
            unawaited(ref.read(activityScopeProvider).stop());
            setState(() => _phase = _BootPhase.pickDevice);
          },
        );
      case _BootPhase.configureGlasses:
        home = GlassesConfigScreen(onDone: _onGlassesConfigured);
      case _BootPhase.setup:
        home = SetupScreen(onComplete: _onSetupComplete);
      case _BootPhase.ready:
        if (ref.watch(showAttemptTraceProvider)) {
          home = const LastAttemptTraceScreen();
        } else if (uiPhase == UiPhase.settings) {
          home = const SettingsScreen();
        } else if (uiPhase == UiPhase.objectSearch) {
          final q = ref.watch(
                appControllerProvider.select((s) => s.activeQuery),
              ) ??
              'object';
          home = ObjectSearchScreen(query: q);
        } else if (uiPhase == UiPhase.textSearch) {
          final s = ref.watch(appControllerProvider);
          final q = s.activeQuery ?? '';
          home = TextVisionScreen(
            mode: s.hybridFind ? TextVisionMode.hybrid : TextVisionMode.search,
            query: q,
            objectQuery: s.secondaryQuery,
          );
        } else if (uiPhase == UiPhase.nearbyText) {
          home = const TextVisionScreen(mode: TextVisionMode.nearby);
        } else if (uiPhase == UiPhase.documentRead) {
          home = const DocumentReadScreen();
        } else if (uiPhase == UiPhase.nearbyObjects) {
          home = const NearbyObjectsScreen();
        } else if (uiPhase == UiPhase.personalRemember) {
          final n = ref.watch(
            appControllerProvider.select((s) => s.activeQuery),
          );
          home = PersonalObjectScreen(suggestedName: n);
        } else if (uiPhase == UiPhase.describe) {
          final s = ref.watch(appControllerProvider);
          home = DescribeScreen(
            continuous: s.describeContinuous,
            fromMemory: s.describeFromMemory,
            onlineDetail: s.describeOnlineDetail,
          );
        } else {
          home = const HomeScreen();
        }
    }

    final showCornerPill = _phase == _BootPhase.ready &&
        (uiPhase == UiPhase.home || uiPhase == UiPhase.listening);

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: OrienteTheme.lightTheme(),
      darkTheme: OrienteTheme.dark(),
      highContrastTheme: OrienteTheme.highContrast(),
      highContrastDarkTheme: OrienteTheme.highContrast(),
      themeMode: switch (veMode) {
        VeThemeMode.system => ThemeMode.system,
        VeThemeMode.dark => ThemeMode.dark,
        VeThemeMode.light => ThemeMode.light,
        VeThemeMode.highContrast => ThemeMode.dark,
      },
      builder: (context, child) {
        if (!_brandCached) {
          _brandCached = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _precacheBrand(context);
          });
        }
        final platform = MediaQuery.platformBrightnessOf(context);
        if (veMode == VeThemeMode.highContrast) {
          return Theme(
            data: OrienteTheme.highContrast(),
            child: child ?? const SizedBox.shrink(),
          );
        }
        if (veMode == VeThemeMode.system) {
          return Theme(
            data: resolveVeTheme(veMode, platform),
            child: child ?? const SizedBox.shrink(),
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: Stack(
        children: [
          home,
          if (showCornerPill)
            const Positioned(
              top: 12,
              left: 12,
              child: SafeArea(child: ConnectivityIndicator()),
            ),
        ],
      ),
    );
  }
}
