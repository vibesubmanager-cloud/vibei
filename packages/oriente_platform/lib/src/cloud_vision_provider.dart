/// Cloud vision enhancement interface. Implementations call the app backend only.
abstract class CloudVisionProvider {
  Future<CloudDescribeResult?> describeView({
    required List<int> jpeg,
    required Map<String, dynamic> offlineHints,
    required String viewKey,
  });

  Future<List<CloudObjectHint>> recognizeUnusualObjects({
    required List<int> jpeg,
    required String query,
  });
}

class CloudDescribeResult {
  const CloudDescribeResult({
    required this.viewKey,
    required this.text,
    this.labels = const [],
  });
  final String viewKey;
  final String text;
  final List<String> labels;
}

class CloudObjectHint {
  const CloudObjectHint({
    required this.label,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.score,
  });
  final String label;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final double score;
}

/// Free-form voice → utterance the offline IntentParser understands.
abstract class VoiceUnderstandingProvider {
  Future<String?> interpret(String utterance);
}
