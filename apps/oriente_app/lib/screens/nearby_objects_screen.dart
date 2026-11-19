import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../services/frame_stream_session.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

/// Lists objects currently in view (offline detector via FrameHub).
class NearbyObjectsScreen extends ConsumerStatefulWidget {
  const NearbyObjectsScreen({super.key});

  @override
  ConsumerState<NearbyObjectsScreen> createState() =>
      _NearbyObjectsScreenState();
}

class _NearbyObjectsScreenState extends ConsumerState<NearbyObjectsScreen> {
  FrameStreamSession? _frames;
  Timer? _timer;
  bool _busy = false;
  bool _ready = false;
  String _status = 'Starting camera…';
  List<DetectionBox> _boxes = const [];
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSpoken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    OfflineFindGuard.enter();
    OfflineFindGuard.resetCounters();
    final host = ref.read(orienteHostProvider);
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() => _status = 'Camera permission needed');
      await host.speak('Camera permission is missing.');
      return;
    }
    await host.speak('Nearby objects. Point the camera around you.');
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
        _status = 'Scanning…';
      });
      await host.setKeepScreenOn(true);
      _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
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
      final boxes = s.detections
          .map(
            (d) => DetectionBox(
              label: d.label,
              score: d.score,
              cx: d.cx,
              cy: d.cy,
              width: d.width,
              height: d.height,
              isTarget: false,
            ),
          )
          .toList();
      final frame = DetectionFrame(
        detections: boxes,
        hasTarget: false,
      );
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        if (boxes.isEmpty) {
          _status = 'No objects yet.';
        } else {
          _status = boxes.map((d) => d.label).toSet().join(', ');
        }
      });
      await _speak(frame);
    } catch (_) {
      if (mounted) setState(() => _status = 'Scanning…');
    } finally {
      _busy = false;
    }
  }

  Future<void> _speak(DetectionFrame frame) async {
    final host = ref.read(orienteHostProvider);
    final muted = ref.read(appControllerProvider).speechMuted;
    if (muted || frame.detections.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastSpeak).inMilliseconds < 3500) return;
    final sorted = [...frame.detections]
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final parts = <String>[];
    for (final d in sorted.take(5)) {
      final side = d.cx < 0.38
          ? 'left'
          : d.cx > 0.62
              ? 'right'
              : 'ahead';
      parts.add('${d.label} on the $side');
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
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    OfflineFindGuard.leave();
    _timer?.cancel();
    unawaited(_frames?.stop() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: !_ready
          ? OrbStatusScaffold(
              title: 'Nearby objects',
              status: _status,
              onStop: _stop,
            )
          : CameraTaskScaffold(
              title: 'Nearby objects',
              status: _status,
              onStop: _stop,
              showReticle: false,
              preview: Stack(
                fit: StackFit.expand,
                children: [
                  const NativeCameraPreview(),
                  CustomPaint(painter: _BoxPainter(_boxes)),
                  const PerfOverlay(),
                ],
              ),
            ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes);
  final List<DetectionBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFF0);
      final left = (b.cx - b.width / 2).clamp(0.0, 1.0) * size.width;
      final top = (b.cy - b.height / 2).clamp(0.0, 1.0) * size.height;
      final w = b.width.clamp(0.0, 1.0) * size.width;
      final h = b.height.clamp(0.0, 1.0) * size.height;
      canvas.drawRect(Rect.fromLTWH(left, top, w, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
