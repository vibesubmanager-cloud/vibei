import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/activity_scope.dart';
import 'services/attempt_trace.dart';
import 'services/command_log.dart';
import 'services/connectivity_service.dart';
import 'services/gemini_vision_client.dart';
import 'services/speech_queue_service.dart';
import 'services/stop_spotter.dart';

final orienteHostProvider = Provider<OrienteHost>((ref) => OrienteHost());

final activityScopeProvider = Provider<ActivityScope>((ref) {
  return ActivityScope(
    ref.watch(orienteHostProvider),
    ref.watch(speechQueueProvider),
  );
});

final stopSpotterProvider = Provider<StopSpotter>((ref) {
  final s = StopSpotter(ref.watch(orienteHostProvider));
  ref.onDispose(s.dispose);
  return s;
});

final autoFlashlightProvider =
    StateNotifierProvider<_BoolPref, bool>((ref) {
  return _BoolPref('autoFlashlight', true);
});

/// Always-on offline describe engine (no Settings toggle). Kept for callers.
final offlineDescribeFallbackProvider = Provider<bool>((ref) => true);

final geminiVisionClientProvider = Provider<GeminiVisionClient>((ref) {
  return GeminiVisionClient();
});

final lastStopLatencyMsProvider = StateProvider<int?>((ref) => null);

final commandLogProvider =
    StateProvider<CommandLogEntry>((ref) => const CommandLogEntry());

final attemptTraceProvider =
    StateProvider<AttemptTrace>((ref) => AttemptTrace());

/// Extra features (glasses extras, personal remember) off until core is solid.
final coreExtrasEnabledProvider = Provider<bool>((ref) => false);

/// Opens Last attempt trace from Settings.
final showAttemptTraceProvider = StateProvider<bool>((ref) => false);

final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  final client = BackendApiClient();
  unawaited(client.loadSession().then((_) => client.refreshConfig()));
  return client;
});

final remoteConfigProvider =
    StateNotifierProvider<_RemoteConfigNotifier, AppRemoteConfig>((ref) {
  return _RemoteConfigNotifier(ref.watch(backendApiClientProvider));
});

class _RemoteConfigNotifier extends StateNotifier<AppRemoteConfig> {
  _RemoteConfigNotifier(this._client) : super(_client.config) {
    unawaited(refresh());
  }
  final BackendApiClient _client;
  Future<void> refresh() async {
    state = await _client.refreshConfig(force: true);
  }
}

enum OnlineFeatureStatus { available, notConfigured, offline, signedOut }

final onlineFeatureStatusProvider = Provider<OnlineFeatureStatus>((ref) {
  final online = ref.watch(connectivityOnlineProvider);
  final cfg = ref.watch(remoteConfigProvider);
  final client = ref.watch(backendApiClientProvider);
  // Embedded Gemini makes detailed describe/read available without a backend.
  if (GeminiVisionClient.isConfigured) {
    if (!online) return OnlineFeatureStatus.offline;
    return OnlineFeatureStatus.available;
  }
  if (!client.isConfigured || !cfg.aiConfigured) {
    return OnlineFeatureStatus.notConfigured;
  }
  if (!online) return OnlineFeatureStatus.offline;
  if (!client.isSignedIn) return OnlineFeatureStatus.signedOut;
  return OnlineFeatureStatus.available;
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final s = ConnectivityService();
  ref.onDispose(s.dispose);
  return s;
});

final connectivityOnlineProvider =
    StateNotifierProvider<_OnlineFlag, bool>((ref) {
  final n = _OnlineFlag();
  final sub = ref.watch(connectivityServiceProvider).stream.listen(n.set);
  ref.onDispose(sub.cancel);
  n.set(ref.watch(connectivityServiceProvider).isOnline);
  return n;
});

class _OnlineFlag extends StateNotifier<bool> {
  _OnlineFlag() : super(false);
  void set(bool v) => state = v;
}

final speechQueueProvider = Provider<SpeechQueueService>((ref) {
  final s = SpeechQueueService(ref.watch(orienteHostProvider));
  s.onSpeaking = (text) {
    unawaited(ref.read(orienteHostProvider).setSpeakingText(text));
  };
  ref.onDispose(s.dispose);
  return s;
});

final cloudVisionProvider = Provider<CloudVisionProvider>((ref) {
  return BackendCloudVisionProvider(ref.watch(backendApiClientProvider));
});

final voiceUnderstandingProvider = Provider<VoiceUnderstandingProvider>((ref) {
  return BackendVoiceUnderstandingProvider(ref.watch(backendApiClientProvider));
});

