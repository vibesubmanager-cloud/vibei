import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../services/auto_torch.dart';
import '../services/frame_stream_session.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

/// Full-screen search using shared FrameHub stream (no takePicture).
class ObjectSearchScreen extends ConsumerStatefulWidget {
  const ObjectSearchScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<ObjectSearchScreen> createState() => _ObjectSearchScreenState();
}

class _ObjectSearchScreenState extends ConsumerState<ObjectSearchScreen> {
  FrameStreamSession? _frames;
  Timer? _timer;
  bool _busy = false;
  bool _ready = false;
  String _status = 'Starting camera…';
  List<DetectionBox> _boxes = const [];
  final _engine = SearchGuidanceEngine();
  SpeechThrottleState _speech = const SpeechThrottleState();
  bool _hadTarget = false;
  double _lastArea = 0;
  DateTime _huntStart = DateTime.now();
  bool _reachedPlayed = false;
  DateTime _lastLocate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _locateInFlight = false;
  bool _saidCableNeedsNet = false;
  List<DetectionBox> _onlineHints = const [];
  late final AutoTorchController _torch;
  bool _torchIcon = false;

  @override
  void initState() {
    super.initState();
    _torch = AutoTorchController(ref.read(orienteHostProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    OfflineFindGuard.enter();
    OfflineFindGuard.resetCounters();
    final host = ref.read(orienteHostProvider);
    final trace = ref.read(attemptTraceProvider);
    _torch.enabled = ref.read(autoFlashlightProvider);
    await Permission.microphone.request();
    final cam = await Permission.camera.request();
    trace.cameraPermission = cam.isGranted ? 'granted' : 'denied';
    if (!cam.isGranted) {
      setState(() => _status = 'Camera permission needed');
      trace.add('camera_permission', false, 'denied');
      ref.read(attemptTraceProvider.notifier).state = trace;
      await host.speak('I need camera permission.');
      return;
    }
    trace.add('camera_permission', true, 'granted');
    _huntStart = DateTime.now();
    _speech = const SpeechThrottleState();
    try {
      final session = FrameStreamSession(host);
      final perf = ref.read(perfOverlayEnabledProvider);
      await session.start(perfOverlay: perf);
      if (!mounted) {
        await session.stop();
        return;
      }
      _frames = session;
      trace.cameraBound = true;
      trace.detectorStarted = true;
      trace.add('camera_bound', true, 'FrameHub started');
      trace.add('detector', true, 'target=${widget.query}');
      ref.read(attemptTraceProvider.notifier).state = trace;
      setState(() {
        _ready = true;
        _status = 'Looking for ${widget.query}';
      });
      await host.setKeepScreenOn(true);
      await host.setSearchTicks(rateHz: 1, pan: 0);
      // Count frames for 3s.
      var frames = 0;
      final end = DateTime.now().add(const Duration(seconds: 3));
      _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        unawaited(_tick());
        if (DateTime.now().isBefore(end) && (_frames?.latest != null)) {
          frames++;
          trace.framesIn3s = frames;
          ref.read(attemptTraceProvider.notifier).state = trace;
        }
      });
    } catch (e) {
      trace.add('camera_bound', false, '$e');
      ref.read(attemptTraceProvider.notifier).state = trace;
      setState(() => _status = 'Camera failed: $e');
      await host.speak('I need camera permission');
    }
  }

  bool _isTargetLabel(String label) {
    final q = widget.query.toLowerCase();
    final l = label.toLowerCase().replaceAll('_', ' ');
    if (l.contains(q) || q.contains(l)) return true;
    if (SupportedObjects.isCableQuery(widget.query) &&
        SupportedObjects.isCableQuery(label)) {
      return true;
    }
    return false;
  }

  DetectionFrame _frameFromSession(FrameStreamSession s) {
    final boxes = [
      ...s.detections.map((d) {
        return DetectionBox(
          label: d.label,
          score: d.score,
          cx: d.cx,
          cy: d.cy,
          width: d.width,
          height: d.height,
          isTarget: _isTargetLabel(d.label),
        );
      }),
      ..._onlineHints,
    ];
    // NMS-ish: drop online hint if offline already has nearby target.
    final merged = <DetectionBox>[];
    for (final b in boxes) {
      final dup = merged.any(
        (m) =>
            m.isTarget &&
            b.isTarget &&
            (m.cx - b.cx).abs() < 0.15 &&
            (m.cy - b.cy).abs() < 0.15,
      );
      if (!dup) merged.add(b);
    }
    final has = merged.any((b) => b.isTarget);
    return DetectionFrame(
      detections: merged,
      hasTarget: has,
      targetLabel: has
          ? merged.firstWhere((b) => b.isTarget).label
          : null,
    );
  }

  /// FIND is offline-only — zero network calls (final addendum).
  Future<void> _maybeOnlineLocate(FrameStreamSession s) async {
    return;
  }

