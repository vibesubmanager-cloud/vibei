import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:oriente_domain/oriente_domain.dart';

/// Typed host API.
///
/// STUB note: Step 2 uses MethodChannel/EventChannel directly.
/// Pigeon IDL can replace this facade later without changing call sites.
class OrienteHost {
  OrienteHost({
    MethodChannel? methodChannel,
    EventChannel? asrChannel,
    EventChannel? guidanceChannel,
    EventChannel? sessionChannel,
  })  : _methods = methodChannel ??
            const MethodChannel('oriente/methods'),
        _asr = asrChannel ??
            const EventChannel('oriente/asr'),
        _guidance = guidanceChannel ??
            const EventChannel('oriente/guidance'),
        _session = sessionChannel ??
            const EventChannel('oriente/session_state');

  final MethodChannel _methods;
  final EventChannel _asr;
  final EventChannel _guidance;
  final EventChannel _session;

  Stream<String> get asrPartials => _asr
      .receiveBroadcastStream({'mode': 'partial'})
      .map((e) => (e as Map)['text'] as String? ?? '');

  Stream<String> get asrFinals => _asr
      .receiveBroadcastStream({'mode': 'final'})
      .map((e) => (e as Map)['text'] as String? ?? '');

  /// Combined ASR events: maps include `isFinal`, `text`, and `alternatives`.
  Stream<AsrEvent> get asrEvents => _asr.receiveBroadcastStream().map((e) {
        final map = Map<Object?, Object?>.from(e as Map);
        final altsRaw = map['alternatives'];
        final alts = <String>[];
        if (altsRaw is List) {
          for (final a in altsRaw) {
            final s = a?.toString().trim() ?? '';
            if (s.isNotEmpty) alts.add(s);
          }
        }
        final text = map['text'] as String? ?? '';
        if (alts.isEmpty && text.trim().isNotEmpty) {
          alts.add(text.trim());
        }
        return AsrEvent(
          text: text,
          isFinal: map['isFinal'] as bool? ?? false,
          alternatives: alts,
        );
      });

  Stream<GuidanceUpdate> get guidance =>
      _guidance.receiveBroadcastStream().map((e) {
        return GuidanceUpdate.fromMap(Map<Object?, Object?>.from(e as Map));
      });

  Stream<SessionState> get sessions =>
      _session.receiveBroadcastStream().map((e) {
        return SessionState.fromMap(Map<Object?, Object?>.from(e as Map));
      });

