import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../services/frame_stream_session.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

enum TextVisionMode { search, nearby, read, hybrid }

/// FIND TEXT / nearby text. High-res stills + EXIF-aware OCR.
class TextVisionScreen extends ConsumerStatefulWidget {
  const TextVisionScreen({
    super.key,
    required this.mode,
    this.query,
    this.objectQuery,
  });

  final TextVisionMode mode;
  final String? query;
  final String? objectQuery;

  @override
  ConsumerState<TextVisionScreen> createState() => _TextVisionScreenState();
}

class _TextVisionScreenState extends ConsumerState<TextVisionScreen> {
  FrameStreamSession? _frames;
  Timer? _timer;
  bool _busy = false;
  bool _ready = false;
  String _status = 'Starting camera…';
  List<OcrBox> _boxes = const [];
  List<DetectionBox> _objBoxes = const [];
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSpoken;
  bool _announcedMatch = false;
  bool _saidBlurry = false;
  bool _saidNotFound60 = false;
  bool _saidAlso = false;
  bool _saidDark = false;
  DateTime _huntStart = DateTime.now();
  final _matcher = const TextMatcher();
  String _debugOcr = '';
  bool _showDebug = false;

  String get _title {
    switch (widget.mode) {
      case TextVisionMode.search:
        return 'Looking for text “${widget.query ?? ''}”';
      case TextVisionMode.hybrid:
        return 'Looking for ${widget.objectQuery ?? widget.query}';
      case TextVisionMode.nearby:
        return 'Nearby text';
      case TextVisionMode.read:
        return 'Reading';
    }
  }