  Future<void> _tick() async {
    final s = _frames;
    if (!_ready || s == null || _busy) return;
    if (s.latest == null) return;
    _busy = true;
    try {
      unawaited(_maybeOnlineLocate(s));
      final frame = _frameFromSession(s);
      if (!mounted) return;
      setState(() {
        _boxes = frame.detections;
        _status = frame.hasTarget
            ? 'Found ${frame.targetLabel ?? widget.query}'
            : 'Looking for ${widget.query}…';
      });
      await _guide(frame);
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Detecting… (${widget.query})');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _guide(DetectionFrame frame) async {
    final host = ref.read(orienteHostProvider);
    final ui = ref.read(appControllerProvider);
    final muted = ui.speechMuted;
    if (ui.keepLookingAck != null && _speech.saidNotFound60) {
      _speech = _speech.copyWith(saidNotFound60: false);
      _huntStart = DateTime.now();
    }
    DetectionBox? target;
    for (final d in frame.detections) {
      if (d.isTarget) {
        target = d;
        break;
      }
    }
    final cx = target?.cx ?? 0.5;
    final area = target == null ? 0.0 : target.width * target.height;
    final improving = frame.hasTarget && area >= _lastArea - 0.01;
    final result = _engine.step(
      query: widget.query,
      hasTarget: frame.hasTarget,
      cx: cx,
      area: area,
      hadTargetBefore: _hadTarget,
      improving: improving,
      huntingFor: DateTime.now().difference(_huntStart),
      speech: _speech.copyWith(muted: muted),
      now: DateTime.now(),
    );
    _speech = result.speech;
    final snap = result.snap;

    await host.setSearchTicks(rateHz: snap.ticksPerSecond, pan: snap.pan);

    if (snap.playLostTone) {
      _reachedPlayed = false;
      await host.playEarcon('error');
    }
    if (snap.phase == SearchTickPhase.reached && !_reachedPlayed) {
      _reachedPlayed = true;
      await host.playEarcon('reached');
    } else if (snap.phase != SearchTickPhase.reached) {
      _reachedPlayed = false;
    }
    if (frame.hasTarget && !_hadTarget) {
      await host.playEarcon('found');
    }

    final brightness =
        (_frames?.latest?['brightness'] as num?)?.toDouble() ?? 0.5;
    await _torch.onBrightness(brightness);
    if (_torch.torchOn && !_torchIcon && mounted) {
      setState(() => _torchIcon = true);
    }

    if (snap.speech != null && !muted) {
      var line = snap.speech!;
      // Prefer exact asked label for found announcements; merge move-closer.
      if (frame.hasTarget && !_hadTarget) {
        final closer = line.toLowerCase().contains('closer');
        line = mergeFoundGuidance(
          queryLabel: widget.query,
          moveCloser: closer,
        );
      }
      ref.read(appControllerProvider.notifier).noteSpokenGuidance(line);
      await ref.read(speechQueueProvider).say(
            line,
            priority: frame.hasTarget && !_hadTarget
                ? SpeechPriority.found
                : SpeechPriority.guidance,
            interrupt: false,
          );
    }

    _hadTarget = frame.hasTarget;
    _lastArea = area;
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _torch.end();
    await ref.read(activityScopeProvider).stop();
    await _frames?.stop();
    _frames = null;
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    OfflineFindGuard.leave();
    _timer?.cancel();
    try {
      unawaited(ref.read(activityScopeProvider).stop());
    } catch (_) {}
    unawaited(_torch.end());
    unawaited(_frames?.stop() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DetectionBox? target;
    for (final b in _boxes) {
      if (b.isTarget) {
        target = b;
        break;
      }
    }
    final dist = target == null
        ? 1.0
        : ((target.cx - 0.5).abs() + (target.cy - 0.5).abs());
    final progress = target == null
        ? 0.28
        : (1.0 - dist.clamp(0.0, 0.7) / 0.7).clamp(0.3, 1.0);
    final found = target != null && dist < 0.18 && target.width > 0.12;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: !_ready
          ? OrbStatusScaffold(
              title: 'Looking for ${widget.query}',
              status: _status,
              onStop: _stop,
              stopLabel: 'Stop',
            )
          : CameraTaskScaffold(
              title: 'Looking for ${widget.query}',
              status: _status,
              onStop: _stop,
              stopLabel: 'Stop',
              stopHint: 'Go back to tap and speak',
              reticleProgress: progress,
              targetFound: found,
              preview: Stack(
                fit: StackFit.expand,
                children: [
                  const NativeCameraPreview(),
                  if (target != null && found)
                    CustomPaint(painter: _TargetOutlinePainter(target)),
                  const PerfOverlay(),
                ],
              ),
            ),
    );
  }
}

/// Soft outline around the found target only (no clutter boxes).
class _TargetOutlinePainter extends CustomPainter {
  _TargetOutlinePainter(this.box);

  final DetectionBox box;

  @override
  void paint(Canvas canvas, Size size) {
    final left = (box.cx - box.width / 2).clamp(0.0, 1.0) * size.width;
    final top = (box.cy - box.height / 2).clamp(0.0, 1.0) * size.height;
    final w = box.width.clamp(0.0, 1.0) * size.width;
    final h = box.height.clamp(0.0, 1.0) * size.height;
    final rect = Rect.fromLTWH(left, top, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(16)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = const Color(0xFF34D399).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _TargetOutlinePainter oldDelegate) =>
      oldDelegate.box != box;
}
