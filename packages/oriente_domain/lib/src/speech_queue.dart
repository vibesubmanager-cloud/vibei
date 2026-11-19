enum SpeechPriority {
  ambient,
  guidance,
  found,
  userRequested,
  safety,
  stop,
}

class SpeechItem {
  const SpeechItem({
    required this.id,
    required this.text,
    required this.priority,
    this.viewKey,
    this.objectKey,
  });

  final String id;
  final String text;
  final SpeechPriority priority;
  final String? viewKey;
  final String? objectKey;
}

/// Single speech queue: priority, dedupe, never cuts mid-sentence except stop/safety.
class SpeechQueue {
  SpeechQueue({this.maxSaid = 80, this.watchdogMs = 12000});

  final int maxSaid;
  final int watchdogMs;
  final List<SpeechItem> _pending = [];
  final Set<String> _saidKeys = {};
  bool silenced = false;
  SpeechItem? current;
  DateTime? _speakingSince;

  bool get isSpeaking => current != null;

  void enqueue(SpeechItem item) {
    if (silenced && item.priority != SpeechPriority.stop) return;
    final key = _dedupeKey(item);
    if (_saidKeys.contains(key) && item.priority.index < SpeechPriority.found.index) {
      return;
    }
    // Drop stale lower/equal guidance for same object.
    _pending.removeWhere(
      (p) =>
          p.objectKey != null &&
          p.objectKey == item.objectKey &&
          p.priority.index <= item.priority.index,
    );
    // Keep at most one pending ambient/guidance description per view change.
    if (item.viewKey != null &&
        item.priority.index <= SpeechPriority.userRequested.index) {
      _pending.removeWhere(
        (p) =>
            p.viewKey != null &&
            p.viewKey != item.viewKey &&
            p.priority.index <= SpeechPriority.userRequested.index,
      );
    }
    _insertByPriority(item);
  }

  void _insertByPriority(SpeechItem item) {
    var i = 0;
    while (i < _pending.length &&
        _pending[i].priority.index >= item.priority.index) {
      i++;
    }
    _pending.insert(i, item);
  }

  /// Only stop/safety may cut a sentence in progress.
  bool shouldInterrupt(SpeechItem next) {
    final cur = current;
    if (cur == null) return false;
    return next.priority.index >= SpeechPriority.safety.index &&
        next.priority.index > cur.priority.index;
  }

  SpeechItem? dequeue() {
    _tripWatchdogIfNeeded();
    if (silenced &&
        (_pending.isEmpty ||
            _pending.first.priority.index < SpeechPriority.stop.index)) {
      return null;
    }
    if (_pending.isEmpty) return null;
    if (current != null) return null;
    final item = _pending.removeAt(0);
    current = item;
    _speakingSince = DateTime.now();
    _saidKeys.add(_dedupeKey(item));
    if (_saidKeys.length > maxSaid) {
      _saidKeys.remove(_saidKeys.first);
    }
    return item;
  }

  void markFinished() {
    current = null;
    _speakingSince = null;
  }

  bool _tripWatchdogIfNeeded() {
    final since = _speakingSince;
    if (current == null || since == null) return false;
    if (DateTime.now().difference(since).inMilliseconds < watchdogMs) {
      return false;
    }
    current = null;
    _speakingSince = null;
    return true;
  }

  bool tickWatchdog() => _tripWatchdogIfNeeded();

  void stopSpeaking() {
    _pending.clear();
    current = null;
    _speakingSince = null;
    silenced = true;
  }

  void cancelCurrent({bool clearPending = true}) {
    if (clearPending) _pending.clear();
    current = null;
    _speakingSince = null;
  }

  void resume() {
    silenced = false;
  }

  void clearViewDedupe(String viewKey) {
    _saidKeys.removeWhere((k) => k.startsWith('v:$viewKey|'));
  }

  void clearCurrentViewSaid() {
    _saidKeys.removeWhere((k) => k.startsWith('v:'));
  }

  String _dedupeKey(SpeechItem i) {
    if (i.objectKey != null) return 'o:${i.objectKey}';
    if (i.viewKey != null) return 'v:${i.viewKey}|${i.text.toLowerCase()}';
    return 't:${i.text.toLowerCase()}';
  }

  int get pendingCount => _pending.length;

  String get debugState {
    final cur = current?.text ?? '-';
    final wd = _speakingSince == null
        ? 'ok'
        : '${DateTime.now().difference(_speakingSince!).inMilliseconds}ms';
    return 'speak=${isSpeaking ? 1 : 0} pend=$pendingCount wd=$wd cur=$cur';
  }
}

/// Merge found + move-closer into one clean utterance.
String mergeFoundGuidance({
  required String queryLabel,
  required bool moveCloser,
  String? direction,
}) {
  final label = queryLabel.trim().isEmpty ? 'Target' : queryLabel.trim();
  final head = '${label[0].toUpperCase()}${label.substring(1)} found';
  final parts = <String>[head];
  if (direction != null && direction.trim().isNotEmpty) {
    parts.add(direction.trim());
  }
  if (moveCloser) {
    parts.add('Move closer.');
  }
  return parts.join('. ').replaceAll('..', '.');
}
