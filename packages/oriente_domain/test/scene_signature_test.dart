import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  test('stationary vs moved', () {
    final d = SceneChangeDetector(settleFrames: 2);
    final a = SceneSignature.fromDetections(const [
      Detection(label: 'chair', score: 0.9, cx: 0.5, cy: 0.5, width: 0.2, height: 0.3),
    ]);
    expect(
      d.classify(signature: a, motionScore: 0, blurry: false),
      ViewChangeKind.changed,
    );
    expect(
      d.classify(signature: a, motionScore: 0, blurry: false),
      ViewChangeKind.stationary,
    );
    final b = SceneSignature.fromDetections(const [
      Detection(label: 'tv', score: 0.9, cx: 0.2, cy: 0.4, width: 0.3, height: 0.25),
      Detection(label: 'person', score: 0.9, cx: 0.7, cy: 0.5, width: 0.2, height: 0.4),
    ]);
    expect(
      d.classify(signature: b, motionScore: 0, blurry: false),
      ViewChangeKind.settling,
    );
    expect(
      d.classify(signature: b, motionScore: 0, blurry: false),
      ViewChangeKind.changed,
    );
  });
}
