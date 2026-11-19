import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../widgets/design/components.dart';

const _actions = <(String id, String label)>[
  ('listen', 'Tap & speak'),
  ('find', 'Object search'),
  ('cancel', 'Cancel / stop'),
  ('photo', 'Take photo'),
  ('video', 'Record video'),
  ('audio', 'Record audio'),
];

/// Customize glass button gestures and sync to the headset via XSX SDK.
class GlassesConfigScreen extends ConsumerStatefulWidget {
  const GlassesConfigScreen({
    super.key,
    required this.onDone,
    this.embedded = false,
  });

  final VoidCallback onDone;
  final bool embedded;

  @override
  ConsumerState<GlassesConfigScreen> createState() =>
      _GlassesConfigScreenState();
}

class _GlassesConfigScreenState extends ConsumerState<GlassesConfigScreen> {
  String leftSingle = 'listen';
  String leftDouble = 'find';
  String leftLong = 'cancel';
  String rightSingle = 'photo';
  String rightDouble = 'video';
  String rightLong = 'audio';
  String _status = 'Customize glass buttons, then save.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      await ref.read(orienteHostProvider).speak(
            'Glass settings. Choose what each button does, then double tap '
            'Save to glasses.',
          );
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      leftSingle = prefs.getString('glass_leftSingle') ?? leftSingle;
      leftDouble = prefs.getString('glass_leftDouble') ?? leftDouble;
      leftLong = prefs.getString('glass_leftLong') ?? leftLong;
      rightSingle = prefs.getString('glass_rightSingle') ?? rightSingle;
      rightDouble = prefs.getString('glass_rightDouble') ?? rightDouble;
      rightLong = prefs.getString('glass_rightLong') ?? rightLong;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Saving button layout to glasses…';
    });
    final host = ref.read(orienteHostProvider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('glass_leftSingle', leftSingle);
    await prefs.setString('glass_leftDouble', leftDouble);
    await prefs.setString('glass_leftLong', leftLong);
    await prefs.setString('glass_rightSingle', rightSingle);
    await prefs.setString('glass_rightDouble', rightDouble);
    await prefs.setString('glass_rightLong', rightLong);

    final ok = await host.glassesApplyButtons({
      'leftSingle': leftSingle,
      'leftDouble': leftDouble,
      'leftLong': leftLong,
      'rightSingle': rightSingle,
      'rightDouble': rightDouble,
      'rightLong': rightLong,
    });
    await host.glassesPullConfig();

    setState(() {
      _busy = false;
      _status = ok
          ? 'Buttons saved to glasses.'
          : 'Saved in VIBEI. Glasses sync failed — reconnect and try again.';
    });
    await host.speak(_status, interrupt: true);
    if (ok) widget.onDone();
  }

  String _labelFor(String id) =>
      _actions.firstWhere((a) => a.$1 == id, orElse: () => (id, id)).$2;

  Future<void> _pick(String field) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Choose action',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              for (final a in _actions)
                ListTile(
                  title: Text(a.$2, style: Theme.of(context).textTheme.bodyLarge),
                  onTap: () => Navigator.pop(context, a.$1),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return;
    setState(() {
      switch (field) {
        case 'leftSingle':
          leftSingle = chosen;
        case 'leftDouble':
          leftDouble = chosen;
        case 'leftLong':
          leftLong = chosen;
        case 'rightSingle':
          rightSingle = chosen;
        case 'rightDouble':
          rightDouble = chosen;
        case 'rightLong':
          rightLong = chosen;
      }
    });
  }

  Widget _row(String title, String field, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$title, ${_labelFor(value)}',
        hint: 'Double tap to change',
        child: Material(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _pick(field),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Text(
                    _labelFor(value),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFFFFFFF0),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScreenScaffold(
      background: const GlowBackground(),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!widget.embedded)
                    Semantics(
                      button: true,
                      label: 'Continue',
                      child: IconButton(
                        iconSize: 32,
                        onPressed: widget.onDone,
                        icon: const Icon(Icons.check),
                      ),
                    ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Glass buttons',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_status, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    Text('Left button', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    _row('Single tap', 'leftSingle', leftSingle),
                    _row('Double tap', 'leftDouble', leftDouble),
                    _row('Long press', 'leftLong', leftLong),
                    const SizedBox(height: 12),
                    Text('Right button', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    _row('Single tap', 'rightSingle', rightSingle),
                    _row('Double tap', 'rightDouble', rightDouble),
                    _row('Long press', 'rightLong', rightLong),
                  ],
                ),
              ),
              PillButton(
                label: _busy ? 'Saving…' : 'Save to glasses',
                onPressed: _busy ? null : _save,
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Continue',
                outlined: true,
                onPressed: _busy ? null : widget.onDone,
              ),
            ],
      ),
    );
  }
}
