/// Pure search guidance: tick rate, stereo pan, speech throttling.
enum SearchTickPhase {
  hunting,
  visibleOffCenter,
  centered,
  reached,
}

class SearchGuidanceSnapshot {
  const SearchGuidanceSnapshot({
    required this.phase,
    required this.ticksPerSecond,
    required this.pan,
    required this.vibrationMs,
    required this.playReachedChirp,
    required this.playLostTone,
    this.speech,
  });

  final SearchTickPhase phase;

  /// Soft tick rate (Hz).
  final double ticksPerSecond;

  /// -1 = left ear, 0 = center, +1 = right ear.
  final double pan;

  final int vibrationMs;
  final bool playReachedChirp;
  final bool playLostTone;
  final String? speech;
}

class SpeechThrottleState {
  const SpeechThrottleState({
    this.lastPhrase,
    this.lastSpokenAt,
    this.spokenOnceFound = false,
    this.saidLost = false,
    this.saidNotFound60 = false,
    this.muted = false,
  });

  final String? lastPhrase;
  final DateTime? lastSpokenAt;
  final bool spokenOnceFound;
  final bool saidLost;
  final bool saidNotFound60;
  final bool muted;

  SpeechThrottleState copyWith({
    String? lastPhrase,
    DateTime? lastSpokenAt,
    bool? spokenOnceFound,
    bool? saidLost,
    bool? saidNotFound60,
    bool? muted,
    bool clearPhrase = false,
  }) {
    return SpeechThrottleState(
      lastPhrase: clearPhrase ? null : (lastPhrase ?? this.lastPhrase),
      lastSpokenAt: lastSpokenAt ?? this.lastSpokenAt,
      spokenOnceFound: spokenOnceFound ?? this.spokenOnceFound,
      saidLost: saidLost ?? this.saidLost,
      saidNotFound60: saidNotFound60 ?? this.saidNotFound60,
      muted: muted ?? this.muted,
    );
  }
}

class SearchGuidanceEngine {
  SearchGuidanceEngine({
    this.minSpeechGap = const Duration(seconds: 3),
    this.noRepeatWithin = const Duration(seconds: 8),
    this.centerBand = 0.12,
    this.reachedArea = 0.22,
  });

  final Duration minSpeechGap;
  final Duration noRepeatWithin;
  final double centerBand;
  final double reachedArea;

  /// Map target box → tick rate + pan. [cx]/[area] in 0..1 normalized frame.
  SearchTickPhase phaseFor({
    required bool hasTarget,
    required double cx,
    required double area,
  }) {
    if (!hasTarget) return SearchTickPhase.hunting;
    final centered = (cx - 0.5).abs() <= centerBand;
    if (centered && area >= reachedArea) return SearchTickPhase.reached;
    if (centered) return SearchTickPhase.centered;
    return SearchTickPhase.visibleOffCenter;
  }

  double ticksPerSecond(SearchTickPhase phase, {double area = 0}) {
    switch (phase) {
      case SearchTickPhase.hunting:
        return 1.0;
      case SearchTickPhase.visibleOffCenter:
        return 2.0;
      case SearchTickPhase.centered:
        return (3.0 + (area.clamp(0, 0.4) / 0.4) * 3.0).clamp(3.0, 6.0);
      case SearchTickPhase.reached:
        return 8.0;
    }
  }

  /// Stereo pan toward target side.
  double panFor(double cx, SearchTickPhase phase) {
    if (phase == SearchTickPhase.hunting) return 0;
    if (phase == SearchTickPhase.centered || phase == SearchTickPhase.reached) {
      return 0;
    }
    return ((cx - 0.5) / 0.5).clamp(-1.0, 1.0);
  }

