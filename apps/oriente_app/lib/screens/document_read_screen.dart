import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../services/auto_torch.dart';
import '../services/frame_stream_session.dart';
import '../services/gemini_vision_client.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

/// READ_MODE — Gemini document understanding + spoken reading with pause/resume.
///
/// Does not use object detection. Primary path is Gemini (or backend AI).
/// Offline OCR is only a last-resort fallback when online is unavailable after
/// the user was already guided; if online is clearly unavailable at start,
/// we explain that internet is required.
class DocumentReadScreen extends ConsumerStatefulWidget {
  const DocumentReadScreen({super.key, this.shortLabel = false});

  final bool shortLabel;

  @override
  ConsumerState<DocumentReadScreen> createState() => _DocumentReadScreenState();
}

class _DocumentReadScreenState extends ConsumerState<DocumentReadScreen> {
  FrameStreamSession? _frames;
  bool _ready = false;
  String _status = 'Line up the page…';
  List<String> _paragraphs = const [];
  int _index = 0;
  bool _paused = false;
  bool _captured = false;
  bool _speaking = false;
  late final AutoTorchController _torch;
  bool _torchIcon = false;

  @override
  void initState() {
    super.initState();
    _torch = AutoTorchController(ref.read(orienteHostProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  bool _canUseOnline() {
    final online = ref.read(connectivityOnlineProvider);
    final privacy = ref.read(privacySettingsProvider);
    final status = ref.read(onlineFeatureStatusProvider);
    return online &&
        privacy.onlineVisionConsent &&
        status == OnlineFeatureStatus.available &&
        (GeminiVisionClient.isConfigured ||
            ref.read(backendApiClientProvider).isConfigured);
  }

  Future<void> _boot() async {
    final host = ref.read(orienteHostProvider);
    _torch.enabled = ref.read(autoFlashlightProvider);
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() => _status = 'Camera permission needed');
      await host.speak('Camera permission is missing.');
      return;
    }

    final online = _canUseOnline();
    if (!online && !widget.shortLabel) {
      await host.speak(
        'Read mode needs an internet connection to read documents with Gemini. '
        'Find text still works offline if you are looking for a specific word.',
      );
      setState(() => _status = 'Internet required');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await ref.read(appControllerProvider.notifier).cancel();
      return;
    }

    await host.speak(
      widget.shortLabel
          ? 'Reading the label. Hold steady.'
          : 'Of course. Please bring your camera closer to the paper and '
              'position it so the entire page is visible. Try to keep the paper '
              'steady and make sure there is enough light.',
    );

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
        _status = 'Hold still… capturing';
      });
      await host.setKeepScreenOn(true);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await _waitForUsableFrame();
      await _captureAndRead();
    } catch (e) {
      setState(() => _status = 'Camera failed');
      await host.speak('Could not open the camera.');
    }
  }

  Future<void> _waitForUsableFrame() async {
    final host = ref.read(orienteHostProvider);
    final s = _frames;
    if (s == null) return;

    for (var i = 0; i < 6; i++) {
      if (!mounted) return;
      final brightness =
          (s.latest?['brightness'] as num?)?.toDouble() ?? 0.5;
      final sharpness =
          (s.latest?['sharpness'] as num?)?.toDouble() ?? 12;
      await _torch.onBrightness(brightness);
      if (_torch.torchOn && mounted) setState(() => _torchIcon = true);

      if (brightness < 0.14) {
        await host.speak(
          'The image appears too dark. Try moving towards better lighting.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 900));
        continue;
      }
      if (sharpness < 6) {
        await host.speak('Please hold your phone steady.');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        continue;
      }
      // Frame is reasonably usable.
      return;
    }
    await host.speak('Hold still. Capturing now.');
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<String?> _onlineRead(List<int> jpeg) async {
    String? onlineText;
    if (GeminiVisionClient.isConfigured) {
      try {
        onlineText = await ref
            .read(geminiVisionClientProvider)
            .readPage(jpeg: jpeg)
            .timeout(const Duration(seconds: 35));
      } catch (_) {
        onlineText = null;
      }
    }
    if ((onlineText == null || onlineText.trim().isEmpty) &&
        ref.read(backendApiClientProvider).isConfigured) {
      final cloud = ref.read(cloudVisionProvider);
      if (cloud is BackendCloudVisionProvider) {
        try {
          onlineText = await cloud.readPage(jpeg: jpeg);
        } catch (_) {
          onlineText = null;
        }
      }
    }
    return onlineText?.trim();
  }

  Future<void> _captureAndRead() async {
    if (_captured) return;
    _captured = true;
    final host = ref.read(orienteHostProvider);
    final s = _frames;
    if (s == null) return;

    try {
      final brightness =
          (s.latest?['brightness'] as num?)?.toDouble() ?? 0.5;
      await _torch.onBrightness(brightness);
      if (_torch.torchOn && mounted) setState(() => _torchIcon = true);

      await host.playEarcon('thinkingStart');
      setState(() => _status = 'Reading with Gemini…');
      final jpeg = await s.grabJpeg(maxEdge: 1280);

      String? onlineText;
      if (jpeg != null && jpeg.isNotEmpty && _canUseOnline()) {
        onlineText = await _onlineRead(jpeg);
      }

      await host.playEarcon('thinkingStop');

      String text;
      if (onlineText != null && onlineText.isNotEmpty) {
        text = onlineText;
      } else if (widget.shortLabel) {
        // Label mode may use offline OCR.
        text = s.ocrFullText.trim();
        if (text.isEmpty && jpeg != null) {
          final frame = await host.recognizeText(jpeg);
          text = frame.fullText.trim();
        }
        if (text.isEmpty) {
          await host.speak(
            'I could not read any text. Try again with more light.',
          );
          setState(() => _status = 'No text found');
          return;
        }
      } else {
        await host.speak(
          'I could not read the page with Gemini. '
          'Please try again with a clearer, well-lit view of the full page.',
        );
        setState(() => _status = 'Read failed');
        return;
      }

      _paragraphs = _splitParagraphs(text);
      _index = 0;
      setState(
        () => _status =
            text.length > 160 ? '${text.substring(0, 160)}…' : text,
      );
      await _speakFrom(_index);
    } catch (_) {
      await host.playEarcon('thinkingStop');
      await host.speak(
        'Reading failed. Please try again with better lighting.',
      );
    }
  }

  List<String> _splitParagraphs(String text) {
    final parts = text
        .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
        .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 1) {
      final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
      if (sentences.length > 3) {
        final chunks = <String>[];
        final buf = StringBuffer();
        for (final s in sentences) {
          if (buf.length + s.length > 180 && buf.isNotEmpty) {
            chunks.add(buf.toString().trim());
            buf.clear();
          }
          buf.write('$s ');
        }
        if (buf.isNotEmpty) chunks.add(buf.toString().trim());
        return chunks;
      }
    }
    return parts.isEmpty ? [text.trim()] : parts;
  }

  Future<void> _speakFrom(int start) async {
    final host = ref.read(orienteHostProvider);
    _speaking = true;
    for (var i = start; i < _paragraphs.length; i++) {
      if (!mounted) {
        _index = i;
        _speaking = false;
        return;
      }
      // Drain voice controls without re-sending the page to Gemini.
      final cmd = ref.read(appControllerProvider).readCommand;
      if (cmd != null) {
        ref.read(appControllerProvider.notifier).clearReadCommand();
        if (cmd == 'pause' || cmd == 'stop') {
          _paused = true;
          _index = i;
          _speaking = false;
          if (cmd == 'stop') {
            await host.speak('Stopped reading.');
            await ref.read(appControllerProvider.notifier).cancel();
          } else {
            await host.speak('Paused.');
          }
          return;
        }
        if (cmd == 'resume') {
          _paused = false;
        }
        if (cmd == 'next' && i + 1 < _paragraphs.length) {
          i++;
        } else if (cmd == 'previous' && i > 0) {
          i--;
        }
      }
      if (_paused) {
        _index = i;
        _speaking = false;
        return;
      }
      _index = i;
      setState(() => _status = _paragraphs[i]);
      ref.read(appControllerProvider.notifier).noteSpokenGuidance(_paragraphs[i]);
      await host.speak(_paragraphs[i], interrupt: true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _speaking = false;
    await host.speak('End of text.');
  }

  Future<void> _onResumeListening() async {
    if (!_paused || _speaking) return;
    _paused = false;
    await _speakFrom(_index);
  }

  Future<void> _stop() async {
    _paused = true;
    await _torch.end();
    await _frames?.stop();
    _frames = null;
    await ref.read(orienteHostProvider).stopSpeaking();
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    unawaited(_torch.end());
    unawaited(_frames?.stop() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appControllerProvider.select((s) => s.readCommand),
      (prev, next) {
        if (next == null || next == prev) return;
        if (next == 'resume' && _paused) {
          ref.read(appControllerProvider.notifier).clearReadCommand();
          unawaited(_onResumeListening());
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
              title: 'Read mode',
              status: _status,
              onStop: _stop,
            )
          : Stack(
              children: [
                CameraTaskScaffold(
                  title: 'Read mode',
                  status: _status,
                  onStop: _stop,
                  showReticle: true,
                  reticleProgress: 0.45,
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
