import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  const m = AppFlowMachine();

  test('HOME → LISTENING → SEARCH → HOME', () {
    var t = m.reduce(
      state: AppFlowState.home,
      event: AppFlowEvent.tapListen,
    );
    expect(t.next, AppFlowState.listening);
    expect(t.playListeningStarted, isTrue);

    t = m.reduce(
      state: AppFlowState.listening,
      event: AppFlowEvent.startSearch,
    );
    expect(t.next, AppFlowState.executing);
    expect(t.executing, ExecutingKind.search);

    t = m.reduce(
      state: AppFlowState.executing,
      executing: ExecutingKind.search,
      event: AppFlowEvent.stop,
    );
    expect(t.next, AppFlowState.home);
  });

  test('stop from listening goes home with end earcon', () {
    final t = m.reduce(
      state: AppFlowState.listening,
      event: AppFlowEvent.stop,
    );
    expect(t.next, AppFlowState.home);
    expect(t.playListeningEnded, isTrue);
  });

  test('silence timeout ends listening', () {
    final t = m.reduce(
      state: AppFlowState.listening,
      event: AppFlowEvent.silenceTimeout,
    );
    expect(t.next, AppFlowState.home);
    expect(t.playListeningEnded, isTrue);
  });
}
