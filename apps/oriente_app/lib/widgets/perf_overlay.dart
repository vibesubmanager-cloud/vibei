import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Developer-only FPS / latency / memory strip.
class PerfOverlay extends ConsumerStatefulWidget {
  const PerfOverlay({super.key});

  @override
  ConsumerState<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends ConsumerState<PerfOverlay> {
  Timer? _timer;
  Map<String, dynamic> _perf = const {};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted) return;
    if (!ref.read(perfOverlayEnabledProvider)) return;
    try {
      final p = await ref.read(orienteHostProvider).getPipelinePerf();
      if (mounted) setState(() => _perf = p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(perfOverlayEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final fps = (_perf['fps'] as num?)?.toStringAsFixed(1) ?? '—';
    final det = '${_perf['detectLatencyMs'] ?? '—'}';
    final ocr = '${_perf['ocrLatencyMs'] ?? '—'}';
    final mem = (_perf['memoryMb'] as num?)?.toStringAsFixed(1) ?? '—';
    final motion = (_perf['motionScore'] as num?)?.toStringAsFixed(2) ?? '—';
    return Positioned(
      left: 8,
      top: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: const Color(0xAA000000),
          child: Text(
            'FPS $fps  det ${det}ms  ocr ${ocr}ms  mem ${mem}MB  motion $motion',
            style: const TextStyle(
              color: Color(0xFF7CFF7C),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