final useOnlineEnhancementsProvider =
    StateNotifierProvider<_BoolPref, bool>((ref) {
  return _BoolPref('useOnlineEnhancements', true);
});

final perfOverlayEnabledProvider =
    StateNotifierProvider<_BoolPref, bool>((ref) {
  return _BoolPref('perfOverlay', false);
});

class _BoolPref extends StateNotifier<bool> {
  _BoolPref(this.key, bool def) : super(def) {
    _load(def);
  }
  final String key;
  Future<void> _load(bool def) async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(key) ?? def;
  }

  Future<void> set(bool v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }
}

/// When true, OrienteApp returns to the Phone vs Glasses picker.
final forceDevicePickerProvider = StateProvider<bool>((ref) => false);

final privacySettingsProvider =
    StateNotifierProvider<PrivacySettingsNotifier, PrivacySettings>((ref) {
  return PrivacySettingsNotifier(ref.watch(orienteHostProvider));
});

class PrivacySettingsNotifier extends StateNotifier<PrivacySettings> {
  PrivacySettingsNotifier(this._host) : super(const PrivacySettings()) {
    _load();
  }

  final OrienteHost _host;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PrivacySettings(
      // Default ON so distributed APK can use detailed describe/read immediately.
      onlineVisionConsent: prefs.getBool('onlineVisionConsent') ?? true,
      onlineChatConsent: prefs.getBool('onlineChatConsent') ?? false,
      speechRate: prefs.getDouble('speechRate') ?? 1.0,
      speechVolume: prefs.getDouble('speechVolume') ?? 1.0,
      speechLanguage: prefs.getString('speechLanguage') ?? 'en-US',
    );
    await _host.setPrivacySettings(state);
    await _host.setSpeechRate(state.speechRate);
    await _host.setSpeechVolume(state.speechVolume);
    await _host.setSpeechBiasing(SupportedObjects.biasingPhrases());
    await _host.setAudioFeedbackPrefs(
      tickSound: prefs.getBool('tickSound') ?? true,
      vibration: prefs.getBool('tickVibration') ?? true,
    );
  }

  Future<void> update(PrivacySettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onlineVisionConsent', next.onlineVisionConsent);
    await prefs.setBool('onlineChatConsent', next.onlineChatConsent);
    await prefs.setDouble('speechRate', next.speechRate);
    await prefs.setDouble('speechVolume', next.speechVolume);
    await prefs.setString('speechLanguage', next.speechLanguage);
    await _host.setPrivacySettings(next);
    await _host.setSpeechRate(next.speechRate);
    await _host.setSpeechVolume(next.speechVolume);
    await _host.setSpeechBiasing(SupportedObjects.biasingPhrases());
  }
}

final feedbackPrefsProvider =
    StateNotifierProvider<FeedbackPrefsNotifier, FeedbackPrefs>((ref) {
  return FeedbackPrefsNotifier(ref.watch(orienteHostProvider));
});

class FeedbackPrefs {
  const FeedbackPrefs({this.tickSound = true, this.vibration = true});
  final bool tickSound;
  final bool vibration;

  FeedbackPrefs copyWith({bool? tickSound, bool? vibration}) => FeedbackPrefs(
        tickSound: tickSound ?? this.tickSound,
        vibration: vibration ?? this.vibration,
      );
}

class FeedbackPrefsNotifier extends StateNotifier<FeedbackPrefs> {
  FeedbackPrefsNotifier(this._host) : super(const FeedbackPrefs()) {
    _load();
  }

  final OrienteHost _host;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = FeedbackPrefs(
      tickSound: prefs.getBool('tickSound') ?? true,
      vibration: prefs.getBool('tickVibration') ?? true,
    );
    await _host.setAudioFeedbackPrefs(
      tickSound: state.tickSound,
      vibration: state.vibration,
    );
  }

  Future<void> update(FeedbackPrefs next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tickSound', next.tickSound);
    await prefs.setBool('tickVibration', next.vibration);
    await _host.setAudioFeedbackPrefs(
      tickSound: next.tickSound,
      vibration: next.vibration,
    );
  }
}

final capabilityProvider = FutureProvider<CapabilityReport>((ref) async {
  return ref.watch(orienteHostProvider).getCapabilityReport();
});

enum UiPhase {
  home,
  listening,
  objectSearch,
  textSearch,
  nearbyText,
  nearbyObjects,
  personalRemember,
  documentRead,
  describe,
  settings,
}

class AppController extends StateNotifier<AppUiState> {
  AppController(this._ref) : super(const AppUiState()) {
    _bindStreams();
  }

  final Ref _ref;
  final AppFlowMachine _flow = const AppFlowMachine();
  OrienteHost get _host => _ref.read(orienteHostProvider);

