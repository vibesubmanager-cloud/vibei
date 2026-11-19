import 'dart:typed_data';

import 'backend_api_client.dart';
import 'cloud_vision_provider.dart';

/// Real cloud vision via Flask `/api/v1/vision/*`. Returns null on any failure
/// so callers fall back to offline behavior.
class BackendCloudVisionProvider implements CloudVisionProvider {
  BackendCloudVisionProvider(this.client);
  final BackendApiClient client;

  @override
  Future<CloudDescribeResult?> describeView({
    required List<int> jpeg,
    required Map<String, dynamic> offlineHints,
    required String viewKey,
  }) async {
    if (!client.isConfigured || !client.isSignedIn) return null;
    if (!client.config.aiConfigured || !client.config.featureOnlineDescribe) {
      return null;
    }
    try {
      final compressed = await compressJpegForUpload(
        jpeg is Uint8List ? jpeg : Uint8List.fromList(jpeg),
      );
      final text = await client.visionDescribe(
        jpeg: compressed,
        sceneContext: '${offlineHints['offline'] ?? offlineHints}',
      );
      if (text.trim().isEmpty) return null;
      return CloudDescribeResult(viewKey: viewKey, text: text.trim());
    } on BackendApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<CloudObjectHint>> recognizeUnusualObjects({
    required List<int> jpeg,
    required String query,
  }) async {
    if (!client.isConfigured || !client.isSignedIn) return const [];
    if (!client.config.aiConfigured) return const [];
    try {
      final compressed = await compressJpegForUpload(
        jpeg is Uint8List ? jpeg : Uint8List.fromList(jpeg),
      );
      final data = await client.visionLocate(jpeg: compressed, target: query);
      if (data['found'] != true) return const [];
      final matches = data['matches'];
      if (matches is! List) return const [];
      return matches.map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        final grid = '${map['grid'] ?? 'center'}';
        final (cx, cy) = _gridToCenter(grid);
        return CloudObjectHint(
          label: query,
          cx: cx,
          cy: cy,
          width: 0.18,
          height: 0.18,
          score: (map['confidence'] as num?)?.toDouble() ?? 0.6,
        );
      }).toList();
    } on BackendApiException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static (double, double) _gridToCenter(String grid) {
    final g = grid.toLowerCase();
    final row = g.startsWith('top')
        ? 0
        : g.startsWith('bottom')
            ? 2
            : 1;
    final col = g.contains('left')
        ? 0
        : g.contains('right')
            ? 2
            : 1;
    return ((col + 0.5) / 3.0, (row + 0.5) / 3.0);
  }

  Future<String?> readPage({
    required List<int> jpeg,
    String language = 'en',
  }) async {
    if (!client.isConfigured || !client.isSignedIn) return null;
    if (!client.config.aiConfigured || !client.config.featureOnlineRead) {
      return null;
    }
    try {
      final compressed = await compressJpegForUpload(
        jpeg is Uint8List ? jpeg : Uint8List.fromList(jpeg),
      );
      final text =
          await client.visionRead(jpeg: compressed, language: language);
      return text.trim().isEmpty ? null : text.trim();
    } on BackendApiException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Real voice → structured intent via `/api/v1/voice/understand`.
class BackendVoiceUnderstandingProvider implements VoiceUnderstandingProvider {
  BackendVoiceUnderstandingProvider(this.client);
  final BackendApiClient client;

  @override
  Future<String?> interpret(String utterance) async {
    if (!client.isConfigured || !client.isSignedIn) return null;
    if (!client.config.aiConfigured || !client.config.featureVoiceAssistant) {
      return null;
    }
    try {
      final data = await client.voiceUnderstand(transcript: utterance);
      final intent = '${data['intent'] ?? ''}';
      final params = data['params'] is Map
          ? Map<String, dynamic>.from(data['params'] as Map)
          : <String, dynamic>{};
      final phrase = intentToUtterance(intent, params);
      return phrase.trim().isEmpty ? null : phrase;
    } on BackendApiException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
