import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gemini_vision_client.dart';

/// Single app-wide connectivity: backend health when configured, else general net.
class ConnectivityService {
  ConnectivityService() {
    _start();
  }

  static const _methods = MethodChannel('oriente/methods');
  final _controller = StreamController<bool>.broadcast();
  Timer? _timer;
  bool _online = false;
  bool _debouncing = false;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<bool> get stream => _controller.stream;
  bool get isOnline => _online;

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh({bool afterFailure = false}) async {
    var ok = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      var base = prefs.getString('visionProxyUrl') ?? '';
      if (base.isEmpty && kVibeiApiBase.isNotEmpty) {
        base = kVibeiApiBase;
        await prefs.setString('visionProxyUrl', base);
      }
      if (base.isNotEmpty) {
        final root = base.replaceAll(RegExp(r'/$'), '');
        final health = '$root/healthz';
        final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
          'pingBackend',
          {'url': health},
        );
        ok = raw?['ok'] == true;
      } else if (GeminiVisionClient.isConfigured) {
        // No backend URL: probe public internet so on-device Gemini can run.
        ok = await _probeInternet();
      } else {
        ok = false;
      }
    } catch (_) {
      ok = false;
    }
    if (afterFailure) ok = false;
    _set(ok);
  }

  Future<bool> _probeInternet() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _set(bool next) {
    if (next == _online) return;
    final now = DateTime.now();
    if (now.difference(_lastChange).inMilliseconds < 1200) {
      if (_debouncing) return;
      _debouncing = true;
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        _debouncing = false;
        if (next != _online) {
          _online = next;
          _lastChange = DateTime.now();
          _controller.add(_online);
        }
      });
      return;
    }
    _online = next;
    _lastChange = now;
    _controller.add(_online);
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