  Timer? _silenceWarn;
  Timer? _silenceEnd;
  Timer? _partialCommit;
  StreamSubscription<AsrEvent>? _asrSub;
  DateTime? _listenGraceUntil;
  bool _handlingCommand = false;
  bool _committedThisListen = false;
  bool _continuationUsed = false;
  String _stablePartialText = '';
  String? _pendingPartialCommit;
  List<String> _lastAlternatives = const [];

  AttemptTrace get _trace => _ref.read(attemptTraceProvider);

  void _publishTrace() {
    _ref.read(attemptTraceProvider.notifier).state = _trace;
  }

  void _logDrop(String reason, String detail) {
    _trace.add('drop', false, '$reason: $detail');
    _publishTrace();
  }

  bool get _acceptHomeCommand {
    if (state.listening || state.phase == UiPhase.listening) return true;
    final g = _listenGraceUntil;
    return g != null && DateTime.now().isBefore(g);
  }

  bool _isActionableCommit(AppIntent intent) {
    return switch (intent) {
      ObjectSearchIntent() => true,
      TextSearchIntent() => true,
      HybridFindIntent() => true,
      DescribeIntent() => true,
      DescribeDetailIntent() => true,
      DocumentReadIntent() => true,
      IdentifyIntent() => true,
      NearbyTextIntent() => true,
      NearbyObjectsIntent() => true,
      OpenSettingsIntent() => true,
      StopIntent() => true,
      StopLookingIntent() => true,
      GoBackIntent() => true,
      _ => false,
    };
  }

  void _schedulePartialCommit(List<String> alternatives) {
    final intent = const IntentParser().parseBest(alternatives);
    // Never commit incomplete intents (missing find target, etc.).
    if (!IntentParser.isComplete(intent) || !_isActionableCommit(intent)) {
      _partialCommit?.cancel();
      _pendingPartialCommit = null;
      _stablePartialText = alternatives.isNotEmpty ? alternatives.first : '';
      return;
    }
    final text = alternatives.isNotEmpty ? alternatives.first : '';
    if (text != _stablePartialText) {
      _stablePartialText = text;
      _pendingPartialCommit = text;
      _partialCommit?.cancel();
      _partialCommit = Timer(const Duration(milliseconds: 600), () async {
        final pending = _pendingPartialCommit;
        if (pending == null || _committedThisListen || _handlingCommand) return;
        if (pending != _stablePartialText) return;
        final again = const IntentParser().parseBest(alternatives);
        if (!IntentParser.isComplete(again) || !_isActionableCommit(again)) {
          return;
        }
        _trace.add('partial_commit', true, pending);
        _publishTrace();
        await _host.stopListening();
        await _handleUtterance(alternatives);
      });
      return;
    }
  }

  void _bindStreams() {
    _asrSub = _host.asrEvents.listen((event) async {
      final alts = event.alternatives.isNotEmpty
          ? event.alternatives
          : (event.text.trim().isEmpty ? <String>[] : [event.text.trim()]);
      final text = (alts.isNotEmpty ? alts.first : event.text).trim();
      _lastAlternatives = alts;
      final t = _trace;
      t.add(
        'kotlin_to_dart',
        text.isNotEmpty || !event.isFinal,
        'final=${event.isFinal} text="$text" alts=$alts',
      );
      if (!event.isFinal && text.isNotEmpty) {
        t.rawPartial = text;
      }
      if (event.isFinal && text.isNotEmpty) {
        t.rawFinal = text;
      }
      _publishTrace();

      final executing = state.phase == UiPhase.objectSearch ||
          state.phase == UiPhase.textSearch ||
          state.phase == UiPhase.nearbyText ||
          state.phase == UiPhase.nearbyObjects ||
          state.phase == UiPhase.personalRemember ||
          state.phase == UiPhase.documentRead ||
          state.phase == UiPhase.describe;

      if (executing) {
        if (event.isFinal && text.isNotEmpty) {
          await _handleTaskUtterance(text);
        }
        return;
      }

      // Soft end of home listening window (Kotlin exhausted retries).
      if (event.isFinal && text.isEmpty) {
        if (state.listening || state.phase == UiPhase.listening) {
          t.add('listen_window_end', true, 'quiet HOME');
          _publishTrace();
          await _goHome(playEndEarcon: false, speakStopped: false);
        }
        return;
      }

      // Grace: accept finals briefly after listening flag clears (early end bug).
      if (!_acceptHomeCommand) {
        _logDrop('not_listening', 'phase=${state.phase}');
        return;
      }
      if (_committedThisListen && !event.isFinal) {
        _logDrop('ignored_after_commit', text);
        return;
      }
      t.phaseAtReceive = '${state.phase}/listening=${state.listening}';
      t.add('dart_listener', true, t.phaseAtReceive);
      _publishTrace();

      if (!_continuationUsed) {
        _resetSilenceTimers();
      }
      if (text.isEmpty) {
        _logDrop('empty', 'final=${event.isFinal}');
        return;
      }
      state = state.copyWith(partialTranscript: text);
      if (event.isFinal) {
        if (_committedThisListen) {
          _logDrop('ignored_late_final', text);
          return;
        }
        await _handleUtterance(alts);
      } else {
        _schedulePartialCommit(alts);
      }
    });

    _host.guidance.listen((g) {
      if (g.announce != null && g.announce!.isNotEmpty) {
        state = state.copyWith(statusLine: g.announce);
      } else if (g.directionSpeech != null) {
        state = state.copyWith(statusLine: g.directionSpeech);
      }
      state = state.copyWith(proximity: g.proximity, guidancePhase: g.phase);
    });

    _host.sessions.listen((s) {
      // Do NOT auto-goHome on idle — cancel() emits idle and was killing
      // brand-new Find/Describe sessions (stale or same-turn events).
      if (s.error != null && s.error!.trim().isNotEmpty) {
        state = state.copyWith(statusLine: s.error);
      }
    });
  }