  Future<CapabilityReport> getCapabilityReport() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'getOfflineCapabilityReport',
    );
    return CapabilityReport.fromMap(raw ?? const {});
  }

  Future<void> speak(String text, {bool interrupt = true}) {
    return _methods.invokeMethod('speak', {
      'text': text,
      'interrupt': interrupt,
    });
  }

  Future<void> stopSpeaking() {
    return _methods.invokeMethod('stopSpeaking');
  }

  Future<void> setTorch(bool enabled) {
    return _methods.invokeMethod('setTorch', {'enabled': enabled});
  }

  Future<void> duckSpeech({required bool duck}) {
    return _methods.invokeMethod('duckSpeech', {'duck': duck});
  }

  Future<void> setSpeakingText(String text) {
    return _methods.invokeMethod('setSpeakingText', {'text': text});
  }

  Future<void> setSpeechRate(double rate) {
    return _methods.invokeMethod('setSpeechRate', {'rate': rate});
  }

  Future<void> setSpeechVolume(double volume) {
    return _methods.invokeMethod('setSpeechVolume', {'volume': volume});
  }

  Future<void> startListening({bool taskMode = false}) {
    return _methods.invokeMethod('startListening', {'taskMode': taskMode});
  }

  Future<void> stopListening() {
    return _methods.invokeMethod('stopListening');
  }

  Future<void> setTaskListening(bool enabled) {
    return _methods.invokeMethod('setTaskListening', {'enabled': enabled});
  }

  Future<void> playEarcon(String name) {
    return _methods.invokeMethod('playEarcon', {'name': name});
  }

  Future<void> setSearchTicks({required double rateHz, double pan = 0}) {
    return _methods.invokeMethod('setSearchTicks', {
      'rateHz': rateHz,
      'pan': pan,
    });
  }

  Future<void> setAudioFeedbackPrefs({
    required bool tickSound,
    required bool vibration,
  }) {
    return _methods.invokeMethod('setAudioFeedbackPrefs', {
      'tickSound': tickSound,
      'vibration': vibration,
    });
  }

  Future<void> vibrate(int ms) {
    return _methods.invokeMethod('vibrate', {'ms': ms});
  }

  Future<void> setKeepScreenOn(bool enabled) {
    return _methods.invokeMethod('setKeepScreenOn', {'enabled': enabled});
  }

  Stream<Map<String, dynamic>> get frameEvents =>
      const EventChannel('oriente/frames').receiveBroadcastStream().map((e) {
        return Map<String, dynamic>.from(e as Map);
      });

  Future<bool> startFramePipeline({bool perfOverlay = false}) async {
    return await _methods.invokeMethod<bool>('startFramePipeline', {
          'perfOverlay': perfOverlay,
        }) ??
        false;
  }

  Future<void> stopFramePipeline() {
    return _methods.invokeMethod('stopFramePipeline');
  }

  Future<Map<String, dynamic>> getPipelinePerf() async {
    final raw =
        await _methods.invokeMethod<Map<Object?, Object?>>('getPipelinePerf');
    return Map<String, dynamic>.from(raw ?? const {});
  }

  /// JPEG from the shared FrameHub analysis session (no Flutter takePicture).
  Future<Uint8List?> grabLatestJpeg({int maxEdge = 1024, int quality = 75}) async {
    final raw = await _methods.invokeMethod<Uint8List>(
      'grabLatestJpeg',
      {'maxEdge': maxEdge, 'quality': quality},
    );
    return raw;
  }

  Future<Map<String, dynamic>?> grabLatestFrame() async {
    final raw =
        await _methods.invokeMethod<Map<Object?, Object?>>('grabLatestFrame');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<bool> pingBackend(String url) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'pingBackend',
      {'url': url},
    );
    return raw?['ok'] == true;
  }

  Future<void> startObjectSearch(String query) {
    return _methods.invokeMethod('startObjectSearch', {'query': query});
  }

  /// Run on-device detection on a JPEG frame (for camera preview pages).
  Future<DetectionFrame> detectObjects(List<int> jpeg, {String query = ''}) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'detectObjects',
      {
        'jpeg': Uint8List.fromList(jpeg),
        'query': query,
      },
    );
    return DetectionFrame.fromMap(raw ?? const {});
  }

  /// On-device OCR. Optional [query] highlights matching lines (`isMatch`).
  /// Pass [rotationDegrees] when known; otherwise native reads JPEG EXIF.
  Future<OcrFrame> recognizeText(
    List<int> jpeg, {
    String query = '',
    int rotationDegrees = -1,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'recognizeText',
      {
        'jpeg': Uint8List.fromList(jpeg),
        'query': query,
        'rotationDegrees': rotationDegrees,
      },
    );
    return OcrFrame.fromMap(raw ?? const {});
  }

  Future<void> cancel() {
    return _methods.invokeMethod('cancel');
  }

  Future<PrivacySettings> getPrivacySettings() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'getPrivacySettings',
    );
    return PrivacySettings.fromMap(raw ?? const {});
  }

  Future<void> setPrivacySettings(PrivacySettings settings) {
    return _methods.invokeMethod('setPrivacySettings', settings.toMap());
  }

  Future<void> setSpeechBiasing(List<String> phrases) {
    return _methods.invokeMethod('setSpeechBiasing', {'phrases': phrases});
  }

  /// Features not yet implemented announce as stubs.
  Future<void> announceStub(String featureName) {
    return speak(
      '$featureName is a stub in this build. Object Search is available. '
      'Say stop to go home.',
    );
  }

  // —— Camera source / XSX smart glasses ——

  Stream<Map<String, dynamic>> get glassesEvents =>
      const EventChannel('oriente/glasses').receiveBroadcastStream().map((e) {
        return Map<String, dynamic>.from(e as Map);
      });

  Future<String> getCameraSource() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('getCameraSource');
    return raw?['source'] as String? ?? 'phone';
  }

  Future<void> setCameraSource(String source) {
    return _methods.invokeMethod('setCameraSource', {'source': source});
  }

  Future<Map<String, dynamic>> initGlassesSdk() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('initGlassesSdk');
    return Map<String, dynamic>.from(raw ?? const {});
  }

  Future<bool> glassesStartScan() async {
    return await _methods.invokeMethod<bool>('glassesStartScan') ?? false;
  }

  Future<void> glassesStopScan() {
    return _methods.invokeMethod('glassesStopScan');
  }

  Future<bool> glassesBind({required String name, required String address}) async {
    return await _methods.invokeMethod<bool>('glassesBind', {
          'name': name,
          'address': address,
        }) ??
        false;
  }

  Future<void> glassesDisconnect() => _methods.invokeMethod('glassesDisconnect');

  Future<void> glassesUnbind() => _methods.invokeMethod('glassesUnbind');

  Future<void> glassesAutoConnect() => _methods.invokeMethod('glassesAutoConnect');

  Future<Map<String, dynamic>> glassesStatus() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('glassesStatus');
    return Map<String, dynamic>.from(raw ?? const {});
  }

  Future<bool> glassesPullConfig() async {
    return await _methods.invokeMethod<bool>('glassesPullConfig') ?? false;
  }

  Future<bool> glassesStartLiveVideo() async {
    return await _methods.invokeMethod<bool>('glassesStartLiveVideo') ?? false;
  }

  Future<void> glassesStopLiveVideo() =>
      _methods.invokeMethod('glassesStopLiveVideo');

  Future<bool> glassesApplyButtons(Map<String, String> mapping) async {
    return await _methods.invokeMethod<bool>('glassesApplyButtons', mapping) ??
        false;
  }
}

