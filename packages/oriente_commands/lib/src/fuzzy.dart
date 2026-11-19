/// Simple Levenshtein distance for OCR / ASR fuzzy matching.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      curr[j + 1] = [
        curr[j] + 1,
        prev[j + 1] + 1,
        prev[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j <= b.length; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[b.length];
}

double similarity(String a, String b) {
  final aa = a.toLowerCase().trim();
  final bb = b.toLowerCase().trim();
  if (aa.isEmpty && bb.isEmpty) return 1;
  if (aa.isEmpty || bb.isEmpty) return 0;
  final dist = levenshtein(aa, bb);
  final maxLen = aa.length > bb.length ? aa.length : bb.length;
  return 1.0 - (dist / maxLen);
}

bool fuzzyEquals(String a, String b, {double threshold = 0.75}) {
  return similarity(a, b) >= threshold;
}

/// Best token match of [needle] against [haystack] tokens / phrases.
double bestFuzzyScore(String needle, String haystack) {
  final n = needle.toLowerCase().trim();
  final h = haystack.toLowerCase().trim();
  if (n.isEmpty || h.isEmpty) return 0;
  if (h.contains(n)) return 1;

  var best = similarity(n, h);
  for (final token in h.split(RegExp(r'\s+'))) {
    final s = similarity(n, token);
    if (s > best) best = s;
  }
  return best;
}