  bool get _isHunt =>
      widget.mode == TextVisionMode.search ||
      widget.mode == TextVisionMode.hybrid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    OfflineFindGuard.enter();
    OfflineFindGuard.resetCounters();
    final host = ref.read(orienteHostProvider);
    final prefs = await SharedPreferences.getInstance();
    _showDebug = prefs.getBool('ocrDebug') ?? false;
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() => _status = 'Camera permission needed');
      await host.speak('Camera permission is missing.');
      return;
    }
    // FIND TEXT: no speech while hunting — only ticks.
    if (!_isHunt) {
      await host.speak(
        widget.mode == TextVisionMode.nearby
            ? 'Looking for nearby text.'
            : 'Reading mode.',
      );
    }
    try {
      final session = FrameStreamSession(host);
      await session.start(perfOverlay: ref.read(perfOverlayEnabledProvider));
      if (!mounted) {
        await session.stop();
        return;
      }
      _frames = session;
      setState(() {
        _ready = true;
        _status = _title;
        _huntStart = DateTime.now();
      });
      await host.setKeepScreenOn(true);
      if (_isHunt) {
        await host.setSearchTicks(rateHz: 1, pan: 0);
      }
      _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        unawaited(_tick());
      });
    } catch (e) {
      setState(() => _status = 'Camera failed: $e');
      await host.speak('Could not open the camera.');
    }
  }

  Future<void> _tick() async {
    final s = _frames;
    if (!_ready || s == null || _busy) return;
    if (s.latest == null) return;
    _busy = true;
    try {
      final query = widget.query ?? '';
      var boxes = s.ocrBoxes
          .map((m) => OcrBox.fromMap(Map<Object?, Object?>.from(m)))
          .toList();
      final fullText = s.ocrFullText;
      var hasMatch = false;
      if (query.isNotEmpty) {
        final hits = _matcher.matchAll(
          query,
          boxes.map((b) => b.text).toList(),
        );
        if (hits.isNotEmpty) {
          hasMatch = true;
          final matchedIdx = hits.map((h) => h.boxIndex).toSet();
          boxes = [
            for (var i = 0; i < boxes.length; i++)
              boxes[i].copyWith(isMatch: matchedIdx.contains(i)),
          ];
        }
      }

      List<DetectionBox> objs = const [];
      var objectHit = false;
      if (widget.mode == TextVisionMode.hybrid &&
          (widget.objectQuery ?? '').isNotEmpty) {
        final q = widget.objectQuery!.toLowerCase();
        objs = s.detections.map((d) {
          final label = d.label.toLowerCase();
          final isTarget = label.contains(q) || q.contains(label);
          return DetectionBox(
            label: d.label,
            score: d.score,
            cx: d.cx,
            cy: d.cy,
            width: d.width,
            height: d.height,
            isTarget: isTarget,
          );
        }).toList();
        objectHit = objs.any((b) => b.isTarget);
      }

      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _objBoxes = objs;
        _debugOcr =
            'motion=${s.motionScore.toStringAsFixed(2)} | ${fullText.isEmpty ? "(empty)" : fullText}';
        if (_isHunt) {
          _status = (hasMatch || objectHit)
              ? 'Found'
              : 'Looking for ${widget.query ?? widget.objectQuery}…';
        } else if (fullText.isEmpty) {
          _status = 'No text yet. Move closer.';
        } else {
          _status = fullText.length > 140
              ? '${fullText.substring(0, 140)}…'
              : fullText;
        }
      });

      if (!_saidDark && fullText.isEmpty && boxes.isEmpty) {
        final elapsed = DateTime.now().difference(_huntStart);
        if (elapsed.inSeconds >= 8) {
          _saidDark = true;
          await ref.read(orienteHostProvider).speak(
                'It may be too dark. Try more light.',
              );
        }
      }

      await _guide(
        boxes: boxes,
        hasTextMatch: hasMatch,
        objectHit: objectHit,
        fullText: fullText,
        objs: objs,
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'Reading text…');
    } finally {
      _busy = false;
    }
  }

  String _hPos(double cx) =>
      cx < 0.38 ? 'on the left' : cx > 0.62 ? 'on the right' : 'ahead';

  String _vPos(double cy) =>
      cy < 0.33 ? 'near the top' : cy > 0.66 ? 'near the bottom' : 'in the middle';

  String _dist(double area) => area < 0.04 ? 'far' : area > 0.12 ? 'near' : '';

  Future<void> _guide({
    required List<OcrBox> boxes,
    required bool hasTextMatch,
    required bool objectHit,
    required String fullText,
    required List<DetectionBox> objs,
  }) async {
    final host = ref.read(orienteHostProvider);
    final muted = ref.read(appControllerProvider).speechMuted;
    final now = DateTime.now();
    final huntingFor = now.difference(_huntStart);

    if (_isHunt) {
      if (!hasTextMatch && !objectHit) {
        await host.setSearchTicks(rateHz: 1, pan: 0);
        if (fullText.isNotEmpty && !_saidBlurry && !muted) {
          _saidBlurry = true;
          await host.speak('I can see some text, move closer.');
          _lastSpeak = now;
        }
        if (huntingFor.inSeconds >= 60 && !_saidNotFound60 && !muted) {
          _saidNotFound60 = true;
          final q = widget.query ?? widget.objectQuery ?? 'it';
          await host.speak(
            "I haven't found $q. Say keep looking, or stop.",
          );
          _lastSpeak = now;
        }
        return;
      }

      double cx = 0.5, cy = 0.5, area = 0.1;
      String seen = widget.query ?? 'it';
      if (objectHit) {
        DetectionBox? t;
        for (final d in objs) {
          if (d.isTarget) {
            t = d;
            break;
          }
        }
        if (t != null) {
          cx = t.cx;
          cy = t.cy;
          area = t.width * t.height;
          seen = t.label;
        }
      }
      final matches = boxes.where((b) => b.isMatch).toList()
        ..sort(
          (a, b) => (b.width * b.height * b.confidence)
              .compareTo(a.width * a.height * a.confidence),
        );
      if (matches.isNotEmpty && !objectHit) {
        cx = matches.first.cx;
        cy = matches.first.cy;
        area = matches.first.width * matches.first.height;
        seen = matches.first.text;
      } else if (matches.isNotEmpty && objectHit) {
        // Prefer whichever is larger / more centered — already have object;
        // still use text if bigger.
        final m = matches.first;
        if (m.width * m.height > area) {
          cx = m.cx;
          cy = m.cy;
          area = m.width * m.height;
          seen = m.text;
        }
      }

      final pan = ((cx - 0.5) / 0.5).clamp(-1.0, 1.0);
      final centered = (cx - 0.5).abs() <= 0.12;
      final rate = centered
          ? (3.0 + area.clamp(0, 0.3) / 0.3 * 4).clamp(3.0, 7.0)
          : 2.0;
      await host.setSearchTicks(rateHz: rate, pan: centered ? 0 : pan);

      if (muted) return;
      if (now.difference(_lastSpeak).inMilliseconds < 3000) return;

      String? line;
      if (!_announcedMatch) {
        _announcedMatch = true;
        await host.playEarcon('found');
        final dist = _dist(area);
        line = dist.isEmpty
            ? 'I see "$seen" ${_hPos(cx)}, ${_vPos(cy)}.'
            : 'I see "$seen" ${_hPos(cx)}, ${_vPos(cy)}, $dist.';
        if (matches.length > 1 && !_saidAlso) {
          _saidAlso = true;
          final other = matches[1];
          line = '$line Also ${_hPos(other.cx)}.';
        }
      } else {
        if (cx < 0.38) {
          line = 'Go right';
        } else if (cx > 0.62) {
          line = 'Go left';
        } else if (area < 0.06) {
          line = 'Move closer';
        } else {
          return;
        }
      }
      if (line == _lastSpoken &&
          now.difference(_lastSpeak).inSeconds < 8) {
        return;
      }
      _lastSpoken = line;
      _lastSpeak = now;
      ref.read(appControllerProvider.notifier).noteSpokenGuidance(line);
      await host.speak(line, interrupt: true);
      return;
    }

    // Nearby: sparse read of OCR
    if (boxes.isEmpty || muted) return;
    if (now.difference(_lastSpeak).inMilliseconds < 3500) return;
    final sorted = [...boxes]
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final parts = <String>[];
    for (final b in sorted.take(4)) {
      parts.add('${b.text}, ${_hPos(b.cx)}');
    }
    final line = parts.join('. ');
    if (line == _lastSpoken || line.isEmpty) return;
    _lastSpoken = line;
    _lastSpeak = now;
    ref.read(appControllerProvider.notifier).noteSpokenGuidance(line);
    await host.speak(line, interrupt: true);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _frames?.stop();
    _frames = null;
    await ref.read(orienteHostProvider).setSearchTicks(rateHz: 0);
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    OfflineFindGuard.leave();
    _timer?.cancel();
    try {
      unawaited(ref.read(orienteHostProvider).setSearchTicks(rateHz: 0));
    } catch (_) {}
    unawaited(_frames?.stop() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = _boxes.any((b) => b.isMatch);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: !_ready
          ? OrbStatusScaffold(
              title: _title,
              status: _status,
              onStop: _stop,
            )
          : CameraTaskScaffold(
              title: _title,
              status: _showDebug && _debugOcr.isNotEmpty
                  ? '$_status\n$_debugOcr'
                  : _status,
              onStop: _stop,
              showReticle: true,
              reticleProgress: hasMatch ? 0.85 : 0.4,
              targetFound: hasMatch,
              preview: Stack(
                fit: StackFit.expand,
                children: [
                  const NativeCameraPreview(),
                  CustomPaint(painter: _OcrPainter(_boxes)),
                  if (_objBoxes.isNotEmpty)
                    CustomPaint(painter: _ObjPainter(_objBoxes)),
                  const PerfOverlay(),
                ],
              ),
            ),
    );
  }
}

class _OcrPainter extends CustomPainter {
  _OcrPainter(this.boxes);
  final List<OcrBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.isMatch ? 4 : 2
        ..color = b.isMatch ? const Color(0xFF00E676) : const Color(0xFF40C4FF);
      final left = (b.cx - b.width / 2).clamp(0.0, 1.0) * size.width;
      final top = (b.cy - b.height / 2).clamp(0.0, 1.0) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          left,
          top,
          b.width.clamp(0.0, 1.0) * size.width,
          b.height.clamp(0.0, 1.0) * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OcrPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}

class _ObjPainter extends CustomPainter {
  _ObjPainter(this.boxes);
  final List<DetectionBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.isTarget ? 4 : 2
        ..color = const Color(0xFFFFEA00);
      final left = (b.cx - b.width / 2).clamp(0.0, 1.0) * size.width;
      final top = (b.cy - b.height / 2).clamp(0.0, 1.0) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          left,
          top,
          b.width.clamp(0.0, 1.0) * size.width,
          b.height.clamp(0.0, 1.0) * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ObjPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
