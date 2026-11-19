import 'dart:convert';
import 'dart:io';

import 'package:oriente_platform/oriente_platform.dart';

/// On-device Gemini vision for DESCRIBE_MODE / READ_MODE when configured.
/// Pass key at build time: --dart-define=GEMINI_API_KEY=...
/// Prefer the Flask backend AI key in production so the APK does not embed secrets.
class GeminiVisionClient {
  GeminiVisionClient({
    String? apiKey,
    this.model = kGeminiModel,
  }) : apiKey = apiKey ?? kGeminiApiKey;

  /// From --dart-define=GEMINI_API_KEY=... Never hardcode in source.
  static const kGeminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// Fast multimodal default for accessibility describe/read.
  static const kGeminiModel = 'gemini-3.5-flash-lite';

  final String apiKey;
  final String model;

  static bool get isConfigured => kGeminiApiKey.trim().isNotEmpty;

  static const describePrompt =
      'You are the eyes of a blind person using PathFinder. Describe the complete '
      'camera view in natural spoken English. Cover physical objects, furniture, '
      'electronics, people if visible, doors, windows, paths, signs or writing, '
      'and how things relate (for example items on a desk). Start with hazards or '
      'obstacles when they are clearly visible. Do not invent distances, conditions, '
      'or details that are not visible. Do not only list object labels. Keep it '
      'conversational, useful, and concise for speech. No markdown or bullet lists.';

  static const readPrompt =
      'You are helping a blind person read a document from a camera photo. '
      'Extract all readable text and organize it in correct reading order: '
      'title first, then headings, paragraphs, lists, tables (spoken clearly), '
      'captions, and footnotes. For multi-column layouts, read one column fully '
      'before the next. Preserve meaning exactly — do not invent missing words, '
      'numbers, names, or dates. If a section is illegible, write: '
      '"Some text in this section is unclear." Plain text only, no markdown.';

  Future<String> describe({
    required List<int> jpeg,
    String previousDescription = '',
    bool viewChanged = false,
    bool detailed = false,
    String language = 'en',
  }) async {
    OfflineFindGuard.checkNoNetwork();
    var prompt = describePrompt;
    if (detailed) {
      prompt +=
          '\nBe a bit more detailed while staying spoken and concise.';
    }
    if (previousDescription.isNotEmpty) {
      prompt +=
          '\nPrevious description (do not repeat): $previousDescription';
    }
    if (viewChanged) {
      prompt += '\nThe camera view has changed. Describe the new view fully.';
    }
    if (language.isNotEmpty) {
      prompt += '\nRespond in language: $language';
    }
    return _generate(
      prompt: prompt,
      jpeg: jpeg,
      maxOutputTokens: 280,
    );
  }

  Future<String> readPage({required List<int> jpeg}) async {
    OfflineFindGuard.checkNoNetwork();
    return _generate(
      prompt: readPrompt,
      jpeg: jpeg,
      maxOutputTokens: 1200,
    );
  }

  Future<String> _generate({
    required String prompt,
    required List<int> jpeg,
    int maxOutputTokens = 512,
  }) async {
    OfflineFindGuard.checkNoNetwork();
    if (apiKey.isEmpty) {
      throw StateError('Gemini API key missing');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent',
    );
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(jpeg),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': maxOutputTokens,
        'thinkingConfig': {'thinkingBudget': 0},
      },
    };
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('x-goog-api-key', apiKey);
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 35));
      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) {
        // Retry without thinkingConfig if the model rejects it.
        if (res.statusCode == 400 && raw.toLowerCase().contains('thinking')) {
          return _generateBasic(
            prompt: prompt,
            jpeg: jpeg,
            maxOutputTokens: maxOutputTokens,
          );
        }
        // Never include the API key in error surfaces.
        throw HttpException('Gemini HTTP ${res.statusCode}');
      }
      return _parseText(raw);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _generateBasic({
    required String prompt,
    required List<int> jpeg,
    required int maxOutputTokens,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent',
    );
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(jpeg),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': maxOutputTokens,
      },
    };
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('x-goog-api-key', apiKey);
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 35));
      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) {
        throw HttpException('Gemini HTTP ${res.statusCode}');
      }
      return _parseText(raw);
    } finally {
      client.close(force: true);
    }
  }

  String _parseText(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final cands = data['candidates'] as List? ?? const [];
    if (cands.isEmpty) return '';
    final content = (cands.first as Map)['content'] as Map? ?? const {};
    final parts = content['parts'] as List? ?? const [];
    return parts
        .map((p) => '${(p as Map)['text'] ?? ''}')
        .join('\n')
        .trim();
  }
}
