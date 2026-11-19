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

/// READ: online detailed (Gemini/backend) or offline OCR — never refuse.
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
  bool _saidOfflineNotice = false;
  late final AutoTorchController _torch;
  bool _torchIcon = false;

  @override
  void initState() {
    super.initState();
    _torch = AutoTorchController(ref.read(orienteHostProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  bool _canUseDetailed() {
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

    final online = _canUseDetailed();
    if (!online && !widget.shortLabel) {
      final msg = _saidOfflineNotice
          ? 'Basic reading, offline.'
          : 'I can read it for you. With internet, I can read it in more detail.';
      _saidOfflineNotice = true;
      await host.speak(msg);
    } else {
      await host.speak(
        widget.shortLabel
            ? 'Reading the label. Hold steady.'
            : 'Reading. Fill the frame with the page. Hold still.',
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
        _status = 'Hold still… capturing';
      });
      await host.setKeepScreenOn(true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await host.speak('Hold still.');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _captureAndRead();
    } catch (e) {
      setState(() => _status = 'Camera failed: $e');
      await host.speak('Could not open the camera.');
    }
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
      setState(() => _status = 'Working…');
      final jpeg = await s.grabJpeg(maxEdge: 1280);

      String? onlineText;
      final wantOnline = !widget.shortLabel && _canUseDetailed();

      if (wantOnline && jpeg != null) {
        try {
          onlineText = await ref
              .read(geminiVisionClientProvider)
              .readPage(jpeg: jpeg)
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          onlineText = null;
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
      }

      await host.playEarcon('thinkingStop');

      String text;
      if (onlineText != null && onlineText.trim().isNotEmpty) {
        text = onlineText.trim();
      } else {
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
      try {
        final text = _frames?.ocrFullText.trim() ?? '';
        if (text.isEmpty) {
          await host.speak('I could not read any text.');
          return;
        }
        _paragraphs = _splitParagraphs(text);
        _index = 0;
        await _speakFrom(0);
      } catch (_) {
        await host.speak('I could not read any text.');
      }
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
    for (var i = start; i < _paragraphs.length; i++) {
      if (!mounted || _paused) {
        _index = i;
        return;
      }
      final cmd = ref.read(appControllerProvider).readCommand;
      if (cmd != null) {
        ref.read(appControllerProvider.notifier).clearReadCommand();
        if (cmd == 'pause' || cmd == 'stop') {
          _paused = true;
          _index = i;
          return;
        }
        if (cmd == 'resume') {
          _paused = false;
        }
        if (cmd == 'next' && i + 1 < _paragraphs.length) {
          i++;
        }
        if (cmd == 'previous' && i > 0) {
          i--;
        }
      }
      _index = i;
      setState(() => _status = _paragraphs[i]);
      await host.speak(_paragraphs[i], interrupt: true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await host.speak('End of text.');
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: !_ready
          ? OrbStatusScaffold(
              title: 'Read text',
              status: _status,
              onStop: _stop,
            )
          : Stack(
              children: [
                CameraTaskScaffold(
                  title: 'Read text',
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
