class CapabilityReport {
  const CapabilityReport({
    required this.cameraAvailable,
    required this.detectorReady,
    required this.ocrReady,
    required this.voskReady,
    required this.systemAsrAvailable,
    required this.ttsReady,
    required this.onlineAvailable,
    required this.spokenSummary,
    this.detectorError,
    this.cableDetectorReady = false,
    this.cableDetectorError,
  });

  final bool cameraAvailable;
  final bool detectorReady;
  final bool ocrReady;
  final bool voskReady;
  final bool systemAsrAvailable;
  final bool ttsReady;
  final bool onlineAvailable;
  final String spokenSummary;
  final String? detectorError;
  final bool cableDetectorReady;
  final String? cableDetectorError;

  factory CapabilityReport.fromMap(Map<Object?, Object?> map) {
    return CapabilityReport(
      cameraAvailable: map['cameraAvailable'] as bool? ?? false,
      detectorReady: map['detectorReady'] as bool? ?? false,
      ocrReady: map['ocrReady'] as bool? ?? false,
      voskReady: map['voskReady'] as bool? ?? false,
      systemAsrAvailable: map['systemAsrAvailable'] as bool? ?? false,
      ttsReady: map['ttsReady'] as bool? ?? false,
      onlineAvailable: map['onlineAvailable'] as bool? ?? false,
      spokenSummary: map['spokenSummary'] as String? ??
          'Capability report unavailable.',
      detectorError: map['detectorError'] as String?,
      cableDetectorReady: map['cableDetectorReady'] as bool? ?? false,
      cableDetectorError: map['cableDetectorError'] as String?,
    );
  }
}
