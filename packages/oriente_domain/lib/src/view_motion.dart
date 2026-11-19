import 'scene_signature.dart';

/// Continuous-describe camera view state (NYOTA §4 / addendum).
enum ViewMotionState { still, moving, newView }

class ViewMotionClassifier {
  ViewMotionClassifier({
    this.moveMotion = 0.18,
    this.settleMs = 500,
    this.changeDistance = 0.38,
    this.sameDistance = 0.18,
  });

  final double moveMotion;
  final int settleMs;
  final double changeDistance;
  final double sameDistance;

  SceneSignature? _current;
  SceneSignature? _candidate;
  DateTime? _movingSince;
  DateTime? _settleSince;
  double lastSimilarity = 1.0;
  ViewMotionState state = ViewMotionState.still;

  /// [gyroEnergy] optional 0..1 supporting signal from rotation sensor.
  ViewMotionState update({
    required SceneSignature signature,
    required double motionScore,
    required bool blurry,
    double gyroEnergy = 0,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final movingHard = blurry ||
        motionScore >= moveMotion ||
        gyroEnergy >= 0.25;

    if (_current == null) {
      _current = signature;
      lastSimilarity = 1.0;
      state = ViewMotionState.newView;
      _movingSince = null;
      _settleSince = null;
      return state;
    }

    final dist = _current!.distanceTo(signature);
    lastSimilarity = (1.0 - dist).clamp(0.0, 1.0);

    if (movingHard) {
      _movingSince ??= t;
      _settleSince = null;
      _candidate = null;
      state = ViewMotionState.moving;
      return state;
    }

    // Settling after motion or while candidate differs.
    if (dist >= changeDistance) {
      _candidate = signature;
      _settleSince ??= t;
      final settled = t.difference(_settleSince!).inMilliseconds >= settleMs;
      if (settled) {
        _current = signature;
        _candidate = null;
        _settleSince = null;
        _movingSince = null;
        state = ViewMotionState.newView;
        return state;
      }
      state = ViewMotionState.moving;
      return state;
    }

    if (dist <= sameDistance) {
      _candidate = null;
      _settleSince = null;
      _movingSince = null;
      state = ViewMotionState.still;
      return state;
    }

    // Mild change — wait to settle before committing NEW_VIEW.
    _settleSince ??= t;
    if (t.difference(_settleSince!).inMilliseconds >= settleMs &&
        dist >= changeDistance * 0.75) {
      _current = signature;
      _settleSince = null;
      state = ViewMotionState.newView;
      return state;
    }
    state = ViewMotionState.still;
    return state;
  }

  void forceStill() {
    state = ViewMotionState.still;
    _settleSince = null;
    _movingSince = null;
  }
}
