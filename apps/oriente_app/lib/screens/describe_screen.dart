import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_domain/oriente_domain.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../services/auto_torch.dart';
import '../services/frame_stream_session.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

/// SCENE_DESCRIPTION — offline only.
///
/// Reuses the same FrameHub object-detection stream as OBJECT_SEARCH.
/// No Gemini, backend vision, or internet prompts.
class DescribeScreen extends ConsumerStatefulWidget {
  const DescribeScreen({
    super.key,
    this.continuous = true,
    this.fromMemory = false,
    this.onlineDetail = false, // kept for call-site compat; ignored
  });

  final bool continuous;
  final bool fromMemory;
  final bool onlineDetail;

  @override
  ConsumerState<DescribeScreen> createState() => _DescribeScreenState();
}

class _DescribeScreenState extends ConsumerState<DescribeScreen> {
  static const _owner = 'describe';
  FrameStreamSession? _frames;
  Timer? _timer;
  bool _ready = false;
  bool _requesting = false;
  bool _speakingDescription = false;
  String _status = 'Looking…';
  String _lastSpoken = '';
  String? _pendingText;
  String _viewKey = 'v0';
  ViewMotionState _motionState = ViewMotionState.still;
  final _viewMotion = ViewMotionClassifier(settleMs: 500);
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  int _gen = 0;
  late final AutoTorchController _torch;
  bool _torchIcon = false;
  SceneDescriberState _offlineScene = const SceneDescriberState();
  // Same detector stream as object search; minHits=1 so first speak is prompt.
  final _offlineDescriber = SceneDescriber(minHits: 1);

  @override
  void initState() {
    super.initState();
    _torch = AutoTorchController(ref.read(orienteHostProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final scope = ref.read(activityScopeProvider);
    final claim = await scope.claim(_owner);
    _gen = claim.gen;
    final host = ref.read(orienteHostProvider);
    final ctrl = ref.read(appControllerProvider.notifier);

    if (widget.fromMemory) {
      final mem = ctrl.roomMemorySummary();
      setState(() => _status = mem);
      await scope.sayOwned(
        mem,
        owner: _owner,
        gen: _gen,
        priority: SpeechPriority.userRequested,
        interrupt: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (scope.isActive(_owner, _gen)) await ctrl.cancel();
      return;
    }

    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      await scope.speakOwned(
        'Camera permission is missing.',
        owner: _owner,
        gen: _gen,
      );
      return;
    }

    try {
      final session = FrameStreamSession(host);
      await session.start(perfOverlay: ref.read(perfOverlayEnabledProvider));
      if (!mounted || !scope.isActive(_owner, _gen)) {
        await session.stop();
        return;
      }
      _frames = session;
      _torch.enabled = ref.read(autoFlashlightProvider);
      setState(() => _ready = true);
      await host.setKeepScreenOn(true);
      await host.playEarcon('thinkingStart');
      setState(() => _status = 'Describing…');
      _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        unawaited(_tick());
      });
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (scope.isActive(_owner, _gen)) await _requestDescribe(force: true);
    } catch (_) {
      await scope.speakOwned(
        'Could not open the camera.',
        owner: _owner,
        gen: _gen,
      );
    }
  }

  Future<void> _tick() async {
    final scope = ref.read(activityScopeProvider);
    if (!scope.isActive(_owner, _gen)) return;
    final s = _frames;
    if (!_ready || s == null || s.latest == null) return;

    final brightness = (s.latest?['brightness'] as num?)?.toDouble() ?? 0.5;
    await _torch.onBrightness(brightness);
    if (_torch.torchOn && !_torchIcon && mounted) {
      setState(() => _torchIcon = true);
    }

    final blurry = ((s.latest?['sharpness'] as num?)?.toDouble() ?? 1) < 8;
    final detections = s.detections;
    final sig = SceneSignature.fromDetections(
      detections,
      brightness: brightness,
    );
    final prev = _motionState;
    _motionState = _viewMotion.update(
      signature: sig,
      motionScore: s.motionScore,
      blurry: blurry,
    );

    if (!_speakingDescription && _pendingText != null) {
      final next = _pendingText!;
      _pendingText = null;
      await _speakFull(next);
      return;
    }

    if (_speakingDescription || _requesting) return;
    if (_motionState == ViewMotionState.moving) return;

    final viewChanged =
        prev != ViewMotionState.newView && _motionState == ViewMotionState.newView;
    final settledStill = _motionState == ViewMotionState.still;
    final elapsed = DateTime.now().difference(_lastRequest);

    if ((viewChanged || settledStill) &&
        elapsed >= const Duration(seconds: 4)) {
      await _requestDescribe(force: viewChanged);
    }
  }

