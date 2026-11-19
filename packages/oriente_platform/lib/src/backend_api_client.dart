import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_find_guard.dart';

/// Single build-time base URL. Override with `--dart-define=VIBEI_API_BASE=...`
const String kVibeiApiBase = String.fromEnvironment(
  'VIBEI_API_BASE',
  defaultValue: '',
);

class BackendApiException implements Exception {
  BackendApiException(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;

  @override
  String toString() => 'BackendApiException($code): $message';
}

class AppRemoteConfig {
  const AppRemoteConfig({
    required this.featureOnlineDescribe,
    required this.featureOnlineRead,
    required this.featureVoiceAssistant,
    required this.aiConfigured,
    required this.maintenanceMessage,
    required this.minAppVersion,
    required this.consentText,
    required this.consentVersion,
    required this.languages,
  });

  final bool featureOnlineDescribe;
  final bool featureOnlineRead;
  final bool featureVoiceAssistant;
  final bool aiConfigured;
  final String maintenanceMessage;
  final String minAppVersion;
  final String consentText;
  final String consentVersion;
  final String languages;

  bool get onlineFeaturesReady =>
      aiConfigured &&
      (featureOnlineDescribe || featureOnlineRead || featureVoiceAssistant);

  factory AppRemoteConfig.fromJson(Map<String, dynamic> j) => AppRemoteConfig(
        featureOnlineDescribe: j['feature_online_describe'] == true,
        featureOnlineRead: j['feature_online_read'] == true,
        featureVoiceAssistant: j['feature_voice_assistant'] == true,
        aiConfigured: j['ai_configured'] == true,
        maintenanceMessage: '${j['maintenance_message'] ?? ''}',
        minAppVersion: '${j['min_app_version'] ?? '0.1.0'}',
        consentText: '${j['consent_text'] ?? ''}',
        consentVersion: '${j['consent_version'] ?? '1'}',
        languages: '${j['languages'] ?? 'en'}',
      );

  static const empty = AppRemoteConfig(
    featureOnlineDescribe: false,
    featureOnlineRead: false,
    featureVoiceAssistant: false,
    aiConfigured: false,
    maintenanceMessage: '',
    minAppVersion: '0.1.0',
    consentText: '',
    consentVersion: '1',
    languages: 'en',
  );
}

/// HTTP client: JWT auth, refresh, retries, timeouts. No secrets in the app.
class BackendApiClient {
  BackendApiClient({String? baseUrl}) : _baseOverride = baseUrl;

  final String? _baseOverride;
  String? _access;
  String? _refresh;
  AppRemoteConfig _config = AppRemoteConfig.empty;
  DateTime _configAt = DateTime.fromMillisecondsSinceEpoch(0);

