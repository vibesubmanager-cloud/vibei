class Detection {
  const Detection({
    required this.label,
    required this.score,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
  });

  final String label;
  final double score;
  final double cx;
  final double cy;
  final double width;
  final double height;

  factory Detection.fromMap(Map<Object?, Object?> map) {
    return Detection(
      label: map['label'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      cx: (map['cx'] as num?)?.toDouble() ?? 0,
      cy: (map['cy'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
    );
  }
}
