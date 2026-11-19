import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../services/frame_stream_session.dart';
import '../widgets/design/camera_task_scaffold.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/perf_overlay.dart';

/// Remember the dominant object in view under a spoken personal name.
class PersonalObjectScreen extends ConsumerStatefulWidget {
  const PersonalObjectScreen({super.key, this.suggestedName});

  final String? suggestedName;

  @override
  ConsumerState<PersonalObjectScreen> createState() =>
      _PersonalObjectScreenState();
}

class _PersonalObjectScreenState extends ConsumerState<PersonalObjectScreen> {
  FrameStreamSession? _frames;
  bool _ready = false;
  String _status = 'Point at the object to remember…';
  bool _saving = false;

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
    final name = widget.suggestedName;
    await host.speak(
      name == null || name.isEmpty
          ? 'Personal object. Point at the item, then I will ask for a name.'
          : 'Remembering $name. Point the camera at it.',
    );
    try {
      final session = FrameStreamSession(host);
      await session.start(perfOverlay: ref.read(perfOverlayEnabledProvider));
      if (!mounted) {
        await session.stop();
        return;
      }
      _frames = session;
      setState(() => _ready = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _captureAndSave();
    } catch (e) {
      setState(() => _status = 'Camera failed: $e');
      await host.speak('Could not open the camera.');
    }
  }

  Future<void> _captureAndSave() async {
    if (_saving) return;
    _saving = true;
    final host = ref.read(orienteHostProvider);
    final s = _frames;
    try {
      if (s == null) {
        await host.speak('Camera not ready.');
        return;
      }
      setState(() => _status = 'Detecting…');
      final detections = s.detections;
      if (detections.isEmpty) {
        setState(() => _status = 'No object detected. Try again.');
        await host.speak(
          'I do not see a clear object. Point closer and say remember this again.',
        );
        await ref.read(appControllerProvider.notifier).cancel();
        return;
      }
      final sorted = [...detections]
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      final label = sorted.first.label;
      var name = widget.suggestedName?.trim().toLowerCase() ?? '';
      if (name.isEmpty) {
        name = 'my $label';
      }
      final key = name.replaceFirst(RegExp(r'^my\s+'), '').trim();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('personalObjects');
      final map = <String, String>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          map.addAll(decoded.map((k, v) => MapEntry(k, '$v')));
        } catch (_) {}
      }
      map[key] = label;
      map[name] = label;
      await prefs.setString('personalObjects', jsonEncode(map));
      final client = ref.read(backendApiClientProvider);
      if (client.isSignedIn) {
        try {
          await client.syncPersonal(map);
        } catch (_) {}
      }
      setState(() => _status = 'Remembered $name as $label');
      await host.speak('Got it. I will remember $name as a $label.');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await ref.read(appControllerProvider.notifier).cancel();
    } catch (_) {
      await host.speak('I could not save that object.');
      await ref.read(appControllerProvider.notifier).cancel();
    }
  }

  Future<void> _stop() async {
    await _frames?.stop();
    _frames = null;
    await ref.read(appControllerProvider.notifier).cancel();
  }

  @override
  void dispose() {
    OfflineFindGuard.leave();
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
              title: 'Remember object',
              status: _status,
              onStop: _stop,
            )
          : CameraTaskScaffold(
              title: 'Remember object',
              status: _status,
              onStop: _stop,
              showReticle: true,
              reticleProgress: 0.5,
              preview: const Stack(
                fit: StackFit.expand,
                children: [
                  NativeCameraPreview(),
                  PerfOverlay(),
                ],
              ),
            ),
    );
  }
}