  void _applyFlow(AppFlowEvent event) {
    final t = _flow.reduce(
      state: state.flow,
      executing: state.executing,
      event: event,
    );
    state = state.copyWith(flow: t.next, executing: t.executing);
  }

  void _resetSilenceTimers() {
    _silenceWarn?.cancel();
    _silenceEnd?.cancel();
    if (state.phase != UiPhase.listening) return;
    // No spoken nudge — TTS mid-listen restarts ASR and retriggers the Google beep.
    _silenceEnd = Timer(const Duration(seconds: 30), () async {
      if (state.phase != UiPhase.listening) return;
      await _goHome(playEndEarcon: false, speakStopped: false);
    });
  }

  Future<void> onBigButton() async {
    if (state.phase == UiPhase.objectSearch ||
        state.phase == UiPhase.textSearch ||
        state.phase == UiPhase.nearbyText ||
        state.phase == UiPhase.nearbyObjects ||
        state.phase == UiPhase.personalRemember ||
        state.phase == UiPhase.documentRead ||
        state.phase == UiPhase.describe ||
        state.listening ||
        state.phase == UiPhase.listening) {
      await cancel();
      return;
    }
    _partialCommit?.cancel();
    _committedThisListen = false;
    _continuationUsed = false;
    _stablePartialText = '';
    _pendingPartialCommit = null;
    _lastAlternatives = const [];
    await _host.setSearchTicks(rateHz: 0);
    await _host.stopSpeaking();
    _applyFlow(AppFlowEvent.tapListen);
    state = state.copyWith(
      phase: UiPhase.listening,
      listening: true,
      partialTranscript: '',
      statusLine: 'Listening…',
      speechMuted: false,
    );
    _ref.read(commandLogProvider.notifier).state = CommandLogEntry(
      heard: '',
      parsed: 'listening',
      phase: 'listening',
      at: DateTime.now(),
    );
    // Spec: one haptic + one beep, then one recognizer session (~30s silence).
    await _host.vibrate(18);
    await _host.playEarcon('listeningStarted');
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (state.phase != UiPhase.listening || !state.listening) return;
    await _host.setTaskListening(false);
    await _host.startListening(taskMode: false);
    _resetSilenceTimers();
  }

  Future<void> cancel() async {
    await _goHome(playEndEarcon: true, speakStopped: true);
  }

  Future<void> _goHome({
    required bool playEndEarcon,
    required bool speakStopped,
  }) async {
    final t0 = DateTime.now();
    _silenceWarn?.cancel();
    _silenceEnd?.cancel();
    _partialCommit?.cancel();
    _committedThisListen = false;
    _continuationUsed = false;
    _stablePartialText = '';
    _pendingPartialCommit = null;
    _lastAlternatives = const [];
    // Idempotent stop only — no ownership cancel that can kill a new session.
    await _ref.read(speechQueueProvider).stop();
    await _host.stopSpeaking();
    await _host.cancel();
    await _host.stopListening();
    await _host.setTaskListening(false);
    await _host.setSearchTicks(rateHz: 0);
    await _host.setTorch(false);
    await _host.setKeepScreenOn(false);
    _applyFlow(AppFlowEvent.stop);
    state = state.copyWith(
      phase: UiPhase.home,
      flow: AppFlowState.home,
      clearExecuting: true,
      listening: false,
      partialTranscript: '',
      statusLine: 'Ready',
      proximity: 0,
      clearActiveQuery: true,
      speechMuted: false,
      hybridFind: false,
      describeContinuous: false,
      describeFromMemory: false,
      describeOnlineDetail: false,
    );
    final ms = DateTime.now().difference(t0).inMilliseconds;
    _ref.read(lastStopLatencyMsProvider.notifier).state = ms;
    _ref.read(commandLogProvider.notifier).state = CommandLogEntry(
      heard: state.partialTranscript,
      parsed: 'home',
      phase: 'home',
      at: DateTime.now(),
    );
  }

