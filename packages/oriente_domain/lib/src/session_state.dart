enum OrienteSessionKind {
  idle,
  listening,
  objectSearch,
  textSearch,
  nearbyText,
  narration,
  identify,
  document,
  personalEnroll,
  stubFeature,
}

class SessionState {
  const SessionState({
    required this.kind,
    this.detail,
    this.error,
  });

  final OrienteSessionKind kind;
  final String? detail;
  final String? error;

  factory SessionState.fromMap(Map<Object?, Object?> map) {
    final name = map['kind'] as String? ?? 'idle';
    return SessionState(
      kind: OrienteSessionKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => OrienteSessionKind.idle,
      ),
      detail: map['detail'] as String?,
      error: map['error'] as String?,
    );
  }

  static const idle = SessionState(kind: OrienteSessionKind.idle);
}