class AsrEvent {
  const AsrEvent({
    required this.text,
    required this.isFinal,
    this.alternatives = const [],
  });
  final String text;
  final bool isFinal;
  final List<String> alternatives;
}

class DetectionBox {
  const DetectionBox({
    required this.label,
    required this.score,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.isTarget,
  });

  final String label;
  final double score;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final bool isTarget;

  factory DetectionBox.fromMap(Map<Object?, Object?> map) {
    return DetectionBox(
      label: map['label'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      cx: (map['cx'] as num?)?.toDouble() ?? 0.5,
      cy: (map['cy'] as num?)?.toDouble() ?? 0.5,
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
      isTarget: map['isTarget'] as bool? ?? false,
    );
  }
}

class DetectionFrame {
  const DetectionFrame({
    required this.detections,
    required this.hasTarget,
    this.targetLabel,
  });

  final List<DetectionBox> detections;
  final bool hasTarget;
  final String? targetLabel;

  factory DetectionFrame.fromMap(Map<Object?, Object?> map) {
    final raw = map['detections'];
    final list = <DetectionBox>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(DetectionBox.fromMap(Map<Object?, Object?>.from(item)));
        }
      }
    }
    return DetectionFrame(
      detections: list,
      hasTarget: map['hasTarget'] as bool? ?? false,
      targetLabel: map['targetLabel'] as String?,
    );
  }
}

class OcrBox {
  const OcrBox({
    required this.text,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.isMatch,
    this.confidence = 0.5,
  });

  final String text;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final bool isMatch;
  final double confidence;

  OcrBox copyWith({bool? isMatch}) => OcrBox(
        text: text,
        cx: cx,
        cy: cy,
        width: width,
        height: height,
        isMatch: isMatch ?? this.isMatch,
        confidence: confidence,
      );

  factory OcrBox.fromMap(Map<Object?, Object?> map) {
    return OcrBox(
      text: map['text'] as String? ?? '',
      cx: (map['cx'] as num?)?.toDouble() ?? 0.5,
      cy: (map['cy'] as num?)?.toDouble() ?? 0.5,
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
      isMatch: map['isMatch'] as bool? ?? false,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class OcrFrame {
  const OcrFrame({
    required this.boxes,
    required this.fullText,
    required this.hasMatch,
    this.rotationApplied = 0,
  });

  final List<OcrBox> boxes;
  final String fullText;
  final bool hasMatch;
  final int rotationApplied;

  factory OcrFrame.fromMap(Map<Object?, Object?> map) {
    final raw = map['boxes'];
    final list = <OcrBox>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(OcrBox.fromMap(Map<Object?, Object?>.from(item)));
        }
      }
    }
    return OcrFrame(
      boxes: list,
      fullText: map['fullText'] as String? ?? '',
      hasMatch: map['hasMatch'] as bool? ?? false,
      rotationApplied: map['rotationApplied'] as int? ?? 0,
    );
  }
}
