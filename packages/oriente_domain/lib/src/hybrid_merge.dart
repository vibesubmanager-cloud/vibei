/// Merge offline sentence with online enrichment — speak offline first,
/// then only novel additions; drop stale view results.
class HybridDescribeMerge {
  const HybridDescribeMerge();

  /// Returns follow-up additions only (never repeats offline facts).
  String? additions({
    required String offlineSentence,
    required String onlineSentence,
    required String currentViewKey,
    required String resultViewKey,
  }) {
    if (resultViewKey != currentViewKey) return null; // stale
    final offlineNorm = _tokens(offlineSentence);
    final onlineParts = onlineSentence
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final fresh = <String>[];
    for (final part in onlineParts) {
      final t = _tokens(part);
      final overlap = t.where(offlineNorm.contains).length;
      if (t.isEmpty) continue;
      if (overlap / t.length >= 0.6) continue; // mostly repeat
      fresh.add(part);
    }
    if (fresh.isEmpty) return null;
    return fresh.join(' ');
  }

  Set<String> _tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toSet();
}
