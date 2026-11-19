/// COCO / EfficientDet-Lite0 labels Oriente can hunt offline, plus aliases.
class SupportedObjects {
  static const cocoLabels = <String>{
    'person',
    'bicycle',
    'car',
    'motorcycle',
    'airplane',
    'bus',
    'train',
    'truck',
    'boat',
    'traffic light',
    'fire hydrant',
    'stop sign',
    'parking meter',
    'bench',
    'bird',
    'cat',
    'dog',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
    'backpack',
    'umbrella',
    'handbag',
    'tie',
    'suitcase',
    'frisbee',
    'skis',
    'snowboard',
    'sports ball',
    'kite',
    'baseball bat',
    'baseball glove',
    'skateboard',
    'surfboard',
    'tennis racket',
    'bottle',
    'wine glass',
    'cup',
    'fork',
    'knife',
    'spoon',
    'bowl',
    'banana',
    'apple',
    'sandwich',
    'orange',
    'broccoli',
    'carrot',
    'hot dog',
    'pizza',
    'donut',
    'cake',
    'chair',
    'couch',
    'potted plant',
    'bed',
    'dining table',
    'toilet',
    'tv',
    'laptop',
    'mouse',
    'remote',
    'keyboard',
    'cell phone',
    'microwave',
    'oven',
    'toaster',
    'sink',
    'refrigerator',
    'book',
    'clock',
    'vase',
    'scissors',
    'teddy bear',
    'hair drier',
    'toothbrush',
  };

  /// Labels produced by the optional offline cable detector.
  static const cableLabels = <String>{
    'cable',
    'charging_cable',
    'usb_c_cable',
    'lightning_cable',
    'micro_usb_cable',
    'hdmi_cable',
    'power_cord',
    'extension_cord',
    'ethernet_cable',
    'headphone_cable',
    'charger_adapter',
    'power_strip',
  };

  /// Whole-phrase aliases only (never applied to a trailing token of a longer phrase).
  static const aliases = <String, String>{
    'phone': 'cell phone',
    'mobile': 'cell phone',
    'cellphone': 'cell phone',
    'computer': 'laptop',
    'tv': 'tv',
    'television': 'tv',
    'screen': 'tv',
    'sofa': 'couch',
    'plant': 'potted plant',
    'mug': 'cup',
    'bag': 'handbag',
    'water bottle': 'bottle',
    'bottle of water': 'bottle',
    'water': 'bottle',
    'bottles': 'bottle',
    'battle': 'bottle',
    'bottom': 'bottle',
    'bottled': 'bottle',
    'boddle': 'bottle',
    'award': 'bottle',
    'a word': 'bottle',
    'a ward': 'bottle',
    'ward': 'bottle',
    'cable': 'cable',
    'cables': 'cable',
    'cord': 'cable',
    'cords': 'cable',
    'wire': 'cable',
    'wires': 'cable',
    'charger': 'cable',
    'charging cable': 'cable',
    'usb cable': 'cable',
    'usb-c': 'cable',
    'usb c': 'cable',
    'lightning cable': 'cable',
    'hdmi': 'cable',
    'hdmi cable': 'cable',
    'power cord': 'cable',
    'extension cord': 'cable',
    'ethernet': 'cable',
    'headphone cable': 'cable',
    'adapter': 'charger_adapter',
    'power strip': 'power_strip',
  };

  static bool isCableQuery(String query) {
    final q = query.toLowerCase().trim();
    if (cableLabels.contains(q)) return true;
    final a = aliases[q];
    if (a != null && (a == 'cable' || cableLabels.contains(a))) return true;
    return q.contains('cable') ||
        q.contains('cord') ||
        q.contains('wire') ||
        q.contains('charger') ||
        q.contains('usb') ||
        q.contains('hdmi') ||
        q.contains('lightning');
  }

  /// Returns canonical detector label, or null if unsupported.
  static String? resolve(String query, {Map<String, String> personal = const {}}) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;
    if (personal.containsKey(q)) return personal[q];
    final withoutMy = q.replaceFirst(RegExp(r'^my\s+'), '').trim();
    if (withoutMy.isNotEmpty && personal.containsKey(withoutMy)) {
      return personal[withoutMy];
    }

    // 1) Exact label.
    if (cocoLabels.contains(q) || cableLabels.contains(q)) return q;
    if (withoutMy.isNotEmpty &&
        (cocoLabels.contains(withoutMy) || cableLabels.contains(withoutMy))) {
      return withoutMy;
    }

