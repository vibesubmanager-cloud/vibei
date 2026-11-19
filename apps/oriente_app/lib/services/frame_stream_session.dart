import 'dart:async';
import 'dart:typed_data';

import 'package:oriente_domain/oriente_domain.dart';
import 'package:oriente_platform/oriente_platform.dart';

/// Shared FrameHub session for feature screens (no Flutter takePicture).
class FrameStreamSession {
  FrameStreamSession(this.host);

  final OrienteHost host;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Map<String, dynamic>? _latest;
  bool _started = false;

  Map<String, dynamic>? get latest => _latest;

  double get motionScore =>
      (_latest?['motionScore'] as num?)?.toDouble() ?? 0;

  bool get isStill => motionScore < 0.12;

  List<Detection> get detections {
    final raw = _latest?['detections'];
    if (raw is! List) return const [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return Detection(
        label: '${m['label'] ?? ''}',
        score: (m['score'] as num?)?.toDouble() ?? 0,
        cx: (m['cx'] as num?)?.toDouble() ?? 0,
        cy: (m['cy'] as num?)?.toDouble() ?? 0,
        width: (m['width'] as num?)?.toDouble() ?? 0,
        height: (m['height'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  String get ocrFullText => '${_latest?['ocrFullText'] ?? ''}';

  List<Map<String, dynamic>> get ocrBoxes {
    final raw = _latest?['ocrBoxes'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> start({bool perfOverlay = false}) async {
    if (_started) return;
    _started = true;
    await host.startFramePipeline(perfOverlay: perfOverlay);
    _sub = host.frameEvents.listen((e) {
      _latest = e;
    });
    // Warm a couple frames.
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<Uint8List?> grabJpeg({int maxEdge = 1024}) {
    return host.grabLatestJpeg(maxEdge: maxEdge);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    await host.stopFramePipeline();
  }
}
