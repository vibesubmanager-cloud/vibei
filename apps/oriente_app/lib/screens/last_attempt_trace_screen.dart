import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/design/components.dart';

class LastAttemptTraceScreen extends ConsumerStatefulWidget {
  const LastAttemptTraceScreen({super.key});

  @override
  ConsumerState<LastAttemptTraceScreen> createState() =>
      _LastAttemptTraceScreenState();
}

class _LastAttemptTraceScreenState
    extends ConsumerState<LastAttemptTraceScreen> {
  final _cmd = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cmd.dispose();
    super.dispose();
  }

  Future<void> _inject() async {
    final text = _cmd.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      // Leave this overlay so Search/camera can mount on screen.
      ref.read(showAttemptTraceProvider.notifier).state = false;
      await ref.read(appControllerProvider.notifier).injectVoiceCommand(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(attemptTraceProvider);
    return ScreenScaffold(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  ref.read(showAttemptTraceProvider.notifier).state = false;
                },
              ),
              Expanded(
                child: Text(
                  'Last attempt trace',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Type a command (same entry as speech):',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cmd,
            decoration: const InputDecoration(
              hintText: 'can you look for a bottle',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _inject(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _inject,
            child: Text(_busy ? 'Running…' : 'Run command'),
          ),
          const SizedBox(height: 20),
          Text('Trace', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          _row('1 Raw partial', t.rawPartial.isNotEmpty, t.rawPartial),
          _row('1 Raw final', t.rawFinal.isNotEmpty, t.rawFinal),
          _row(
            '2 Kotlin→Dart delivered',
            t.steps.any((s) => s.name == 'kotlin_to_dart' && s.ok),
            t.steps
                .where((s) => s.name == 'kotlin_to_dart')
                .map((s) => s.detail)
                .join('; '),
          ),
          _row(
            '3 Dart listener',
            t.steps.any((s) => s.name == 'dart_listener' && s.ok),
            'phase=${t.phaseAtReceive}',
          ),
          _row(
            '4 Parsed intent',
            t.intent.isNotEmpty && !t.intent.contains('Clarify'),
            '${t.intent} target=${t.target} norm=${t.normalized}',
          ),
          _row(
            '5 State machine',
            t.flowTransition.contains('accepted'),
            t.flowTransition,
          ),
          _row(
            '6 Navigation',
            t.navCalled && t.navVisible,
            'called=${t.navCalled} visible=${t.navVisible}',
          ),
          _row(
            '7 Camera',
            t.cameraBound && t.framesIn3s > 0,
            'perm=${t.cameraPermission} bound=${t.cameraBound} frames3s=${t.framesIn3s}',
          ),
          _row(
            '8 Detector',
            t.detectorStarted,
            t.detectorStarted ? 'started for ${t.target}' : 'not started',
          ),
          const SizedBox(height: 12),
          ...t.steps.map(
            (s) => ListTile(
              dense: true,
              leading: Icon(
                s.ok ? Icons.check_circle : Icons.cancel,
                color: s.ok ? Colors.green : Colors.red,
              ),
              title: Text(s.name),
              subtitle: Text(
                '${s.at.toIso8601String().substring(11, 19)}  ${s.detail}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, bool ok, String detail) {
    return ListTile(
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle : Icons.cancel,
        color: ok ? Colors.green : Colors.red,
      ),
      title: Text(title),
      subtitle: Text(detail.isEmpty ? '—' : detail),
    );
  }
}
