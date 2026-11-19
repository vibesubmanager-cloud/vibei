import 'dart:async';
import 'dart:collection';

import 'package:oriente_platform/oriente_platform.dart';

/// Plain FIFO speech queue — no priorities, no ducking.
class SpeechQueueService {
  SpeechQueueService(this._host);

  final OrienteHost _host;
  final Queue<String> _pending = Queue<String>();
  bool _pumping = false;
  bool _stopped = false;
  bool _speaking = false;
  void Function(String text)? onSpeaking;

  bool get isSpeaking => _speaking;
  int get pendingCount => _pending.length;
  bool get isBusy => _speaking || _pending.isNotEmpty || _pumping;

  /// Compatibility shim for callers that used speech.queue.*.
  SpeechQueueService get queue => this;

  void dispose() {}

  Future<void> say(
    String text, {
    Object? priority,
    String? viewKey,
    String? objectKey,
    bool interrupt = false,
  }) async {
    if (text.trim().isEmpty) return;
    final cleaned = text
        .replaceAll(RegExp(r'no internet[^.]*\.?', caseSensitive: false), '')
        .replaceAll(RegExp(r'reading offline\.?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\boffline\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bonline\b', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty) return;

    if (interrupt) {
      try {
        await _host.stopSpeaking();
      } catch (_) {}
      _pending.clear();
      _pumping = false;
    }
    _stopped = false;
    _pending.add(cleaned);
    await _pump();
  }

  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    try {
      await _host.stopSpeaking();
    } catch (_) {}
    _pumping = false;
    _speaking = false;
    onSpeaking?.call('');
  }

  void resume() {
    _stopped = false;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_stopped && _pending.isNotEmpty) {
        final next = _pending.removeFirst();
        _speaking = true;
        onSpeaking?.call(next);
        try {
          await _host
              .speak(next, interrupt: false)
              .timeout(const Duration(seconds: 30));
        } catch (_) {
        } finally {
          _speaking = false;
          onSpeaking?.call('');
        }
        if (_stopped) break;
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _pumping = false;
    }
  }
}
