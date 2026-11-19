int _lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = [
        curr[j] + 1,
        prev[j + 1] + 1,
        prev[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j < prev.length; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[b.length];
}

double _similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final d = _lev(a, b);
  return 1.0 - d / (a.length > b.length ? a.length : b.length);
}

/// Normalize OCR/ASR text for matching.
String normalizeText(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r"[^\w\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class TextMatchHit {
  const TextMatchHit({
    required this.boxIndex,
    required this.score,
    required this.matchedText,
  });
  final int boxIndex;
  final double score;
  final String matchedText;
}

/// Fuzzy / partial / multi-box phrase matching for FIND TEXT.
class TextMatcher {
  const TextMatcher({this.minScore = 0.72});

  final double minScore;

  /// Returns best hits for [query] against OCR line texts.
  List<TextMatchHit> matchAll(String query, List<String> lines) {
    final q = normalizeText(query);
    if (q.isEmpty || lines.isEmpty) return const [];
    final qTokens = q.split(' ').where((t) => t.isNotEmpty).toList();
    final hits = <TextMatchHit>[];

    for (var i = 0; i < lines.length; i++) {
      final line = normalizeText(lines[i]);
      if (line.isEmpty) continue;
      var score = _scoreLine(q, qTokens, line);
      // Adjacent pair for multi-word queries
      if (score < minScore && i + 1 < lines.length) {
        final joined = normalizeText('${lines[i]} ${lines[i + 1]}');
        final s2 = _scoreLine(q, qTokens, joined);
        if (s2 > score) score = s2;
      }
      if (score >= minScore) {
        hits.add(TextMatchHit(boxIndex: i, score: score, matchedText: lines[i]));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  bool matches(String query, String line) =>
      matchAll(query, [line]).isNotEmpty;

  double _scoreLine(String q, List<String> qTokens, String line) {
    if (line.contains(q)) return 1.0;
    final tokens = line.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return 0;

    // Exact token / substring
    for (final t in tokens) {
      if (t == q || t.contains(q) || q.contains(t) && t.length >= 3) {
        return 0.95;
      }
      final sim = _similarity(t, q);
      if (sim >= minScore) return sim;
    }

    // Sliding window of qTokens length
    if (qTokens.length > 1 && tokens.length >= qTokens.length) {
      for (var i = 0; i <= tokens.length - qTokens.length; i++) {
        final window = tokens.sublist(i, i + qTokens.length).join(' ');
        if (window == q) return 1.0;
        final sim = _similarity(window, q);
        if (sim >= minScore) return sim;
      }
    }

    return _similarity(line, q);
  }
}
