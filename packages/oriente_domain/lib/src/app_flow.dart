/// Explicit app navigation state machine: HOME → LISTENING → EXECUTING → HOME.
enum AppFlowState {
  home,
  listening,
  executing,
}

enum ExecutingKind {
  search,
  textSearch,
  nearbyText,
  nearbyObjects,
  personal,
  describe,
  read,
  settings,
}

enum AppFlowEvent {
  tapListen,
  cancelListen,
  startSearch,
  startDescribe,
  startRead,
  openSettings,
  stop,
  taskComplete,
  silenceWarn,
  silenceTimeout,
}

class AppFlowTransition {
  const AppFlowTransition({
    required this.next,
    this.executing,
    this.playListeningStarted = false,
    this.playListeningEnded = false,
    this.announceStillListening = false,
  });

  final AppFlowState next;
  final ExecutingKind? executing;
  final bool playListeningStarted;
  final bool playListeningEnded;
  final bool announceStillListening;
}

/// Pure state machine — unit-tested; UI/controller mirrors these transitions.
class AppFlowMachine {
  const AppFlowMachine();

  AppFlowTransition reduce({
    required AppFlowState state,
    ExecutingKind? executing,
    required AppFlowEvent event,
  }) {
    switch (state) {
      case AppFlowState.home:
        switch (event) {
          case AppFlowEvent.tapListen:
            return const AppFlowTransition(
              next: AppFlowState.listening,
              playListeningStarted: true,
            );
          case AppFlowEvent.openSettings:
            return const AppFlowTransition(
              next: AppFlowState.executing,
              executing: ExecutingKind.settings,
            );
          case AppFlowEvent.stop:
          case AppFlowEvent.cancelListen:
          case AppFlowEvent.taskComplete:
            return const AppFlowTransition(next: AppFlowState.home);
          default:
            return AppFlowTransition(next: state, executing: executing);
        }

      case AppFlowState.listening:
        switch (event) {
          case AppFlowEvent.cancelListen:
          case AppFlowEvent.stop:
            return const AppFlowTransition(
              next: AppFlowState.home,
              playListeningEnded: true,
            );
          case AppFlowEvent.silenceWarn:
            return AppFlowTransition(
              next: AppFlowState.listening,
              announceStillListening: true,
            );
          case AppFlowEvent.silenceTimeout:
            return const AppFlowTransition(
              next: AppFlowState.home,
              playListeningEnded: true,
            );
          case AppFlowEvent.startSearch:
            return const AppFlowTransition(
              next: AppFlowState.executing,
              executing: ExecutingKind.search,
            );
          case AppFlowEvent.startDescribe:
            return const AppFlowTransition(
              next: AppFlowState.executing,
              executing: ExecutingKind.describe,
            );
          case AppFlowEvent.startRead:
            return const AppFlowTransition(
              next: AppFlowState.executing,
              executing: ExecutingKind.read,
            );
          case AppFlowEvent.openSettings:
            return const AppFlowTransition(
              next: AppFlowState.executing,
              executing: ExecutingKind.settings,
            );
          default:
            return const AppFlowTransition(next: AppFlowState.listening);
        }

      case AppFlowState.executing:
        switch (event) {
          case AppFlowEvent.stop:
          case AppFlowEvent.taskComplete:
            return const AppFlowTransition(
              next: AppFlowState.home,
              playListeningEnded: true,
            );
          default:
            return AppFlowTransition(next: state, executing: executing);
        }
    }
  }
}
