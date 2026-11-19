import 'detection.dart';

enum ViewChangeKind { stationary, changed, settling }

class SceneSignature {
  const SceneSignature({
    required this.classBag,
    required this.centroidHash,
    required this.brightnessBucket,
  });

  final String classBag;
  final int centroidHash;
  final int brightnessBucket;

  factory SceneSignature.fromDetections(
    List<Detection> detections, {
    double brightness = 0.5,
  }) {
    final labels = detections.map((d) => d.label).toList()..sort();
    final bag = <String, int>{};
    for (final l in labels) {
      bag[l] = (bag[l] ?? 0) + 1;
    }
    final classBag =
        bag.entries.map((e) => '${e.key}:${e.value}').join('|');
    var hash = 0;
    for (final d in detections) {
      hash = (hash * 31 + (d.cx * 10).round()) & 0x7fffffff;
      hash = (hash * 31 + (d.cy * 10).round()) & 0x7fffffff;
    }
    return SceneSignature(
      classBag: classBag,
      centroidHash: hash,
      brightnessBucket: (brightness * 8).round().clamp(0, 8),
    );
  }

  double distanceTo(SceneSignature other) {
    final sameClasses = classBag == other.classBag;
    final posDelta =
        (centroidHash - other.centroidHash).abs() / 1000000.0;
    final brightDelta =
        (brightnessBucket - other.brightnessBucket).abs() / 8.0;
    if (!sameClasses) return 0.7 + brightDelta * 0.2;
    return (posDelta.clamp(0, 1) * 0.6) + brightDelta * 0.3;
  }
}

class SceneChangeDetector {
  SceneChangeDetector({
    this.moveThreshold = 0.38,
    this.settleFrames = 2,
    this.motionSkip = 0.22,
  });

  final double moveThreshold;
  final int settleFrames;
  final double motionSkip;

  SceneSignature? _current;
  SceneSignature? _candidate;
  int _candidateHits = 0;
  final List<String> roomMemoryKeys = [];
  final Map<String, List<String>> roomFacts = {};

  ViewChangeKind classify({
    required SceneSignature signature,
    required double motionScore,
    required bool blurry,
  }) {
    if (blurry || motionScore > motionSkip) {
      return ViewChangeKind.settling;
    }
    if (_current == null) {
      _current = signature;
      _remember(signature);
      return ViewChangeKind.changed;
    }
    final dist = _current!.distanceTo(signature);
    if (dist < moveThreshold * 0.5) {
      _candidate = null;
      _candidateHits = 0;
      return ViewChangeKind.stationary;
    }
    if (dist >= moveThreshold) {
      _candidate = signature;
      _candidateHits++;
      if (_candidateHits >= settleFrames) {
        _current = signature;
        _candidate = null;
        _candidateHits = 0;
        _remember(signature);
        return ViewChangeKind.changed;
      }
      return ViewChangeKind.settling;
    }
    return ViewChangeKind.stationary;
  }

  bool isKnownView(SceneSignature signature) {
    final key = _key(signature);
    return roomMemoryKeys.contains(key);
  }

  void _remember(SceneSignature s) {
    final key = _key(s);
    if (!roomMemoryKeys.contains(key)) {
      roomMemoryKeys.add(key);
      if (roomMemoryKeys.length > 24) {
        final old = roomMemoryKeys.removeAt(0);
        roomFacts.remove(old);
      }
    }
  }

  void addFact(SceneSignature s, String fact) {
    final key = _key(s);
    final list = roomFacts.putIfAbsent(key, () => []);
    if (!list.contains(fact)) list.add(fact);
  }

  List<String> allFacts() {
    final out = <String>[];
    for (final k in roomMemoryKeys) {
      out.addAll(roomFacts[k] ?? const []);
    }
    return out;
  }

  String _key(SceneSignature s) =>
      '${s.classBag}#${s.centroidHash ~/ 1000}#${s.brightnessBucket}';
}