  int vibrationMs(SearchTickPhase phase, {double area = 0}) {
    switch (phase) {
      case SearchTickPhase.hunting:
        return 18;
      case SearchTickPhase.visibleOffCenter:
        return 28;
      case SearchTickPhase.centered:
        return (40 + area * 80).round().clamp(40, 90);
      case SearchTickPhase.reached:
        return 220;
    }
  }

  /// Decide whether [candidate] may be spoken now.
  bool maySpeak(SpeechThrottleState state, String candidate, DateTime now) {
    if (state.muted) return false;
    if (state.lastSpokenAt != null) {
      if (now.difference(state.lastSpokenAt!) < minSpeechGap) return false;
      if (candidate == state.lastPhrase &&
          now.difference(state.lastSpokenAt!) < noRepeatWithin) {
        return false;
      }
    }
    return true;
  }

  /// Build one guidance step from detector output + prior speech state.
  ({SearchGuidanceSnapshot snap, SpeechThrottleState speech}) step({
    required String query,
    required bool hasTarget,
    required double cx,
    required double area,
    required bool hadTargetBefore,
    required bool improving,
    required Duration huntingFor,
    required SpeechThrottleState speech,
    required DateTime now,
  }) {
    final phase = phaseFor(hasTarget: hasTarget, cx: cx, area: area);
    final tps = ticksPerSecond(phase, area: area);
    final pan = panFor(cx, phase);
    final vib = vibrationMs(phase, area: area);

    var nextSpeech = speech;
    String? line;
    var reachedChirp = false;
    var lostTone = false;

    if (!hasTarget && hadTargetBefore && !speech.saidLost) {
      line = 'Lost it';
      nextSpeech = nextSpeech.copyWith(saidLost: true, spokenOnceFound: false);
      lostTone = true;
    } else if (!hasTarget &&
        huntingFor >= const Duration(seconds: 60) &&
        !speech.saidNotFound60) {
      line =
          "I haven't found the $query. Say keep looking, or stop.";
      nextSpeech = nextSpeech.copyWith(saidNotFound60: true);
    } else if (hasTarget) {
      nextSpeech = nextSpeech.copyWith(saidLost: false);
      final side = _side(cx);
      if (!speech.spokenOnceFound) {
        line = _firstFound(query, side, area);
        nextSpeech = nextSpeech.copyWith(spokenOnceFound: true);
      } else if (!improving) {
        line = _driftPhrase(side, area, phase);
      }
      if (phase == SearchTickPhase.reached && !speech.spokenOnceFound) {
        // first-found covers it
      }
      if (phase == SearchTickPhase.reached) {
        reachedChirp = true;
      }
    }

    if (line != null) {
      if (maySpeak(nextSpeech, line, now)) {
        nextSpeech = nextSpeech.copyWith(lastPhrase: line, lastSpokenAt: now);
      } else {
        line = null;
      }
    }

    return (
      snap: SearchGuidanceSnapshot(
        phase: phase,
        ticksPerSecond: tps,
        pan: pan,
        vibrationMs: vib,
        playReachedChirp: reachedChirp,
        playLostTone: lostTone,
        speech: line,
      ),
      speech: nextSpeech,
    );
  }

  String _side(double cx) {
    if (cx < 0.38) return 'left';
    if (cx > 0.62) return 'right';
    return 'center';
  }

  String _firstFound(String query, String side, double area) {
    final label = query.isEmpty
        ? 'Object'
        : '${query[0].toUpperCase()}${query.substring(1)}';
    final where = side == 'center'
        ? "it's at the center"
        : side == 'left'
            ? "it's on the left"
            : "it's on the right";
    if (area < reachedArea) {
      return '$label found, $where, move closer.';
    }
    return '$label found, $where.';
  }

  String? _driftPhrase(String side, double area, SearchTickPhase phase) {
    if (phase == SearchTickPhase.reached) return null;
    if (side == 'left') return 'go right';
    if (side == 'right') return 'go left';
    if (area < reachedArea * 0.6) return 'move closer';
    return 'go back a little';
  }
}