    // 2) Whole-phrase alias only.
    final alias = aliases[q] ?? aliases[withoutMy];
    if (alias != null) {
      if (cocoLabels.contains(alias) ||
          cableLabels.contains(alias) ||
          alias == 'cable') {
        return alias;
      }
    }

    if (isCableQuery(q) && q == withoutMy) {
      // Only when the whole query is cable-like, not "find the word cord exhibitor".
      if (!q.contains(' ') || aliases.containsKey(q) || cableLabels.contains(q)) {
        return 'cable';
      }
      if (RegExp(r'\b(cable|cord|wire|charger|usb|hdmi|lightning)\b').hasMatch(q) &&
          q.split(' ').length <= 3) {
        return 'cable';
      }
    }

    // 3) Supported object name as a whole word inside the phrase.
    final contained = _wholeWordLabel(q) ?? _wholeWordLabel(withoutMy);
    if (contained != null) return contained;

    // 4) Fuzzy edit distance ≤ 2 (exact/alias already tried).
    // Same first letter + similar length so "word"≠"bird".
    for (final label in cocoLabels) {
      if (q.endsWith('s') && label == q.substring(0, q.length - 1)) return label;
      if (_fuzzyLabel(q, label)) return label;
      if (withoutMy.isNotEmpty && _fuzzyLabel(withoutMy, label)) return label;
    }

    // 5) Phonetic (Soundex) fallback.
    final phonetic = _phoneticMatch(q) ?? _phoneticMatch(withoutMy);
    if (phonetic != null) return phonetic;

    return null;
  }

  static bool _fuzzyLabel(String q, String label) {
    if (q.length < 3 || label.length < 3) return false;
    if ((q.length - label.length).abs() > 1) return false;
    if (q[0] != label[0]) return false;
    return _editDistance(q, label) <= 2;
  }

  static String? _wholeWordLabel(String q) {
    if (q.isEmpty) return null;
    // Longest labels first so "stop sign" / "cell phone" win over shorter tokens.
    final labels = [...cocoLabels, ...cableLabels]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final label in labels) {
      final re = RegExp('\\b${RegExp.escape(label)}\\b');
      if (re.hasMatch(q)) return label;
    }
    return null;
  }

  static String? _phoneticMatch(String q) {
    if (q.length < 3) return null;
    final qCode = soundex(q);
    if (qCode.isEmpty) return null;
    for (final label in cocoLabels) {
      if (label.contains(' ')) continue;
      if (soundex(label) == qCode) return label;
    }
    // Also match whole-phrase bottle aliases phonetically against bottle.
    if (soundex('bottle') == qCode) return 'bottle';
    return null;
  }

  /// American Soundex.
  static String soundex(String input) {
    final s = input.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (s.isEmpty) return '';
    final map = <String, String>{
      'b': '1',
      'f': '1',
      'p': '1',
      'v': '1',
      'c': '2',
      'g': '2',
      'j': '2',
      'k': '2',
      'q': '2',
      's': '2',
      'x': '2',
      'z': '2',
      'd': '3',
      't': '3',
      'l': '4',
      'm': '5',
      'n': '5',
      'r': '6',
    };
    final first = s[0];
    final buf = StringBuffer(first.toUpperCase());
    String? last;
    for (var i = 1; i < s.length && buf.length < 4; i++) {
      final code = map[s[i]];
      if (code == null) {
        last = null;
        continue;
      }
      if (code == last) continue;
      buf.write(code);
      last = code;
    }
    while (buf.length < 4) {
      buf.write('0');
    }
    return buf.toString();
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      m[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      m[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        m[i][j] = [
          m[i - 1][j] + 1,
          m[i][j - 1] + 1,
          m[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return m[a.length][b.length];
  }

  static bool isSupported(String query, {Map<String, String> personal = const {}}) {
    return resolve(query, personal: personal) != null;
  }

  /// Biasing phrases for Android 13+ speech recognizer.
  static List<String> biasingPhrases() {
    const commands = <String>[
      'find',
      'look for',
      'search',
      'search for',
      'where is',
      'read',
      'describe',
      'stop',
    ];
    final out = <String>{...commands, ...cocoLabels, ...aliases.keys};
    return out.toList()..sort();
  }
}
