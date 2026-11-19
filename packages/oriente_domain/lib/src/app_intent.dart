/// Offline-routable intents produced by the command parser.
sealed class AppIntent {
  const AppIntent();
}

class ObjectSearchIntent extends AppIntent {
  const ObjectSearchIntent(this.query);
  final String query;
}

class TextSearchIntent extends AppIntent {
  const TextSearchIntent(this.query);
  final String query;
}

class NearbyTextIntent extends AppIntent {
  const NearbyTextIntent();
}

class NearbyObjectsIntent extends AppIntent {
  const NearbyObjectsIntent();
}

class NarrationIntent extends AppIntent {
  const NarrationIntent();
}

/// DESCRIBE_MODE — online Gemini scene description (not offline detector).
class DescribeIntent extends AppIntent {
  const DescribeIntent({this.continuous = true, this.fromMemory = false});

  final bool continuous;
  final bool fromMemory;
}

/// Alias of DESCRIBE_MODE (online Gemini). Kept for older call sites.
class DescribeDetailIntent extends AppIntent {
  const DescribeDetailIntent();
}

/// Object detector + OCR race (e.g. stop sign).
class HybridFindIntent extends AppIntent {
  const HybridFindIntent({
    required this.objectQuery,
    required this.textQuery,
  });
  final String objectQuery;
  final String textQuery;
}

class IdentifyIntent extends AppIntent {
  const IdentifyIntent();
}

class StopSpeakingIntent extends AppIntent {
  const StopSpeakingIntent();
}

class StopLookingIntent extends AppIntent {
  const StopLookingIntent();
}

class KeepLookingIntent extends AppIntent {
  const KeepLookingIntent();
}

class RepeatIntent extends AppIntent {
  const RepeatIntent();
}

/// READ_MODE — online Gemini document understanding + spoken reading.
class DocumentReadIntent extends AppIntent {
  const DocumentReadIntent();
}

class PersonalRememberIntent extends AppIntent {
  const PersonalRememberIntent({this.name});
  final String? name;
}

class StopIntent extends AppIntent {
  const StopIntent();
}

class GoBackIntent extends AppIntent {
  const GoBackIntent();
}

class OpenSettingsIntent extends AppIntent {
  const OpenSettingsIntent();
}

/// Open-ended chat; needs internet + consent.
class OnlineChatIntent extends AppIntent {
  const OnlineChatIntent(this.utterance);
  final String utterance;
}

class ClarifyIntent extends AppIntent {
  const ClarifyIntent(this.question);
  final String question;
}

class UnsupportedIntent extends AppIntent {
  const UnsupportedIntent(this.message);
  final String message;
}
