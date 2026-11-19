import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../branding/app_name.dart';
import '../design/theme.dart';
import '../design/theme_controller.dart';
import '../design/tokens.dart';
import '../providers.dart';
import '../widgets/design/components.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _apiBase = TextEditingController();
  String? _authMsg;
  bool _authBusy = false;
  bool _backendBusy = false;
  String? _backendStatus; // Connected / Not connected / …
  bool? _backendOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBackendUrl());
  }

  Future<void> _loadBackendUrl() async {
    final client = ref.read(backendApiClientProvider);
    await client.loadSession();
    if (!mounted) return;
    setState(() {
      _apiBase.text = client.baseUrl.isNotEmpty
          ? client.baseUrl
          : 'https://vibei.onrender.com';
    });
    await _testBackend(silent: true);
  }

  Future<void> _saveAndTestBackend() async {
    setState(() {
      _backendBusy = true;
      _backendStatus = 'Saving…';
    });
    final client = ref.read(backendApiClientProvider);
    await client.setBaseUrl(_apiBase.text.trim());
    await _testBackend();
  }

  Future<void> _testBackend({bool silent = false}) async {
    setState(() {
      _backendBusy = true;
      if (!silent) _backendStatus = 'Checking…';
    });
    final client = ref.read(backendApiClientProvider);
    final ok = await client.pingHealth();
    if (!mounted) return;
    setState(() {
      _backendBusy = false;
      _backendOk = ok;
      _backendStatus = ok
          ? 'Backend connected'
          : 'Backend not connected${client.lastHealthError != null ? ": ${client.lastHealthError}" : ""}';
    });
    if (ok) {
      await ref.read(remoteConfigProvider.notifier).refresh();
      await ref.read(connectivityServiceProvider).refresh();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _apiBase.dispose();
    super.dispose();
  }

  String _onlineStatusLabel(OnlineFeatureStatus s) {
    switch (s) {
      case OnlineFeatureStatus.available:
        return 'Online features: available';
      case OnlineFeatureStatus.notConfigured:
        return 'Online features: not configured';
      case OnlineFeatureStatus.offline:
        return 'Online features: offline';
      case OnlineFeatureStatus.signedOut:
        return 'Online features: sign in required';
    }
  }

  Future<void> _signIn({required bool signUp}) async {
    setState(() {
      _authBusy = true;
      _authMsg = null;
    });
    final client = ref.read(backendApiClientProvider);
    try {
      if (signUp) {
        await client.signUp(_email.text.trim(), _password.text);
      } else {
        await client.signIn(_email.text.trim(), _password.text);
      }
      final privacy = ref.read(privacySettingsProvider);
      final cfg = await client.refreshConfig(force: true);
      ref.read(remoteConfigProvider.notifier).refresh();
      if (privacy.onlineVisionConsent || privacy.onlineChatConsent) {
        await client.recordConsent(
          vision: privacy.onlineVisionConsent,
          chat: privacy.onlineChatConsent,
          textVersion: cfg.consentVersion,
        );
      }
      setState(() => _authMsg = signUp ? 'Account created.' : 'Signed in.');
    } catch (e) {
      setState(() => _authMsg = e.toString());
    } finally {
      setState(() => _authBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final privacy = ref.watch(privacySettingsProvider);
    final caps = ref.watch(capabilityProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context);
    final onlineStatus = ref.watch(onlineFeatureStatusProvider);
    final client = ref.watch(backendApiClientProvider);

    final veMode = ref.watch(veThemeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const ViveiLogo(height: 36, showWordmark: false),
            const SizedBox(width: 10),
            Text('Settings', style: theme.textTheme.titleLarge),
          ],
        ),
        leading: Semantics(
          button: true,
          label: 'Go back',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            constraints: const BoxConstraints(
              minWidth: VeTokens.targetSecondary,
              minHeight: VeTokens.targetSecondary,
            ),
            onPressed: controller.closeSettings,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Semantics(
            header: true,
            child: Text('Appearance', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          const Text('Theme'),
          const SizedBox(height: 8),
          Semantics(
            label: 'Theme',
            child: SegmentedButton<VeThemeMode>(
              segments: const [
                ButtonSegment(
                  value: VeThemeMode.system,
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: VeThemeMode.dark,
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: VeThemeMode.light,
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: VeThemeMode.highContrast,
                  label: Text('HC'),
                ),
              ],
              selected: {veMode},
              onSelectionChanged: (s) {
                ref.read(veThemeModeProvider.notifier).setMode(s.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (veMode) {
              VeThemeMode.system => 'Follows device light or dark mode.',
              VeThemeMode.dark => 'Dark theme.',
              VeThemeMode.light => 'Light theme.',
              VeThemeMode.highContrast => 'High contrast theme.',
            },
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Backend', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(
                  _backendOk == true
                      ? Icons.check_circle
                      : _backendOk == false
                          ? Icons.error
                          : Icons.cloud_outlined,
                  color: _backendOk == true
                      ? Colors.green
                      : _backendOk == false
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _backendStatus ??
                        (client.isConfigured
                            ? 'Backend URL saved — tap Test'
                            : 'No backend URL yet'),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiBase,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Backend URL (Render)',
              hintText: 'https://vibei.onrender.com',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _backendBusy ? null : _saveAndTestBackend,
                  child: Text(_backendBusy ? 'Working…' : 'Save & test'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _backendBusy ? null : () => _testBackend(),
                  child: const Text('Test only'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'When connected, the app can sync accounts and optional online features.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Online', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(_onlineStatusLabel(onlineStatus)),
          ),
          const SizedBox(height: 12),
          if (!client.isSignedIn) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _authBusy ? null : () => _signIn(signUp: false),
                    child: const Text('Sign in'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _authBusy ? null : () => _signIn(signUp: true),
                    child: const Text('Sign up'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text('Signed in for online features.'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _authBusy
                  ? null
                  : () async {
                      await client.signOut();
                      setState(() => _authMsg = 'Signed out.');
                    },
              child: const Text('Sign out'),
            ),
            TextButton(
              onPressed: _authBusy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete account?'),
                          content: const Text(
                            'Deletes your online account. Offline features stay on this device.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          await client.deleteAccount();
                          setState(() => _authMsg = 'Account deleted.');
                        } catch (e) {
                          setState(() => _authMsg = e.toString());
                        }
                      }
                    },
              child: const Text('Delete account'),
            ),
          ],
          if (_authMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_authMsg!),
            ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Speech', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 12),
          const Text('Speech language'),
          const SizedBox(height: 8),
          Semantics(
            label: 'Speech language',
            child: DropdownButtonFormField<String>(
              value: switch (privacy.speechLanguage) {
                'en-GB' || 'en_GB' => 'en-GB',
                'en-IN' || 'en_IN' => 'en-IN',
                _ => 'en-US',
              },
              items: const [
                DropdownMenuItem(
                  value: 'en-US',
                  child: Text('English (US)'),
                ),
                DropdownMenuItem(
                  value: 'en-GB',
                  child: Text('English (UK)'),
                ),
                DropdownMenuItem(
                  value: 'en-IN',
                  child: Text('English (India)'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(privacySettingsProvider.notifier)
                    .update(privacy.copyWith(speechLanguage: v));
              },
            ),
          ),
          const SizedBox(height: 12),
          Text('Speech rate: ${privacy.speechRate.toStringAsFixed(2)}'),
          Slider(
            value: privacy.speechRate,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: privacy.speechRate.toStringAsFixed(2),
            onChanged: (v) {
              ref
                  .read(privacySettingsProvider.notifier)
                  .update(privacy.copyWith(speechRate: v));
            },
          ),
          Text('Volume: ${privacy.speechVolume.toStringAsFixed(2)}'),
          Slider(
            value: privacy.speechVolume,
            min: 0.2,
            max: 1.0,
            divisions: 8,
            onChanged: (v) {
              ref
                  .read(privacySettingsProvider.notifier)
                  .update(privacy.copyWith(speechVolume: v));
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Camera', style: theme.textTheme.headlineMedium),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto flashlight'),
            subtitle: const Text(
              'Turns the torch on when the scene is too dark during camera tasks.',
            ),
            value: ref.watch(autoFlashlightProvider),
            onChanged: (v) {
              ref.read(autoFlashlightProvider.notifier).set(v);
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Privacy', style: theme.textTheme.headlineMedium),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use online enhancements'),
            subtitle: const Text(
              'When on, richer cloud details may follow offline answers. '
              'Airplane mode still works fully.',
            ),
            value: ref.watch(useOnlineEnhancementsProvider),
            onChanged: (v) {
              ref.read(useOnlineEnhancementsProvider.notifier).set(v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow online vision upgrades'),
            subtitle: const Text(
              'Sends sampled camera frames to your backend only after consent.',
            ),
            value: privacy.onlineVisionConsent,
            onChanged: (v) async {
              final next = privacy.copyWith(onlineVisionConsent: v);
              await ref.read(privacySettingsProvider.notifier).update(next);
              final c = ref.read(backendApiClientProvider);
              if (c.isSignedIn) {
                try {
                  await c.recordConsent(
                    vision: next.onlineVisionConsent,
                    chat: next.onlineChatConsent,
                    textVersion: c.config.consentVersion,
                  );
                } catch (_) {}
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow online conversational answers'),
            value: privacy.onlineChatConsent,
            onChanged: (v) async {
              final next = privacy.copyWith(onlineChatConsent: v);
              await ref.read(privacySettingsProvider.notifier).update(next);
              final c = ref.read(backendApiClientProvider);
              if (c.isSignedIn) {
                try {
                  await c.recordConsent(
                    vision: next.onlineVisionConsent,
                    chat: next.onlineChatConsent,
                    textVersion: c.config.consentVersion,
                  );
                } catch (_) {}
              }
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Developer', style: theme.textTheme.headlineMedium),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Performance overlay'),
            subtitle: const Text('FPS, detection/OCR latency, memory, motion.'),
            value: ref.watch(perfOverlayEnabledProvider),
            onChanged: (v) {
              ref.read(perfOverlayEnabledProvider.notifier).set(v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last attempt trace'),
            subtitle: const Text(
              'Recognizer → parse → navigation → camera checks, plus type-a-command.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(showAttemptTraceProvider.notifier).state = true;
            },
          ),
          Builder(
            builder: (context) {
              final log = ref.watch(commandLogProvider);
              final stopMs = ref.watch(lastStopLatencyMsProvider);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Command log\n'
                  'Heard: ${log.heard.isEmpty ? "—" : log.heard}\n'
                  'Parsed: ${log.parsed.isEmpty ? "—" : log.parsed}\n'
                  'Phase: ${log.phase}\n'
                  'Error: ${log.error.isEmpty ? "—" : log.error}\n'
                  'Stop latency: ${stopMs == null ? "—" : "$stopMs ms"}',
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
          FutureBuilder<bool>(
            future: SharedPreferences.getInstance()
                .then((p) => p.getBool('detectionRecorderEnabled') ?? false),
            builder: (context, snap) {
              final on = snap.data ?? false;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Record detection sequences'),
                subtitle: const Text(
                  'Saves real FrameHub detections during Describe for fixtures.',
                ),
                value: on,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('detectionRecorderEnabled', v);
                  (context as Element).markNeedsBuild();
                },
              );
            },
          ),
          FutureBuilder<bool>(
            future: SharedPreferences.getInstance()
                .then((p) => p.getBool('ocrDebug') ?? false),
            builder: (context, snap) {
              final on = snap.data ?? false;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('OCR debug overlay'),
                subtitle: const Text('Shows raw OCR text on Find Text screens.'),
                value: on,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('ocrDebug', v);
                  (context as Element).markNeedsBuild();
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child:
                Text('Search feedback', style: theme.textTheme.headlineMedium),
          ),
          Consumer(
            builder: (context, ref, _) {
              final fb = ref.watch(feedbackPrefsProvider);
              return Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Search tick sound'),
                    value: fb.tickSound,
                    onChanged: (v) {
                      ref
                          .read(feedbackPrefsProvider.notifier)
                          .update(fb.copyWith(tickSound: v));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Search vibration'),
                    value: fb.vibration,
                    onChanged: (v) {
                      ref
                          .read(feedbackPrefsProvider.notifier)
                          .update(fb.copyWith(vibration: v));
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Camera source', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose phone camera or smart glasses for $kAppName. After pairing '
            'glasses you can customize glass buttons.',
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Change phone / glasses',
            outlined: true,
            onPressed: () {
              ref.read(forceDevicePickerProvider.notifier).state = true;
              controller.closeSettings();
            },
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Offline models', style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 8),
          caps.when(
            data: (c) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.spokenSummary),
                const SizedBox(height: 8),
                Text(
                  c.voskReady
                      ? 'Vosk offline speech: installed.'
                      : 'Vosk offline speech: not installed. '
                          'Using system speech recognition when available. '
                          'Download is a stub in this build.',
                ),
                Text(
                  c.detectorReady
                      ? 'Object detector: ready.'
                      : 'Object detector: missing.',
                ),
              ],
            ),
            loading: () => const Text('Checking models…'),
            error: (e, _) => Text('Could not read capabilities: $e'),
          ),
          const SizedBox(height: 24),
          const Text(
            'STUB: model download UI will speak progress in a later step.',
          ),
        ],
      ),
    );
  }
}
