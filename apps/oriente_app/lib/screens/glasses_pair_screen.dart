import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../design/tokens.dart';
import '../providers.dart';
import '../widgets/design/components.dart';

class GlassDevice {
  GlassDevice({
    required this.name,
    required this.address,
    required this.rssi,
  });

  final String name;
  final String address;
  final int rssi;
}

class GlassesPairScreen extends ConsumerStatefulWidget {
  const GlassesPairScreen({
    super.key,
    required this.onPaired,
    required this.onBack,
  });

  final VoidCallback onPaired;
  final VoidCallback onBack;

  @override
  ConsumerState<GlassesPairScreen> createState() => _GlassesPairScreenState();
}

class _GlassesPairScreenState extends ConsumerState<GlassesPairScreen> {
  static const _owner = 'glasses_pair';
  final Map<String, GlassDevice> _devices = {};
  StreamSubscription? _sub;
  String _status = 'Preparing…';
  bool _scanning = false;
  bool _connecting = false;
  bool _ready = false;
  bool _saidNotFound = false;
  int _gen = 0;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final scope = ref.read(activityScopeProvider);
    final claim = await scope.claim(_owner, onCancel: () async {
      _timeout?.cancel();
      _sub?.cancel();
    });
    _gen = claim.gen;

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
    ].request();
    if (!scope.isActive(_owner, _gen)) return;

    final host = ref.read(orienteHostProvider);
    final init = await host.initGlassesSdk();
    _ready = init['ok'] == true || init['sdkReady'] == true;
    if (!mounted || !scope.isActive(_owner, _gen)) return;

    setState(() {
      _status = _ready
          ? 'Your smart glasses are ready. Scanning for glasses.'
          : 'Could not start glasses. Go back and use the phone.';
    });
    await scope.speakOwned(
      _status,
      owner: _owner,
      gen: _gen,
      interrupt: true,
    );
    if (!_ready || !scope.isActive(_owner, _gen)) return;

    _sub = host.glassesEvents.listen((event) {
      if (!scope.isActive(_owner, _gen)) return;
      final type = event['type'] as String?;
      if (type == 'device') {
        final name = event['name'] as String? ?? '';
        final address = event['address'] as String? ?? '';
        final rssi = (event['rssi'] as num?)?.toInt() ?? 0;
        if (name.isEmpty || address.isEmpty) return;
        setState(() {
          _devices[address] = GlassDevice(
            name: name,
            address: address,
            rssi: rssi,
          );
        });
      } else if (type == 'connection') {
        final state = '${event['state'] ?? ''}';
        setState(() {
          _status = 'Connecting…';
          _connecting = !state.toLowerCase().contains('servicesdiscovered') &&
              !state.toLowerCase().contains('authenticated');
        });
        if (state.toLowerCase().contains('servicesdiscovered') ||
            state.toLowerCase().contains('authenticated')) {
          unawaited(_onConnected());
        }
      }
    });

    await _scan(auto: true);
  }

  Future<void> _onConnected() async {
    final scope = ref.read(activityScopeProvider);
    if (!scope.isActive(_owner, _gen)) return;
    final host = ref.read(orienteHostProvider);
    await host.glassesPullConfig();
    await scope.speakOwned(
      'Glasses connected.',
      owner: _owner,
      gen: _gen,
      interrupt: true,
    );
    if (!scope.isActive(_owner, _gen)) return;
    widget.onPaired();
  }

  Future<void> _scan({bool auto = false}) async {
    final scope = ref.read(activityScopeProvider);
    if (!_ready || _scanning || !scope.isActive(_owner, _gen)) return;
    final host = ref.read(orienteHostProvider);
    _saidNotFound = false;
    setState(() {
      _scanning = true;
      _devices.clear();
      _status = 'Your smart glasses are ready. Scanning for glasses.';
    });
    if (!auto) {
      await scope.speakOwned(
        'Scanning for glasses.',
        owner: _owner,
        gen: _gen,
        interrupt: true,
      );
    }
    if (!scope.isActive(_owner, _gen)) return;
    await host.glassesStartScan();
    _timeout?.cancel();
    _timeout = scope.ownedTimer(
      const Duration(seconds: 20),
      () {
        unawaited(_finishScan());
      },
      owner: _owner,
      gen: _gen,
    );
  }

  Future<void> _finishScan() async {
    final scope = ref.read(activityScopeProvider);
    if (!scope.isActive(_owner, _gen)) return;
    final host = ref.read(orienteHostProvider);
    await host.glassesStopScan();
    if (!mounted || !scope.isActive(_owner, _gen)) return;
    setState(() {
      _scanning = false;
      if (_devices.isEmpty) {
        _status =
            'No glasses found. Make sure they are on, then say scan or tap Scan.';
      } else {
        _status =
            'Found ${_devices.length} device(s). Double tap one to pair.';
      }
    });
    if (_devices.isEmpty && !_saidNotFound) {
      _saidNotFound = true;
      await scope.speakOwned(
        _status,
        owner: _owner,
        gen: _gen,
        interrupt: true,
      );
    } else if (_devices.isNotEmpty) {
      await scope.speakOwned(
        _status,
        owner: _owner,
        gen: _gen,
        interrupt: true,
      );
    }
  }

  Future<void> _connect(GlassDevice d) async {
    final scope = ref.read(activityScopeProvider);
    if (_connecting || !scope.isActive(_owner, _gen)) return;
    final host = ref.read(orienteHostProvider);
    setState(() {
      _connecting = true;
      _status = 'Connecting to ${d.name}…';
    });
    _timeout?.cancel();
    await host.glassesStopScan();
    await scope.speakOwned(
      'Connecting to ${d.name}.',
      owner: _owner,
      gen: _gen,
      interrupt: true,
    );
    if (!scope.isActive(_owner, _gen)) return;
    final ok = await host.glassesBind(name: d.name, address: d.address);
    if (!ok && mounted && scope.isActive(_owner, _gen)) {
      setState(() {
        _connecting = false;
        _status = 'Could not start pairing. Try again.';
      });
      await scope.speakOwned(
        _status,
        owner: _owner,
        gen: _gen,
        interrupt: true,
      );
    }
  }

  Future<void> _leave() async {
    await ref.read(activityScopeProvider).stop();
    widget.onBack();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    try {
      unawaited(ref.read(activityScopeProvider).stop());
    } catch (_) {
      try {
        ref.read(orienteHostProvider).glassesStopScan();
        ref.read(orienteHostProvider).stopSpeaking();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return ScreenScaffold(
      background: const GlowBackground(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Go back',
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: VeTokens.targetSecondary,
                    minHeight: VeTokens.targetSecondary,
                  ),
                  iconSize: 28,
                  onPressed: _leave,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Pair glasses',
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
          PillButton(
            label: _scanning ? 'Scanning…' : 'Scan',
            onPressed: (!_ready || _scanning || _connecting)
                ? null
                : () => _scan(auto: false),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Scanning for nearby glasses…'
                          : 'Glasses will appear here after a scan.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final d = list[i];
                      return ChoiceCard(
                        title: d.name,
                        description: '${d.address}  ·  ${d.rssi} dBm',
                        icon: Icons.visibility_rounded,
                        compact: true,
                        onTap: () {
                          if (!_connecting) _connect(d);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
