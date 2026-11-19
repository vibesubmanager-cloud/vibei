import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  test('cable synonyms resolve', () {
    expect(SupportedObjects.resolve('cable'), 'cable');
    expect(SupportedObjects.resolve('charging cable'), 'cable');
    expect(SupportedObjects.resolve('USB cable'), 'cable');
    expect(SupportedObjects.resolve('cord'), 'cable');
    expect(SupportedObjects.resolve('wire'), 'cable');
    expect(SupportedObjects.resolve('charger'), 'cable');
    expect(SupportedObjects.isCableQuery('hdmi cable'), isTrue);
  });

  test('merge online and offline cable boxes without duplicates', () {
    // Mirrors object-search merge: nearby same-target dropped.
    final offline = [
      const Detection(
        label: 'cable',
        score: 0.8,
        cx: 0.4,
        cy: 0.5,
        width: 0.2,
        height: 0.1,
      ),
    ];
    final online = [
      const Detection(
        label: 'cable',
        score: 0.7,
        cx: 0.42,
        cy: 0.51,
        width: 0.18,
        height: 0.1,
      ),
      const Detection(
        label: 'cable',
        score: 0.65,
        cx: 0.8,
        cy: 0.3,
        width: 0.15,
        height: 0.1,
      ),
    ];
    final merged = <Detection>[];
    for (final d in [...offline, ...online]) {
      final dup = merged.any(
        (m) => (m.cx - d.cx).abs() < 0.15 && (m.cy - d.cy).abs() < 0.15,
      );
      if (!dup) merged.add(d);
    }
    expect(merged.length, 2);
  });
}
