enum GuidancePhase { searching, tracking, found, reached }

class GuidanceUpdate {
  const GuidanceUpdate({
    required this.phase,
    required this.proximity,
    this.directionSpeech,
    this.announce,
    this.label,
  });

  final GuidancePhase phase;
  final double proximity;
  final String? directionSpeech;
  final String? announce;
  final String? label;

  factory GuidanceUpdate.fromMap(Map<Object?, Object?> map) {
    final phaseName = map['phase'] as String? ?? 'searching';
    return GuidanceUpdate(
      phase: GuidancePhase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => GuidancePhase.searching,
      ),
      proximity: (map['proximity'] as num?)?.toDouble() ?? 0,
      directionSpeech: map['directionSpeech'] as String?,
      announce: map['announce'] as String?,
      label: map['label'] as String?,
    );
  }
}
