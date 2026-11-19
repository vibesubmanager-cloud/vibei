/// Ensures FIND paths (object / text / personal) make zero network calls.
class OfflineFindGuard {
  OfflineFindGuard._();

  static int _depth = 0;
  static int networkAttemptsWhileFind = 0;

  static bool get active => _depth > 0;

  static void enter() => _depth++;

  static void leave() {
    if (_depth > 0) _depth--;
  }

  static Future<T> runAsync<T>(Future<T> Function() body) async {
    enter();
    try {
      return await body();
    } finally {
      leave();
    }
  }

  static void checkNoNetwork() {
    if (!active) return;
    networkAttemptsWhileFind++;
    throw StateError(
      'Network call blocked during offline FIND (attempts=$networkAttemptsWhileFind)',
    );
  }

  static void resetCounters() {
    networkAttemptsWhileFind = 0;
  }
}
