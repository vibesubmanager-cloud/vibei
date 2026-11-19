/// Developer log: last heard text, alternatives, parsed command, UI state, error.
class CommandLogEntry {
  const CommandLogEntry({
    this.heard = '',
    this.alternatives = const [],
    this.parsed = '',
    this.resolved = '',
    this.phase = 'home',
    this.error = '',
    this.at,
  });

  final String heard;
  final List<String> alternatives;
  final String parsed;
  final String resolved;
  final String phase;
  final String error;
  final DateTime? at;

  CommandLogEntry copyWith({
    String? heard,
    List<String>? alternatives,
    String? parsed,
    String? resolved,
    String? phase,
    String? error,
    DateTime? at,
  }) =>
      CommandLogEntry(
        heard: heard ?? this.heard,
        alternatives: alternatives ?? this.alternatives,
        parsed: parsed ?? this.parsed,
        resolved: resolved ?? this.resolved,
        phase: phase ?? this.phase,
        error: error ?? this.error,
        at: at ?? this.at,
      );
}
