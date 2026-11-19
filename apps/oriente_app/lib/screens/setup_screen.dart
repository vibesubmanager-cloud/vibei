import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oriente_platform/oriente_platform.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../branding/app_name.dart';
import '../providers.dart';
import '../widgets/design/components.dart';

/// First-launch gate: mic, camera, location, then offline models — before home.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

enum _SetupStep { welcome, running, done }

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _SetupStep _step = _SetupStep.welcome;
  String _headline = 'Setup';
  String _status =
      'Before $kAppName starts, we will turn on microphone, camera, '
      'and location, then prepare offline models.';
  bool _busy = false;
  bool _micOk = false;
  bool _camOk = false;
  bool _locOk = false;
  bool _modelsOk = false;
  String _modelsDetail = '';

  OrienteHost get _host => ref.read(orienteHostProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _host.speak(
        'Welcome to $kAppName. Before you start, we will turn on the '
        'microphone, camera, and location, then prepare offline models. '
        'Double tap Continue.',
      );
    });
  }

  Future<void> _advance() async {
    if (_busy) return;
    if (_step == _SetupStep.done) {
      await _finish();
      return;
    }
    setState(() {
      _busy = true;
      _step = _SetupStep.running;
    });
    try {
      await _runFullSetup();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runFullSetup() async {
    // 1. Microphone
    setState(() {
      _headline = '1 / 4  Microphone';
      _status =
          'Microphone. Allow so VIBEI can hear your voice commands.';
    });
    await _host.speak(
      'Microphone. Please allow microphone access so VIBEI can hear you.',
      interrupt: true,
    );
    final mic = await Permission.microphone.request();
    _micOk = mic.isGranted;
    setState(() {
      _status = _micOk ? 'Microphone allowed.' : 'Microphone denied.';
    });
    await _host.speak(
      _micOk ? 'Microphone allowed.' : 'Microphone denied.',
      interrupt: true,
    );

    // 2. Camera
    setState(() {
      _headline = '2 / 4  Camera';
      _status = 'Camera. Allow so VIBEI can find objects around you.';
    });
    await _host.speak(
      'Camera. Please allow camera access for Object Search.',
      interrupt: true,
    );
    final cam = await Permission.camera.request();
    _camOk = cam.isGranted;
    setState(() {
      _status = _camOk ? 'Camera allowed.' : 'Camera denied.';
    });
    await _host.speak(
      _camOk ? 'Camera allowed.' : 'Camera denied.',
      interrupt: true,
    );

    // 3. Location
    setState(() {
      _headline = '3 / 4  Location';
      _status =
          'Location. Optional for this build. Allow to prepare GPS for later.';
    });
    await _host.speak(
      'Location. Optional for this build. Allow if you want GPS ready later.',
      interrupt: true,
    );
    final loc = await Permission.locationWhenInUse.request();
    _locOk = loc.isGranted;
    setState(() {
      _status = _locOk ? 'Location allowed.' : 'Location skipped.';
    });
    await _host.speak(
      _locOk ? 'Location allowed.' : 'Location skipped.',
      interrupt: true,
    );

    // 4. Models
    setState(() {
      _headline = '4 / 4  Models';
      _status = 'Preparing offline models…';
      _modelsDetail = '';
    });
    await _host.speak(
      'Preparing offline models. This may take a moment.',
      interrupt: true,
    );

    final caps = await _host.getCapabilityReport();
    ref.invalidate(capabilityProvider);

    final detector = caps.detectorReady;
    final tts = caps.ttsReady;
    final asr = caps.systemAsrAvailable || caps.voskReady;
    _modelsOk = detector && tts;

    _modelsDetail = [
      detector
          ? 'Object detection model: ready.'
          : (caps.detectorError != null && caps.detectorError!.isNotEmpty
              ? 'Object detection: not ready on this simulator. '
                  '${caps.detectorError}'
              : 'Object detection model: missing.'),
      caps.voskReady
          ? 'Offline speech model: ready.'
          : 'Offline speech pack: not installed yet. '
              'Using system speech recognition for now.',
      tts ? 'Voice feedback: ready.' : 'Voice feedback: not ready.',
      asr
          ? 'Speech input path: available.'
          : 'Speech input path: unavailable on this device.',
    ].join('\n');

    setState(() {
      _step = _SetupStep.done;
      _status = _modelsOk
          ? 'Setup complete. Double tap Start VIBEI.'
          : 'Setup finished with warnings. Double tap Start VIBEI.';
    });
    await _host.speak(_status, interrupt: true);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setupComplete', true);
    await prefs.setBool('permMic', _micOk);
    await prefs.setBool('permCam', _camOk);
    await prefs.setBool('permLoc', _locOk);
    await _host.speak(
      'VIBEI is ready. Tap the big button and speak a request, '
      'for example find a bottle.',
      interrupt: true,
    );
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTap = !_busy;
    final label = switch (_step) {
      _SetupStep.welcome => 'Continue',
      _SetupStep.running => 'Working…',
      _SetupStep.done => 'Start $kAppName',
    };

    return ScreenScaffold(
      background: const GlowBackground(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ViveiLogo(height: 48)),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(_headline, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(_status, style: theme.textTheme.bodyLarge),
          ),
          if (_modelsDetail.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_modelsDetail, style: theme.textTheme.bodyLarge),
          ],
          const Spacer(),
          _PermissionChecklist(
            mic: _micOk,
            camera: _camOk,
            location: _locOk,
            models: _modelsOk,
          ),
          const SizedBox(height: 24),
          if (_busy)
            const SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            PillButton(label: label, onPressed: canTap ? _advance : null),
          if (_step != _SetupStep.welcome) ...[
            const SizedBox(height: 12),
            PillButton(
              label: 'Open system settings',
              outlined: true,
              onPressed: _busy ? null : openAppSettings,
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionChecklist extends StatelessWidget {
  const _PermissionChecklist({
    required this.mic,
    required this.camera,
    required this.location,
    required this.models,
  });

  final bool mic;
  final bool camera;
  final bool location;
  final bool models;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, bool ok) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.radio_button_unchecked,
              color: ok ? const Color(0xFFFFFFF0) : Colors.white54,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Microphone', mic),
        row('Camera', camera),
        row('Location', location),
        row('Offline models', models),
      ],
    );
  }
}