  static const _unknownMsg =
      "Sorry, I didn't catch that. Try: find a bottle, describe, or read this.";

  void _logCommand(
    String heard,
    String parsed, {
    List<String> alternatives = const [],
    String resolved = '',
  }) {
    _ref.read(commandLogProvider.notifier).state = CommandLogEntry(
      heard: heard,
      alternatives: alternatives,
      parsed: parsed,
      resolved: resolved,
      phase: state.phase.name,
      at: DateTime.now(),
    );
  }

  /// Kept for call sites; always-on stop spotter removed.
  void armStopSpotter() {}

  /// One short listen during a task (no restart loop). Used when user taps Stop-listen.
  Future<void> listenOnceForStop() async {
    if (state.phase == UiPhase.home || state.phase == UiPhase.listening) return;
    await _host.setTaskListening(true);
    await _host.startListening(taskMode: true);
  }

  Future<void> openSettings() async {
    _applyFlow(AppFlowEvent.openSettings);
    state = state.copyWith(
      phase: UiPhase.settings,
      executing: ExecutingKind.settings,
    );
  }

  Future<void> closeSettings() async {
    await _goHome(playEndEarcon: false, speakStopped: false);
  }

  /// Same entry point as the recognizer (Settings trace text box / adb).
  Future<void> injectVoiceCommand(String text) async {
    final heard = text.trim();
    final t = _trace..clear();
    t.rawFinal = heard;
    t.add('inject', true, heard);
    t.add('kotlin_to_dart', true, 'inject main-thread');
    t.add('dart_listener', true, 'inject→listening');
    t.phaseAtReceive = 'listening/inject';
    _publishTrace();
    // Pretend we are listening so grace/accept path is identical.
    state = state.copyWith(
      phase: UiPhase.listening,
      flow: AppFlowState.listening,
      listening: true,
      statusLine: 'Listening…',
    );
    _listenGraceUntil = DateTime.now().add(const Duration(seconds: 3));
    await _handleUtterance([heard]);
  }

