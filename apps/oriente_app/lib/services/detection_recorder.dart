import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Developer-only recorder for real detection sequences (no invented data).
class DetectionRecorder {
  static const prefKey = 'detectionRecorderEnabled';
  static const storeKey = 'detectionRecorderSequences';

  bool enabled = false;
  final List<Map<String, dynamic>> _buf = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(prefKey) ?? false;
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, v);
  }

  void recordFrame({
    required List<Map<String, dynamic>> detections,
    required double motionScore,
    required String viewState,
  }) {
    if (!enabled) return;
    _buf.add({
      't': DateTime.now().toIso8601String(),
      'motion': motionScore,
      'view': viewState,
      'detections': detections,
    });
    if (_buf.length > 400) _buf.removeAt(0);
  }

  Future<void> flush() async {
    if (_buf.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final prev = p.getString(storeKey);
    final list = <dynamic>[];
    if (prev != null && prev.isNotEmpty) {
      try {
        list.addAll(jsonDecode(prev) as List);
      } catch (_) {}
    }
    list.add({
      'savedAt': DateTime.now().toIso8601String(),
      'frames': List<Map<String, dynamic>>.from(_buf),
    });
    // Keep last 5 sessions.
    while (list.length > 5) {
      list.removeAt(0);
    }
    await p.setString(storeKey, jsonEncode(list));
    _buf.clear();
  }

  Future<List<dynamic>> loadFixtures() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(storeKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }
}