  Future<void> _requestDescribe({bool force = false}) async {
    final scope = ref.read(activityScopeProvider);
    if (!scope.isActive(_owner, _gen) || _requesting) return;
    final host = ref.read(orienteHostProvider);

    _requesting = true;
    _lastRequest = DateTime.now();
    _viewKey = 'v${DateTime.now().millisecondsSinceEpoch}';
    try {
      await host.playEarcon('thinkingStart');

      final brightness =
          (_frames?.latest?['brightness'] as num?)?.toDouble() ?? 0.5;
      final String text;
      if (brightness < 0.12) {
        text = 'The image is too dark to identify the surroundings clearly. '
            'Try pointing your camera towards more light.';
      } else {
        text = _offlineDescribeOnce(force: force);
      }

      if (!scope.isActive(_owner, _gen)) return;
      await host.playEarcon('thinkingStop');

      if (text.trim().isEmpty) {
        // Stay in session — try again on next settle; do not go home.
        return;
      }

      if (_speakingDescription) {
        _pendingText = text.trim();
      } else {
        await _speakFull(text.trim());
      }
    } finally {
      _requesting = false;
    }
  }

  /// Offline narrative from the same detector boxes OBJECT_SEARCH uses.
  String _offlineDescribeOnce({bool force = false}) {
    final detections = _frames?.detections ?? const [];
    _offlineScene = _offlineDescriber.ingest(_offlineScene, detections);
    if (force) {
      _offlineScene = _offlineDescriber.onViewChanged(_offlineScene);
    }
    final stable = _offlineDescriber.stable(_offlineScene);
    if (stable.isEmpty) {
      return 'I cannot identify any objects clearly in front of you. '
          'Try moving your camera slowly.';
    }
    if (force || !widget.continuous) {
      final summary = _offlineDescriber.summarize(stable);
      if (summary.trim().isEmpty) {
        return 'I cannot identify any objects clearly in front of you. '
            'Try moving your camera slowly.';
      }
      final seeded = {..._offlineScene.said};
      for (final s in summary
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)) {
        seeded.add(s.toLowerCase());
      }
      _offlineScene = _offlineScene.copyWith(said: seeded);
      return summary;
    }
    final result = _offlineDescriber.updateSpeech(_offlineScene);
    _offlineScene = result.state;
    return result.speech?.trim() ?? '';
  }

  Future<void> _speakFull(String text) async {
    final scope = ref.read(activityScopeProvider);
    if (!scope.isActive(_owner, _gen)) return;
    _speakingDescription = true;
    setState(() {
      _status = text;
      _lastSpoken = text;
    });
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final speech = ref.read(speechQueueProvider);
    speech.resume();
    for (final s in sentences) {
      if (!scope.isActive(_owner, _gen)) break;
      await speech.say(
        s,
        priority: SpeechPriority.userRequested,
        viewKey: _viewKey,
        interrupt: false,
      );
      while (speech.queue.isSpeaking || speech.queue.pendingCount > 0) {
        if (!scope.isActive(_owner, _gen)) break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    _speakingDescription = false;
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    await _torch.end();
    await ref.read(activityScopeProvider).stop();
    await _frames?.stop();
    _frames = null;
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_torch.end());
    unawaited(_frames?.stop() ?? Future<void>.value());
    try {
      unawaited(ref.read(activityScopeProvider).stop());
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appControllerProvider.select((s) => s.keepLookingAck),
      (prev, next) {
        if (next != null && next != prev) {
          unawaited(_requestDescribe(force: true));
        }
      },
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: !_ready
          ? OrbStatusScaffold(
              title: 'Surroundings',
              status: _status,
              onStop: _stop,
            )
          : Stack(
              children: [
                CameraTaskScaffold(
                  title: 'Surroundings',
                  status: _lastSpoken.isNotEmpty ? _lastSpoken : _status,
                  onStop: _stop,
                  showReticle: false,
                  preview: const Stack(
                    fit: StackFit.expand,
                    children: [
                      NativeCameraPreview(),
                      PerfOverlay(),
                    ],
                  ),
                ),
                if (_torchIcon)
                  const Positioned(
                    top: 56,
                    right: 20,
                    child: Icon(
                      Icons.flashlight_on,
                      color: Colors.amber,
                      size: 28,
                    ),
                  ),
              ],
            ),
    );
  }
}