  Future<void> _handleUtterance(List<String> alternatives) async {
    if (_handlingCommand) return;
    final alts = alternatives
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (alts.isEmpty) return;
    if (_committedThisListen) {
      _logDrop('ignored_duplicate_utterance', alts.first);
      return;
    }
    _handlingCommand = true;
    try {
      _silenceWarn?.cancel();
      _silenceEnd?.cancel();
      _partialCommit?.cancel();
      await _host.stopListening();
      final heard = alts.first;
      _lastAlternatives = alts;
      // Keep a short grace so a delayed duplicate final can still land.
      _listenGraceUntil = DateTime.now().add(const Duration(seconds: 2));
      state = state.copyWith(
        listening: false,
        partialTranscript: heard,
        statusLine: 'Heard: $heard',
      );

      const parser = IntentParser();
      final intent = parser.parseBest(alts);
      final t = _trace;
      t.normalized = heard.toLowerCase();
      t.intent = intent.runtimeType.toString();
      t.target = switch (intent) {
        ObjectSearchIntent(:final query) => query,
        TextSearchIntent(:final query) => query,
        HybridFindIntent(:final objectQuery) => objectQuery,
        _ => '',
      };
      t.add(
        'parsed',
        IntentParser.isComplete(intent),
        '${t.intent} target=${t.target} alts=$alts',
      );
      _publishTrace();
      _logCommand(
        heard,
        t.intent,
        alternatives: alts,
        resolved: t.target,
      );

      if (intent is ClarifyIntent) {
        final q = intent.question.trim().isNotEmpty
            ? intent.question
            : 'Find what?';
        // Incomplete find: say once, one 8s continuation, then quiet end.
        t.flowTransition = _continuationUsed
            ? 'clarify→home (no more continuation)'
            : 'clarify→one continuation 8s';
        _publishTrace();
        await _host.speak(q, interrupt: true);
        if (_continuationUsed) {
          await _goHome(playEndEarcon: false, speakStopped: false);
          return;
        }
        _continuationUsed = true;
        _committedThisListen = false;
        state = state.copyWith(
          phase: UiPhase.listening,
          flow: AppFlowState.listening,
          listening: true,
          statusLine: 'Listening…',
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (state.phase != UiPhase.listening) return;
        await _host.startListening(taskMode: false);
        _silenceWarn?.cancel();
        _silenceEnd?.cancel();
        _silenceEnd = Timer(const Duration(seconds: 8), () async {
          if (state.phase != UiPhase.listening) return;
          await _goHome(playEndEarcon: false, speakStopped: false);
        });
        return;
      }

      // Commit: ignore later finals/errors from this session.
      _committedThisListen = true;

      if (intent is UnsupportedIntent) {
        final msg = intent.message.trim().isNotEmpty ? intent.message : _unknownMsg;
        t.flowTransition = 'unsupported→home';
        _logDrop('unsupported', msg);
        _publishTrace();
        state = state.copyWith(
          phase: UiPhase.home,
          flow: AppFlowState.home,
          listening: false,
          statusLine: 'Ready',
        );
        await _host.speak(msg);
        return;
      }

      // Ensure state machine is in listening before startSearch.
      if (state.flow != AppFlowState.listening) {
        state = state.copyWith(flow: AppFlowState.listening);
      }
      await _dispatch(intent);
    } finally {
      _handlingCommand = false;
    }
  }

  Future<void> _handleTaskUtterance(String text) async {
    const parser = TaskCommandParser();
    final readCmd = parser.parseReadControl(text);
    if (readCmd != null && state.phase == UiPhase.documentRead) {
      state = state.copyWith(readCommand: readCmd);
      return;
    }
    final intent = parser.parse(text);
    if (intent == null) return;
    switch (intent) {
      case StopSpeakingIntent():
        state = state.copyWith(speechMuted: true);
        await _host.stopSpeaking();
      case StopLookingIntent():
      case StopIntent():
      case GoBackIntent():
        await cancel();
      case RepeatIntent():
        final last = state.lastSpokenGuidance;
        if (last != null && last.isNotEmpty) {
          await _host.speak(last, interrupt: true);
        }
      case KeepLookingIntent():
        state = state.copyWith(
          statusLine: 'Still looking for ${state.activeQuery ?? 'it'}',
          keepLookingAck: DateTime.now(),
        );
      case DescribeIntent():
        await _openDescribe();
      default:
        break;
    }
  }

  Future<Map<String, String>> _personalObjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('personalObjects');
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _dispatch(AppIntent intent) async {
    switch (intent) {
      case StopIntent():
      case GoBackIntent():
      case StopLookingIntent():
        await cancel();
      case StopSpeakingIntent():
        state = state.copyWith(speechMuted: true);
        await _ref.read(speechQueueProvider).stop();
        await _host.stopSpeaking();
      case KeepLookingIntent():
        state = state.copyWith(phase: UiPhase.home, flow: AppFlowState.home);
      case RepeatIntent():
        final last = state.lastSpokenGuidance;
        if (last != null && last.isNotEmpty) {
          await _host.speak(last, interrupt: true);
        } else {
          await _host.speak(_unknownMsg);
          await _goHome(playEndEarcon: false, speakStopped: false);
        }
      case OpenSettingsIntent():
        await openSettings();
        await _host.speak('Settings.');
      case ObjectSearchIntent(:final query):
        final personal = _ref.read(coreExtrasEnabledProvider)
            ? await _personalObjects()
            : <String, String>{};
        final resolved = SupportedObjects.resolve(query, personal: personal);
        final t = _trace;
        if (resolved == null) {
          // Fallback: hunt the spoken words as on-screen text.
          t.flowTransition = 'object→textSearch "$query"';
          t.add('state_machine', true, t.flowTransition);
          _publishTrace();
          _applyFlow(AppFlowEvent.startRead);
          state = state.copyWith(
            phase: UiPhase.textSearch,
            flow: AppFlowState.executing,
            executing: ExecutingKind.textSearch,
            statusLine: 'Looking for text $query',
            activeQuery: query,
            hybridFind: false,
            speechMuted: false,
          );
          await _host.setKeepScreenOn(true);
          return;
        }
        // Permissions before route — never open Search silently denied.
        await Permission.microphone.request();
        final cam = await Permission.camera.request();
        t.cameraPermission = cam.isGranted ? 'granted' : 'denied';
        t.add('camera_permission', cam.isGranted, t.cameraPermission);
        _publishTrace();
        if (!cam.isGranted) {
          state = state.copyWith(
            phase: UiPhase.home,
            flow: AppFlowState.home,
            statusLine: 'Camera permission needed',
          );
          await _host.speak('I need camera permission.');
          return;
        }
        final before = state.flow;
        _applyFlow(AppFlowEvent.startSearch);
        final accepted = state.flow == AppFlowState.executing ||
            before == AppFlowState.listening;
        t.flowTransition = accepted
            ? 'accepted: $before→executing search'
            : 'rejected: flow was $before';
        t.add('state_machine', accepted, t.flowTransition);
        // Force navigation regardless of flow bookkeeping.
        state = state.copyWith(
          phase: UiPhase.objectSearch,
          flow: AppFlowState.executing,
          executing: ExecutingKind.search,
          statusLine: 'Looking for $resolved',
          activeQuery: resolved,
          speechMuted: false,
        );
        t.navCalled = true;
        t.target = resolved;
        t.add('navigation_called', true, 'phase=objectSearch query=$resolved');
        _publishTrace();
        // Verify route still up after 500ms.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () {
          final still = state.phase == UiPhase.objectSearch;
          t.navVisible = still;
          t.add('navigation_visible', still, 'phase=${state.phase}');
          _publishTrace();
        }));
        await _host.setKeepScreenOn(true);
        final article = RegExp(r'^[aeiou]', caseSensitive: false).hasMatch(resolved)
            ? 'an'
            : 'a';
        await _host.speak('Looking for $article $resolved.');
      case ClarifyIntent():
      case UnsupportedIntent():
        state = state.copyWith(
          phase: UiPhase.home,
          flow: AppFlowState.home,
          statusLine: 'Ready',
        );
        await _host.speak(_unknownMsg);
      case TextSearchIntent(:final query):
        _applyFlow(AppFlowEvent.startRead);
        state = state.copyWith(
          phase: UiPhase.textSearch,
          flow: AppFlowState.executing,
          executing: ExecutingKind.textSearch,
          statusLine: 'Looking for text $query',
          activeQuery: query,
          hybridFind: false,
          speechMuted: false,
        );
        await _host.setKeepScreenOn(true);
        await _host.speak('Looking for the word $query.');
      case NearbyTextIntent():
        _applyFlow(AppFlowEvent.startRead);
        state = state.copyWith(
          phase: UiPhase.nearbyText,
          flow: AppFlowState.executing,
          executing: ExecutingKind.nearbyText,
          statusLine: 'Nearby text',
          speechMuted: false,
        );
        await _host.setKeepScreenOn(true);
      case DocumentReadIntent():
        _applyFlow(AppFlowEvent.startRead);
        state = state.copyWith(
          phase: UiPhase.documentRead,
          flow: AppFlowState.executing,
          executing: ExecutingKind.read,
          statusLine: 'Reading mode',
          speechMuted: false,
        );
        await _host.setSearchTicks(rateHz: 0);
        await _host.setKeepScreenOn(true);
      case HybridFindIntent(:final objectQuery, :final textQuery):
        _applyFlow(AppFlowEvent.startSearch);
        state = state.copyWith(
          phase: UiPhase.textSearch,
          flow: AppFlowState.executing,
          executing: ExecutingKind.textSearch,
          statusLine: 'Looking for $objectQuery',
          activeQuery: textQuery,
          secondaryQuery: objectQuery,
          hybridFind: true,
          speechMuted: false,
        );
        await _host.setKeepScreenOn(true);
      case DescribeDetailIntent():
        // Same offline detector narrative as SCENE_DESCRIPTION — no cloud.
        await _openDescribe(continuous: true);
      case DescribeIntent(:final continuous, :final fromMemory):
        await _openDescribe(
          continuous: continuous,
          fromMemory: fromMemory,
        );
      case NarrationIntent():
        await _openDescribe(continuous: true);
      case IdentifyIntent():
        await _openDescribe(continuous: true);
      case NearbyObjectsIntent():
        await _openDescribe(continuous: true);
      case PersonalRememberIntent(:final name):
        if (!_ref.read(coreExtrasEnabledProvider)) {
          await _host.speak(_unknownMsg);
          await _goHome(playEndEarcon: false, speakStopped: false);
          return;
        }
        _applyFlow(AppFlowEvent.startSearch);
        state = state.copyWith(
          phase: UiPhase.personalRemember,
          flow: AppFlowState.executing,
          executing: ExecutingKind.personal,
          statusLine: 'Remember personal object',
          activeQuery: name,
          speechMuted: false,
        );
      case OnlineChatIntent():
        await _host.speak("I can't answer that right now.");
        state = state.copyWith(phase: UiPhase.home, flow: AppFlowState.home);
    }
  }

  Future<void> _openDescribe({
    bool continuous = true,
    bool fromMemory = false,
  }) async {
    final loop = fromMemory ? false : true;
    _applyFlow(AppFlowEvent.startDescribe);
    state = state.copyWith(
      phase: UiPhase.describe,
      flow: AppFlowState.executing,
      executing: ExecutingKind.describe,
      statusLine: 'Surroundings',
      speechMuted: false,
      describeContinuous: loop || continuous,
      describeFromMemory: fromMemory,
      describeOnlineDetail: false,
    );
    await _host.setSearchTicks(rateHz: 0);
  }

  void noteSpokenGuidance(String phrase) {
    state = state.copyWith(lastSpokenGuidance: phrase);
  }

  void rememberRoom(String phrase) {
    final mem = [...state.roomMemory, phrase];
    state = state.copyWith(roomMemory: mem.length > 40 ? mem.sublist(mem.length - 40) : mem);
  }

  String roomMemorySummary() {
    if (state.roomMemory.isEmpty) {
      return 'I have not noted objects in this room yet.';
    }
    return 'In this room I have seen ${state.roomMemory.join(' ')}';
  }

  void setSpeechMuted(bool muted) {
    state = state.copyWith(speechMuted: muted);
  }

  void clearReadCommand() {
    state = state.copyWith(clearReadCommand: true);
  }

  @override
  void dispose() {
    _silenceWarn?.cancel();
    _silenceEnd?.cancel();
    _partialCommit?.cancel();
    _asrSub?.cancel();
    super.dispose();
  }
}

