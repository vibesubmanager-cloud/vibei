import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

SceneSignature sig(String bag, {int hash = 1}) => SceneSignature(
      classBag: bag,
      centroidHash: hash,
      brightnessBucket: 4,
    );

void main() {
  test('still → moving → settle → newView', () {
    final c = ViewMotionClassifier(settleMs: 50, changeDistance: 0.3);
    final a = sig('chair:1|table:1', hash: 100);
    expect(
      c.update(signature: a, motionScore: 0, blurry: false),
      ViewMotionState.newView,
    );
    c.forceStill();

    expect(
      c.update(signature: a, motionScore: 0.5, blurry: false),
      ViewMotionState.moving,
    );

    final b = sig('couch:1|tv:1', hash: 900000);
    final t0 = DateTime.now();
    expect(
      c.update(
        signature: b,
        motionScore: 0,
        blurry: false,
        now: t0,
      ),
      ViewMotionState.moving,
    );
    expect(
      c.update(
        signature: b,
        motionScore: 0,
        blurry: false,
        now: t0.add(const Duration(milliseconds: 60)),
      ),
      ViewMotionState.newView,
    );
  });

  test('unchanged view stays still', () {
    final c = ViewMotionClassifier();
    final a = sig('bottle:1', hash: 10);
    c.update(signature: a, motionScore: 0, blurry: false);
    c.forceStill();
    expect(
      c.update(signature: a, motionScore: 0.05, blurry: false),
      ViewMotionState.still,
    );
  });
}
