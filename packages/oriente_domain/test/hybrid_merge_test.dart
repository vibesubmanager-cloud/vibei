import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const m = HybridDescribeMerge();

  test('offline first then only additions; stale dropped', () {
    final offline = 'I see a person sitting on a chair ahead.';
    final online =
        'I see a person sitting on a chair ahead. The chair is wooden. A red mug is on the floor.';
    final add = m.additions(
      offlineSentence: offline,
      onlineSentence: online,
      currentViewKey: 'v1',
      resultViewKey: 'v1',
    );
    expect(add, isNotNull);
    expect(add!.toLowerCase(), contains('wooden'));
    expect(add.toLowerCase(), isNot(contains('sitting on a chair ahead')));

    expect(
      m.additions(
        offlineSentence: offline,
        onlineSentence: online,
        currentViewKey: 'v1',
        resultViewKey: 'v2',
      ),
      isNull,
    );
  });
}