class AppUiState {
  const AppUiState({
    this.phase = UiPhase.home,
    this.flow = AppFlowState.home,
    this.executing,
    this.listening = false,
    this.partialTranscript = '',
    this.statusLine = 'Ready',
    this.activeQuery,
    this.secondaryQuery,
    this.hybridFind = false,
    this.proximity = 0,
    this.guidancePhase = GuidancePhase.searching,
    this.speechMuted = false,
    this.lastSpokenGuidance,
    this.keepLookingAck,
    this.describeContinuous = false,
    this.describeFromMemory = false,
    this.describeOnlineDetail = false,
    this.readCommand,
    this.roomMemory = const [],
  });

  final UiPhase phase;
  final AppFlowState flow;
  final ExecutingKind? executing;
  final bool listening;
  final String partialTranscript;
  final String statusLine;
  final String? activeQuery;
  final String? secondaryQuery;
  final bool hybridFind;
  final double proximity;
  final GuidancePhase guidancePhase;
  final bool speechMuted;
  final String? lastSpokenGuidance;
  final DateTime? keepLookingAck;
  final bool describeContinuous;
  final bool describeFromMemory;
  final bool describeOnlineDetail;
  final String? readCommand;
  final List<String> roomMemory;

  AppUiState copyWith({
    UiPhase? phase,
    AppFlowState? flow,
    ExecutingKind? executing,
    bool clearExecuting = false,
    bool? listening,
    String? partialTranscript,
    String? statusLine,
    String? activeQuery,
    bool clearActiveQuery = false,
    String? secondaryQuery,
    bool? hybridFind,
    double? proximity,
    GuidancePhase? guidancePhase,
    bool? speechMuted,
    String? lastSpokenGuidance,
    DateTime? keepLookingAck,
    bool? describeContinuous,
    bool? describeFromMemory,
    bool? describeOnlineDetail,
    String? readCommand,
    bool clearReadCommand = false,
    List<String>? roomMemory,
  }) {
    return AppUiState(
      phase: phase ?? this.phase,
      flow: flow ?? this.flow,
      executing: clearExecuting ? null : (executing ?? this.executing),
      listening: listening ?? this.listening,
      partialTranscript: partialTranscript ?? this.partialTranscript,
      statusLine: statusLine ?? this.statusLine,
      activeQuery:
          clearActiveQuery ? null : (activeQuery ?? this.activeQuery),
      secondaryQuery: secondaryQuery ?? this.secondaryQuery,
      hybridFind: hybridFind ?? this.hybridFind,
      proximity: proximity ?? this.proximity,
      guidancePhase: guidancePhase ?? this.guidancePhase,
      speechMuted: speechMuted ?? this.speechMuted,
      lastSpokenGuidance: lastSpokenGuidance ?? this.lastSpokenGuidance,
      keepLookingAck: keepLookingAck ?? this.keepLookingAck,
      describeContinuous: describeContinuous ?? this.describeContinuous,
      describeFromMemory: describeFromMemory ?? this.describeFromMemory,
      describeOnlineDetail: describeOnlineDetail ?? this.describeOnlineDetail,
      readCommand: clearReadCommand ? null : (readCommand ?? this.readCommand),
      roomMemory: roomMemory ?? this.roomMemory,
    );
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppUiState>((ref) {
  return AppController(ref);
});
