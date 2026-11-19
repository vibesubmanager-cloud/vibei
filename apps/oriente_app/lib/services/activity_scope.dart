import 'dart:async';

import 'package:oriente_platform/oriente_platform.dart';

import 'speech_queue_service.dart';

/// Lightweight page helper. No ownership cancel that can kill a new session.
class ActivityScope {
  ActivityScope(this._host, this._speech);

  final OrienteHost _host;
  final SpeechQueueService _speech;

  String? _owner;
  int _generation = 0;
  final Set<Timer> _timers = {};
  bool _stopped = false;

  String? get owner => _owner;
  int get generation => _generation;

  bool isActive(String owner, int gen) =>
      _owner == owner && _generation == gen;

  Future<({String owner, int gen})> claim(
    String owner, {
    Future<void> Function()? onCancel,
  }) async {
    // Do not cancel the previous session here — that raced new Find/Describe.
    _owner = owner;
    _generation += 1;
    _stopped = false;
    return (owner: owner, gen: _generation);
  }

  /// Idempotent stop used on page close only.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final t in List<Timer>.from(_timers)) {
      t.cancel();
    }
    _timers.clear();
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _host.stopSpeaking();
    } catch (_) {}
    try {
      await _host.stopListening();
    } catch (_) {}
    try {
      await _host.setSearchTicks(rateHz: 0);
    } catch (_) {}
    try {
      await _host.setTorch(false);
    } catch (_) {}
  }

  /// Legacy name → idempotent [stop].
  Future<void> cancelAll({String reason = 'cancelled'}) => stop();

  Timer ownedTimer(
    Duration duration,
    void Function() callback, {
    required String owner,
    required int gen,
  }) {
    late final Timer t;
    t = Timer(duration, () {
      _timers.remove(t);
      if (!isActive(owner, gen)) return;
      callback();
    });
    _timers.add(t);
    return t;
  }

  Future<void> speakOwned(
    String text, {
    required String owner,
    required int gen,
    bool interrupt = true,
  }) async {
    if (!isActive(owner, gen)) return;
    if (text.trim().isEmpty) return;
    await _host.speak(text, interrupt: interrupt);
  }

  Future<void> sayOwned(
    String text, {
    required String owner,
    required int gen,
    Object? priority,
    bool interrupt = false,
  }) async {
    if (!isActive(owner, gen)) return;
    await _speech.say(text, interrupt: interrupt);
  }
}