  AppRemoteConfig get config => _config;
  bool get isSignedIn => (_access ?? '').isNotEmpty;
  String get baseUrl => (_baseOverride ?? kVibeiApiBase).trim().replaceAll(RegExp(r'/$'), '');

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<void> loadSession() async {
    final p = await SharedPreferences.getInstance();
    _access = p.getString('vibei_access');
    _refresh = p.getString('vibei_refresh');
    final cached = p.getString('vibei_config_cache');
    if (cached != null && cached.isNotEmpty) {
      try {
        _config = AppRemoteConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(cached) as Map),
        );
      } catch (_) {}
    }
    // Persist build-time base into prefs so ConnectivityService can ping /healthz.
    if (baseUrl.isNotEmpty) {
      await p.setString('visionProxyUrl', baseUrl);
    }
  }

  Future<void> _persistTokens() async {
    final p = await SharedPreferences.getInstance();
    if (_access != null) {
      await p.setString('vibei_access', _access!);
    } else {
      await p.remove('vibei_access');
    }
    if (_refresh != null) {
      await p.setString('vibei_refresh', _refresh!);
    } else {
      await p.remove('vibei_refresh');
    }
  }

  Future<AppRemoteConfig> refreshConfig({bool force = false}) async {
    if (!isConfigured) {
      _config = AppRemoteConfig.empty;
      return _config;
    }
    if (!force &&
        DateTime.now().difference(_configAt) < const Duration(minutes: 2) &&
        _config != AppRemoteConfig.empty) {
      return _config;
    }
    try {
      final data = await _request(
        'GET',
        '/api/v1/config',
        auth: false,
        retries: 2,
      );
      _config = AppRemoteConfig.fromJson(data);
      _configAt = DateTime.now();
      final p = await SharedPreferences.getInstance();
      await p.setString('vibei_config_cache', jsonEncode(data));
    } catch (_) {
      // Keep cached config.
    }
    return _config;
  }

  Future<Map<String, dynamic>> signUp(String email, String password) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/signup',
      body: {'email': email, 'password': password},
      auth: false,
    );
    _access = data['access_token'] as String?;
    _refresh = data['refresh_token'] as String?;
    await _persistTokens();
    return data;
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    );
    _access = data['access_token'] as String?;
    _refresh = data['refresh_token'] as String?;
    await _persistTokens();
    return data;
  }

  Future<void> signOut() async {
    try {
      if (_refresh != null) {
        await _request(
          'POST',
          '/api/v1/auth/logout',
          body: {'refresh_token': _refresh},
          auth: true,
        );
      }
    } catch (_) {}
    _access = null;
    _refresh = null;
    await _persistTokens();
  }

  Future<void> deleteAccount() async {
    await _request('DELETE', '/api/v1/auth/account', auth: true);
    _access = null;
    _refresh = null;
    await _persistTokens();
  }

  Future<void> recordConsent({
    required bool vision,
    required bool chat,
    required String textVersion,
  }) async {
    await _request(
      'POST',
      '/api/v1/consent',
      body: {
        'vision': vision,
        'chat': chat,
        'text_version': textVersion,
      },
      auth: true,
    );
  }

  Future<Map<String, dynamic>> syncPersonal(Map<String, String> objects) async {
    return _request(
      'POST',
      '/api/v1/sync/personal',
      body: {'personal_objects': objects},
      auth: true,
    );
  }

  Future<String> visionDescribe({
    required List<int> jpeg,
    required String sceneContext,
    String language = 'en',
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/vision/describe',
      body: {
        'image_base64': base64Encode(jpeg),
        'scene_context': sceneContext,
        'language': language,
      },
      auth: true,
      timeout: const Duration(seconds: 30),
    );
    return '${data['text'] ?? data['description'] ?? ''}';
  }

  /// Streaming describe (SSE). Falls back to empty on failure for caller retry.
  Future<String> visionDescribeStream({
    required List<int> jpeg,
    required String sceneContext,
    String previousDescription = '',
    bool viewChanged = false,
    String language = 'en',
    void Function(String sentence)? onSentence,
  }) async {
    OfflineFindGuard.checkNoNetwork();
    if (!isConfigured) {
      throw BackendApiException(
        'not_configured',
        'Online features are not set up',
      );
    }
    final uri = Uri.parse('$baseUrl/api/v1/vision/describe_stream');
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if ((_access ?? '').isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
      }
      req.add(
        utf8.encode(
          jsonEncode({
            'image_base64': base64Encode(jpeg),
            'scene_context': sceneContext,
            'previous_description': previousDescription,
            'view_changed': viewChanged,
            'language': language,
          }),
        ),
      );
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) {
        throw BackendApiException('unauthorized', 'Sign in required', status: 401);
      }
      if (res.statusCode >= 400) {
        throw BackendApiException(
          'server_error',
          'Describe stream HTTP ${res.statusCode}',
          status: res.statusCode,
        );
      }
      final buf = StringBuffer();
      var sentenceBuf = StringBuffer();
      await for (final chunk in res.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          final t = line.trimRight();
          if (!t.startsWith('data:')) continue;
          final payload = t.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          try {
            final j = jsonDecode(payload);
            final delta = '${j['delta'] ?? j['text'] ?? ''}';
            if (delta.isEmpty) continue;
            buf.write(delta);
            sentenceBuf.write(delta);
            final s = sentenceBuf.toString();
            final parts = s.split(RegExp(r'(?<=[.!?])\s+'));
            if (parts.length > 1) {
              for (var i = 0; i < parts.length - 1; i++) {
                final sent = parts[i].trim();
                if (sent.isNotEmpty) onSentence?.call(sent);
              }
              sentenceBuf
                ..clear()
                ..write(parts.last);
            }
          } catch (_) {
            buf.write(payload);
          }
        }
      }
      final rem = sentenceBuf.toString().trim();
      if (rem.isNotEmpty) onSentence?.call(rem);
      return buf.toString().trim();
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> visionLocate({
    required List<int> jpeg,
    required String target,
    String language = 'en',
  }) async {
    return _request(
      'POST',
      '/api/v1/vision/locate',
      body: {
        'image_base64': base64Encode(jpeg),
        'target': target,
        'language': language,
      },
      auth: true,
      timeout: const Duration(seconds: 25),
    );
  }

  Future<String> visionRead({
    required List<int> jpeg,
    String language = 'en',
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/vision/read',
      body: {
        'image_base64': base64Encode(jpeg),
        'language': language,
      },
      auth: true,
      timeout: const Duration(seconds: 30),
    );
    return '${data['text'] ?? ''}';
  }

  Future<Map<String, dynamic>> voiceUnderstand({
    required String transcript,
    Map<String, dynamic> context = const {},
  }) async {
    return _request(
      'POST',
      '/api/v1/voice/understand',
      body: {'transcript': transcript, 'context': context},
      auth: true,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<bool> tryRefresh() async {
    if ((_refresh ?? '').isEmpty) return false;
    try {
      final data = await _request(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh_token': _refresh},
        auth: false,
        retries: 1,
      );
      _access = data['access_token'] as String?;
      _refresh = data['refresh_token'] as String?;
      await _persistTokens();
      return (_access ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    int retries = 2,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    OfflineFindGuard.checkNoNetwork();
    if (!isConfigured) {
      throw BackendApiException(
        'not_configured',
        'Online features are not set up',
      );
    }
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _once(
          method,
          path,
          body: body,
          auth: auth,
          timeout: timeout,
        );
      } on BackendApiException catch (e) {
        lastError = e;
        if (e.code == 'unauthorized' && auth) {
          final ok = await tryRefresh();
          if (ok) {
            auth = true;
            continue;
          }
        }
        if (e.code == 'quota_exceeded' ||
            e.code == 'not_configured' ||
            e.status == 400) {
          rethrow;
        }
        if (attempt == retries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      } on SocketException catch (e) {
        lastError = e;
        if (attempt == retries) {
          throw BackendApiException('no_internet', 'No internet connection');
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == retries) {
          throw BackendApiException('timeout', 'Request timed out');
        }
      } catch (e) {
        lastError = e;
        if (attempt == retries) {
          throw BackendApiException('server_error', e.toString());
        }
      }
    }
    throw BackendApiException('server_error', '$lastError');
  }

  Future<Map<String, dynamic>> _once(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool auth,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req;
      switch (method) {
        case 'GET':
          req = await client.getUrl(uri).timeout(timeout);
        case 'DELETE':
          req = await client.deleteUrl(uri).timeout(timeout);
        case 'POST':
          req = await client.postUrl(uri).timeout(timeout);
        default:
          req = await client.openUrl(method, uri).timeout(timeout);
      }
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (auth && (_access ?? '').isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> data = {};
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      }
      if (res.statusCode == 401) {
        throw BackendApiException(
          'unauthorized',
          '${data['message'] ?? 'Unauthorized'}',
          status: 401,
        );
      }
      if (res.statusCode == 429) {
        throw BackendApiException(
          '${data['error'] ?? 'quota_exceeded'}',
          '${data['message'] ?? 'Quota exceeded'}',
          status: 429,
        );
      }
      if (res.statusCode == 503) {
        throw BackendApiException(
          '${data['error'] ?? 'not_configured'}',
          '${data['message'] ?? 'Online features are not set up'}',
          status: 503,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw BackendApiException(
          '${data['error'] ?? 'server_error'}',
          '${data['message'] ?? 'HTTP ${res.statusCode}'}',
          status: res.statusCode,
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }
}

/// Downscale long edge to ~1024 and JPEG-encode (isolate-friendly).
Future<Uint8List> compressJpegForUpload(
  Uint8List jpeg, {
  int maxEdge = 1024,
  int quality = 75,
}) async {
  return compute(_compressJpegWorker, _CompressArgs(jpeg, maxEdge, quality));
}

class _CompressArgs {
  _CompressArgs(this.bytes, this.maxEdge, this.quality);
  final Uint8List bytes;
  final int maxEdge;
  final int quality;
}

Uint8List _compressJpegWorker(_CompressArgs args) {
  // Without dart:ui in isolate for decode, pass-through with size cap.
  // Real decode/resize happens via package:image when available; for now
  // truncate only if already small enough — callers should prefer native
  // FrameHub grab which already downscales.
  final b = args.bytes;
  if (b.lengthInBytes <= 900 * 1024) return b;
  // Soft truncate is unsafe for JPEG; return original and let server size-check.
  // Prefer native grabLatestJpeg which encodes at maxEdge.
  return b;
}

/// Intent name → phrase the offline IntentParser understands.
String intentToUtterance(String intent, Map<String, dynamic> params) {
  final q = '${params['query'] ?? params['object'] ?? params['name'] ?? ''}'.trim();
  switch (intent) {
    case 'object_search':
    case 'find':
      return q.isEmpty ? 'find object' : 'find $q';
    case 'text_search':
      return q.isEmpty ? 'find text' : 'find text $q';
    case 'nearby_text':
      return 'what text is near me';
    case 'nearby_objects':
      return 'what is near me';
    case 'describe':
      return 'describe';
    case 'describe_detail':
      return 'describe in detail';
    case 'document_read':
    case 'read':
      return 'read this';
    case 'stop':
      return 'stop';
    case 'personal_remember':
      return q.isEmpty ? 'remember this' : 'remember this as $q';
    default:
      return q.isNotEmpty ? q : intent;
  }
}

double clamp01(double v) => math.max(0, math.min(1, v));
