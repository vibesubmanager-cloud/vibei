import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'design/components.dart';

/// Restyled connectivity as a compact StatusPill.
class ConnectivityIndicator extends ConsumerWidget {
  const ConnectivityIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityOnlineProvider);
    return StatusPill(
      label: online ? 'Online' : 'Offline',
      online: online,
    );
  }
}
