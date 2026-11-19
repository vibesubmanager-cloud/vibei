import 'detection.dart';

class SceneObject {
  const SceneObject({
    required this.id,
    required this.label,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.score,
    this.hits = 1,
  });

  final String id;
  final String label;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final double score;
  final int hits;

  double get area => width * height;
  double get left => cx - width / 2;
  double get right => cx + width / 2;
  double get top => cy - height / 2;
  double get bottom => cy + height / 2;

  SceneObject copyWith({int? hits}) => SceneObject(
        id: id,
        label: label,
        cx: cx,
        cy: cy,
        width: width,
        height: height,
        score: score,
        hits: hits ?? this.hits,
      );
}

class SceneDescriberState {
  const SceneDescriberState({
    this.tracks = const [],
    this.said = const {},
    this.roomMemory = const [],
  });

  final List<SceneObject> tracks;
  final Set<String> said;
  final List<String> roomMemory;

  SceneDescriberState copyWith({
    List<SceneObject>? tracks,
    Set<String>? said,
    bool clearSaid = false,
    List<String>? roomMemory,
  }) =>
      SceneDescriberState(
        tracks: tracks ?? this.tracks,
        said: clearSaid ? {} : (said ?? this.said),
        roomMemory: roomMemory ?? this.roomMemory,
      );
}

/// Pure offline scene → natural language. Unit-tested.
///
/// Describes the scene as a connected environment (groups, surfaces,
/// activities), not as a robotic list of detections.
class SceneDescriber {
  SceneDescriber({
    this.minHits = 3,
    this.window = 5,
    this.dropAfterMissing = 10,
    this.minConfidence = 0.4,
  });

  final int minHits;
  final int window;
  final int dropAfterMissing;
  final double minConfidence;

  static const supportLabels = {
    'chair',
    'couch',
    'bench',
    'bed',
  };

  static const surfaceLabels = {
    'dining table',
    'table',
  };

  /// Items that typically sit on a desk/table as a computer setup.
  static const workstationLabels = {
    'laptop',
    'keyboard',
    'mouse',
    'tv',
    'cell phone',
    'book',
  };

  static const cableLikeLabels = {
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
    'remote',
  };

  static const hedgedCableMin = 0.55;
  static const certainCableMin = 0.72;

  static const kitchenAnchors = {
    'refrigerator',
    'microwave',
    'oven',
    'sink',
    'toaster',
  };

  static const livingAnchors = {
    'couch',
    'tv',
  };

  static const outdoorAnchors = {
    'car',
    'motorcycle',
    'bus',
    'truck',
    'bicycle',
    'traffic light',
  };

  static String displayLabel(String raw) {
    switch (raw) {
      case 'dining table':
        return 'table';
      case 'tv':
        return 'TV';
      case 'cell phone':
        return 'phone';
      case 'potted plant':
        return 'plant';
      case 'remote':
        return 'remote control';
      case 'cable':
      case 'charging_cable':
      case 'usb_c_cable':
      case 'lightning_cable':
      case 'micro_usb_cable':
      case 'hdmi_cable':
      case 'power_cord':
      case 'extension_cord':
      case 'ethernet_cable':
      case 'headphone_cable':
        return 'cable';
      case 'charger_adapter':
        return 'charger';
      case 'power_strip':
        return 'power strip';
      default:
        return raw;
    }
  }

  /// Update tracks from a frame of detections; return stable objects.
  SceneDescriberState ingest(
    SceneDescriberState state,
    List<Detection> detections,
  ) {
    final filtered =
        detections.where((d) => d.score >= minConfidence).toList();
    final next = <SceneObject>[];
    final used = <int>{};

    for (final t in state.tracks) {
      var bestI = -1;
      var bestIoU = 0.0;
      for (var i = 0; i < filtered.length; i++) {
        if (used.contains(i)) continue;
        final d = filtered[i];
        if (d.label != t.label) continue;
        final iou = _iou(t, d);
        if (iou > bestIoU) {
          bestIoU = iou;
          bestI = i;
        }
      }
      if (bestI >= 0 && bestIoU >= 0.3) {
        used.add(bestI);
        final d = filtered[bestI];
        next.add(
          SceneObject(
            id: t.id,
            label: d.label,
            cx: d.cx,
            cy: d.cy,
            width: d.width,
            height: d.height,
            score: d.score,
            hits: (t.hits + 1).clamp(0, window),
          ),
        );
      } else {
        final miss = t.hits - 1;
        if (miss > -dropAfterMissing) {
          next.add(t.copyWith(hits: miss));
        }
      }
    }

    for (var i = 0; i < filtered.length; i++) {
      if (used.contains(i)) continue;
      final d = filtered[i];
      next.add(
        SceneObject(
          id: '${d.label}_${d.cx.toStringAsFixed(2)}_${d.cy.toStringAsFixed(2)}',
          label: d.label,
          cx: d.cx,
          cy: d.cy,
          width: d.width,
          height: d.height,
          score: d.score,
        ),
      );
    }

    return state.copyWith(tracks: next);
  }

  List<SceneObject> stable(SceneDescriberState state) =>
      state.tracks.where((t) => t.hits >= minHits).toList();

  /// Full one-shot summary (what is in front of me).
  String summarize(List<SceneObject> objects) {
    if (objects.isEmpty) {
      return 'I cannot identify any objects clearly in front of you. '
          'Try moving your camera slowly.';
    }
    final sentences = _buildSceneNarrative(objects);
    if (sentences.isEmpty) {
      return 'I cannot identify any objects clearly in front of you. '
          'Try moving your camera slowly.';
    }
    return sentences.take(3).join(' ');
  }

  /// Continuous mode: only new/changed facts.
  ({String? speech, SceneDescriberState state}) updateSpeech(
    SceneDescriberState state,
  ) {
    final objs = stable(state);
    final sentences = _buildSceneNarrative(objs);
    final fresh = <String>[];
    final said = {...state.said};
    final memory = [...state.roomMemory];
    for (final s in sentences) {
      final key = s.toLowerCase();
      if (!said.contains(key)) {
        fresh.add(s);
        said.add(key);
        if (!memory.contains(s)) memory.add(s);
      }
    }
    if (fresh.isEmpty) {
      return (
        speech: null,
        state: state.copyWith(said: said, roomMemory: memory),
      );
    }
    // One coherent utterance (may be 1–2 sentences already joined).
    final speech = fresh.take(2).join(' ');
    return (
      speech: speech,
      state: state.copyWith(said: said, roomMemory: memory),
    );
  }

  /// Call when the camera view meaningfully changes so a new scene can speak.
  SceneDescriberState onViewChanged(SceneDescriberState state) =>
      state.copyWith(clearSaid: true);

  String roomSummary(SceneDescriberState state) {
    if (state.roomMemory.isEmpty) {
      return 'I have not noted objects in this room yet.';
    }
    return 'In this room I have seen ${state.roomMemory.join(' ')}';
  }

  /// Structured offline hints for optional online enhancement.
  Map<String, dynamic> structuredHints(List<SceneObject> objects) {
    final env = _inferEnvironment(objects);
    return {
      'intent': 'SCENE_DESCRIPTION',
      'description': summarize(objects),
      'objects': objects
          .map(
            (o) => {
              'name': displayLabel(o.label),
              'label': o.label,
              'position': _positionToken(o),
              'cx': o.cx,
              'cy': o.cy,
              'width': o.width,
              'height': o.height,
              'score': o.score,
            },
          )
          .toList(),
      'environment': env,
      'confidence': 'based on actual visual evidence',
      'offline': summarize(objects),
    };
  }

  // —— Narrative builder ——

  List<String> _buildSceneNarrative(List<SceneObject> objects) {
    if (objects.isEmpty) return const [];
    final used = <String>{};
    final out = <String>[];

    final env = _inferEnvironment(objects);
    if (env != null) {
      out.add(env);
    }

    // 1) People + seating + nearby work surface
    _describePeople(objects, used, out);

    // 2) Surfaces with items on them (tables)
    _describeSurfaces(objects, used, out);

    // 3) Soft workstation cluster without an explicit table
    _describeWorkstationCluster(objects, used, out);

    // 4) Living-room layout: couch facing TV
    _describeLivingLayout(objects, used, out);

    // 5) Remaining notable objects, grouped by label / proximity
    _describeRemainder(objects, used, out);

    // Prefer a single coherent paragraph of ≤3 sentences.
    return out.take(3).toList();
  }

  String? _inferEnvironment(List<SceneObject> objects) {
    final labels = objects.map((o) => o.label).toSet();
    final has = labels.contains;

    final kitchenHits = kitchenAnchors.where(has).length;
    if (kitchenHits >= 2 ||
        (has('refrigerator') &&
            (has('microwave') || has('oven') || has('sink') || has('bowl')))) {
      return 'You appear to be in a kitchen.';
    }

    if (has('couch') && (has('tv') || has('remote'))) {
      return 'This looks like a living room.';
    }

    if (has('bed') &&
        (has('laptop') ||
            has('book') ||
            has('tv') ||
            has('chair') ||
            objects.length >= 2)) {
      return 'This looks like a bedroom.';
    }

    final workBits = workstationLabels.where(has).length;
    if (workBits >= 2 &&
        (has('dining table') ||
            has('chair') ||
            has('laptop') ||
            has('keyboard'))) {
      return 'This looks like a workspace.';
    }

    if (has('dining table') &&
        (has('chair') || has('cup') || has('bowl') || has('bottle'))) {
      // Dining / meeting — only if not already workspace-like
      if (workBits < 2) {
        return 'This looks like a dining area.';
      }
    }

    final outdoorHits = outdoorAnchors.where(has).length;
    if (outdoorHits >= 2 ||
        (has('car') && (has('person') || has('motorcycle') || has('bicycle'))) ||
        (has('bus') || has('truck')) && outdoorHits >= 1) {
      return 'You appear to be outdoors near a road.';
    }

    return null; // uncertain — do not guess
  }

  void _describePeople(
    List<SceneObject> objects,
    Set<String> used,
    List<String> out,
  ) {
    final people = objects.where((o) => o.label == 'person').toList();
    final supports =
        objects.where((o) => supportLabels.contains(o.label)).toList();
    final tables =
        objects.where((o) => surfaceLabels.contains(o.label)).toList();

    for (final p in people) {
      SceneObject? seat;
      for (final s in supports) {
        if (_sittingOn(p, s)) {
          seat = s;
          break;
        }
      }
      SceneObject? tableAhead;
      for (final t in tables) {
        if (_inFrontOf(p, t) || _near(p, t, 0.35)) {
          tableAhead = t;
          break;
        }
      }

      final onTable = <SceneObject>[];
      if (tableAhead != null) {
        for (final o in objects) {
          if (o.id == tableAhead.id || o.label == 'person') continue;
          if (supportLabels.contains(o.label)) continue;
          if (_onSurface(o, tableAhead)) onTable.add(o);
        }
      }

      if (seat != null && tableAhead != null) {
        final buf = StringBuffer(
          'A person is sitting on a ${displayLabel(seat.label)} '
          '${_relativeTo(p, tableAhead)} a ${displayLabel(tableAhead.label)}',
        );
        if (onTable.isNotEmpty) {
          buf.write(
            ', with ${_joinNouns(onTable)} on the ${displayLabel(tableAhead.label)}',
          );
          for (final o in onTable) {
            used.add(o.id);
          }
        }
        buf.write('.');
        out.add(buf.toString());
        used.add(p.id);
        used.add(seat.id);
        used.add(tableAhead.id);
      } else if (seat != null) {
        out.add(
          'A person is sitting on a ${displayLabel(seat.label)} ${_pos(p)}.',
        );
        used.add(p.id);
        used.add(seat.id);
      } else if (people.length >= 2) {
        // Count handled once below.
      } else {
        out.add('There is a person ${_pos(p)}.');
        used.add(p.id);
      }
    }

    final unusedPeople =
        people.where((p) => !used.contains(p.id)).toList();
    if (unusedPeople.length >= 2) {
      final table = tables.isEmpty ? null : tables.first;
      if (table != null && unusedPeople.any((p) => _near(p, table, 0.45))) {
        out.add(
          'There are ${unusedPeople.length} people around a '
          '${displayLabel(table.label)}.',
        );
        used.add(table.id);
      } else {
        out.add('There are ${unusedPeople.length} people nearby.');
      }
      for (final p in unusedPeople) {
        used.add(p.id);
      }
    } else if (unusedPeople.length == 1) {
      out.add('There is a person ${_pos(unusedPeople.first)}.');
      used.add(unusedPeople.first.id);
    }
  }

  void _describeSurfaces(
    List<SceneObject> objects,
    Set<String> used,
    List<String> out,
  ) {
    final tables = objects
        .where((o) => surfaceLabels.contains(o.label) && !used.contains(o.id))
        .toList()
      ..sort((a, b) => b.area.compareTo(a.area));

    for (final table in tables) {
      final onIt = objects
          .where(
            (o) =>
                !used.contains(o.id) &&
                o.id != table.id &&
                o.label != 'person' &&
                !supportLabels.contains(o.label) &&
                !surfaceLabels.contains(o.label) &&
                _onSurface(o, table),
          )
          .toList()
        ..sort((a, b) => b.area.compareTo(a.area));

      final pos = _pos(table);
      if (onIt.isEmpty) {
        out.add('There is a ${displayLabel(table.label)} $pos.');
        used.add(table.id);
        continue;
      }

      // Prefer "desk-like" wording when workstation items dominate.
      final workCount =
          onIt.where((o) => workstationLabels.contains(o.label)).length;
      final surfaceWord = workCount >= 2 ? 'desk' : displayLabel(table.label);

      out.add(
        'I can see a $surfaceWord $pos with ${_joinNouns(onIt)} '
        'on it.',
      );
      used.add(table.id);
      for (final o in onIt) {
        used.add(o.id);
      }
    }
  }

  void _describeWorkstationCluster(
    List<SceneObject> objects,
    Set<String> used,
    List<String> out,
  ) {
    final candidates = objects
        .where(
          (o) =>
              !used.contains(o.id) &&
              (workstationLabels.contains(o.label) ||
                  o.label == 'bottle' ||
                  cableLikeLabels.contains(o.label) ||
                  o.label == 'cable'),
        )
        .toList();
    if (candidates.length < 2) return;

    // Cluster around the largest workstation item.
    candidates.sort((a, b) => b.area.compareTo(a.area));
    final seed = candidates.first;
    final cluster = <SceneObject>[seed];
    for (final o in candidates.skip(1)) {
      if (_near(seed, o, 0.42) || _near(cluster.last, o, 0.35)) {
        cluster.add(o);
      }
    }
    if (cluster.length < 2) return;

    final work =
        cluster.where((o) => workstationLabels.contains(o.label)).toList();
    if (work.length < 2) return;

    final others =
        cluster.where((o) => !workstationLabels.contains(o.label)).toList();
    final pos = _pos(_centroidObject(cluster));
    final parts = [...work, ...others];
    out.add(
      'There is a computer setup $pos with ${_joinNouns(parts)}.',
    );
    for (final o in cluster) {
      used.add(o.id);
    }
  }

  void _describeLivingLayout(
    List<SceneObject> objects,
    Set<String> used,
    List<String> out,
  ) {
    final couches = objects
        .where((o) => o.label == 'couch' && !used.contains(o.id))
        .toList();
    final tvs =
        objects.where((o) => o.label == 'tv' && !used.contains(o.id)).toList();
    final tables = objects
        .where(
          (o) => surfaceLabels.contains(o.label) && !used.contains(o.id),
        )
        .toList();

    if (couches.isEmpty) return;
    final couch = couches.first;
    final tv = tvs.isEmpty ? null : tvs.first;
    SceneObject? coffee;
    for (final t in tables) {
      if (_near(couch, t, 0.45) && t.area < couch.area) {
        coffee = t;
        break;
      }
    }

    if (tv != null && _facingPair(couch, tv)) {
      final buf = StringBuffer(
        'There is a sofa ${_pos(couch)} facing a TV',
      );
      used.add(couch.id);
      used.add(tv.id);
      if (coffee != null) {
        final onCoffee = objects
            .where(
              (o) =>
                  !used.contains(o.id) &&
                  o.id != coffee!.id &&
                  _onSurface(o, coffee),
            )
            .toList();
        buf.write(
          ', with a ${displayLabel(coffee.label)} in front of it',
        );
        used.add(coffee.id);
        if (onCoffee.isNotEmpty) {
          buf.write('. ${_capitalize(_joinNouns(onCoffee))} '
              '${onCoffee.length == 1 ? 'is' : 'are'} on the table');
          for (final o in onCoffee) {
            used.add(o.id);
          }
        }
      }
      buf.write('.');
      out.add(buf.toString());
    } else if (!used.contains(couch.id)) {
      out.add('There is a sofa ${_pos(couch)}.');
      used.add(couch.id);
    }
  }

  void _describeRemainder(
    List<SceneObject> objects,
    Set<String> used,
    List<String> out,
  ) {
    if (out.length >= 3) return;
    final rest = objects.where((o) => !used.contains(o.id)).toList()
      ..sort((a, b) => b.area.compareTo(a.area));
    if (rest.isEmpty) return;

    // Prefer a natural "A next to B" when two leftovers are adjacent.
    if (rest.length >= 2 && out.length < 3) {
      final a = rest[0];
      final b = rest[1];
      if (_near(a, b, 0.28) && a.label != b.label) {
        final relation = a.cx <= b.cx ? 'next to' : 'next to';
        out.add(
          'I can see ${_article(displayLabel(a.label))} ${_pos(a)}, '
          '$relation ${_article(displayLabel(b.label))}.',
        );
        used.add(a.id);
        used.add(b.id);
        rest.removeWhere((o) => used.contains(o.id));
      }
    }

    if (out.length >= 3 || rest.isEmpty) return;

    // Group nearby leftovers into one "nearby" sentence when possible.
    final byLabel = <String, List<SceneObject>>{};
    for (final o in rest.take(8)) {
      byLabel.putIfAbsent(o.label, () => []).add(o);
    }
    final chunks = <String>[];
    final labelOrder = byLabel.keys.toList()
      ..sort((a, b) {
        final aa = byLabel[a]!.map((e) => e.area).fold<double>(0, (x, y) => x + y);
        final bb = byLabel[b]!.map((e) => e.area).fold<double>(0, (x, y) => x + y);
        return bb.compareTo(aa);
      });

    for (final label in labelOrder) {
      final group = byLabel[label]!;
      if (group.length >= 2) {
        chunks.add(
          '${_plural(displayLabel(label), group.length)} ${_pos(group.first)}',
        );
      } else {
        chunks.add(
          '${_article(displayLabel(group.first.label))} ${_pos(group.first)}',
        );
      }
      for (final o in group) {
        used.add(o.id);
      }
      if (chunks.length >= 3) break;
    }

    if (chunks.isEmpty) return;
    if (chunks.length == 1) {
      out.add('I can see ${_uncapitalizeArticle(chunks.first)}.');
    } else {
      out.add('Nearby, ${_join(chunks)}.');
    }
  }

  // —— Geometry helpers ——

  bool _sittingOn(SceneObject person, SceneObject seat) {
    final overlap = _horizontalOverlap(person, seat);
    if (overlap < 0.2) return false;
    final personLower = person.cy + person.height * 0.15;
    return person.bottom > seat.top &&
        personLower < seat.bottom &&
        person.bottom < seat.bottom + 0.25 &&
        person.cy < seat.bottom;
  }

  bool _onSurface(SceneObject obj, SceneObject table) {
    if (_horizontalOverlap(obj, table) < 0.35) return false;
    // Object roughly in the upper/middle band of the table box, smaller than table.
    if (obj.area >= table.area * 0.95) return false;
    return (obj.bottom - table.top).abs() < 0.25 ||
        (obj.cy >= table.top - 0.05 &&
            obj.cy <= table.bottom &&
            obj.area < table.area);
  }

  bool _near(SceneObject a, SceneObject b, double maxDist) {
    final dx = a.cx - b.cx;
    final dy = a.cy - b.cy;
    return (dx * dx + dy * dy) <= maxDist * maxDist;
  }

  bool _inFrontOf(SceneObject person, SceneObject table) {
    // Table roughly ahead of person (similar x, table higher or overlapping).
    return (person.cx - table.cx).abs() < 0.3 &&
        table.cy <= person.cy + 0.15 &&
        _near(person, table, 0.45);
  }

  bool _facingPair(SceneObject a, SceneObject b) {
    // Horizontal separation with similar vertical band → facing across space.
    return (a.cx - b.cx).abs() > 0.15 && (a.cy - b.cy).abs() < 0.35;
  }

  String _relativeTo(SceneObject person, SceneObject table) {
    if ((person.cx - table.cx).abs() < 0.2) return 'in front of';
    if (person.cx < table.cx) return 'to the left of';
    return 'to the right of';
  }

  double _horizontalOverlap(SceneObject a, SceneObject b) {
    final left = a.left > b.left ? a.left : b.left;
    final right = a.right < b.right ? a.right : b.right;
    final w = right - left;
    if (w <= 0) return 0;
    final minW = a.width < b.width ? a.width : b.width;
    return minW <= 0 ? 0 : w / minW;
  }

  double _iou(SceneObject a, Detection b) {
    final aL = a.left, aR = a.right, aT = a.top, aB = a.bottom;
    final bL = b.cx - b.width / 2,
        bR = b.cx + b.width / 2,
        bT = b.cy - b.height / 2,
        bB = b.cy + b.height / 2;
    final l = aL > bL ? aL : bL;
    final r = aR < bR ? aR : bR;
    final t = aT > bT ? aT : bT;
    final bot = aB < bB ? aB : bB;
    final inter = (r - l).clamp(0, 1) * (bot - t).clamp(0, 1);
    final union = a.area + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  SceneObject _centroidObject(List<SceneObject> group) {
    var cx = 0.0, cy = 0.0;
    for (final o in group) {
      cx += o.cx;
      cy += o.cy;
    }
    cx /= group.length;
    cy /= group.length;
    return SceneObject(
      id: 'centroid',
      label: group.first.label,
      cx: cx,
      cy: cy,
      width: group.first.width,
      height: group.first.height,
      score: 1,
      hits: 3,
    );
  }

  /// Camera-space positions spoken for the user holding the phone.
  /// cx grows rightward in the image; "left/right" match the user's left/right
  /// when the rear camera faces away from them (standard phone pose).
  String _pos(SceneObject o) {
    final h = _positionToken(o);
    final near = o.area > 0.12;
    if (near && (h == 'centre' || h == 'slightly left' || h == 'slightly right')) {
      if (h == 'centre') return 'in front of you';
      return '$h, near you';
    }
    if (near) return '$h, near you';
    if (o.cy < 0.28) return '$h, in the upper part of the view';
    if (o.cy > 0.72) return '$h, in the lower part of the view';
    if (o.area < 0.04) return '$h, in the background';
    return h;
  }

  String _positionToken(SceneObject o) {
    if (o.cx < 0.18) return 'far left';
    if (o.cx < 0.35) return 'on the left';
    if (o.cx < 0.45) return 'slightly left';
    if (o.cx <= 0.55) return 'centre';
    if (o.cx <= 0.65) return 'slightly right';
    if (o.cx <= 0.82) return 'on the right';
    return 'far right';
  }

  String _uncapitalizeArticle(String s) {
    // chunks already include article; keep natural "I can see a chair…"
    return s;
  }

  String _article(String noun) {
    if (noun.toUpperCase() == noun && noun.length <= 3) return 'a $noun';
    final first = noun.isEmpty ? '' : noun[0].toLowerCase();
    if ('aeiou'.contains(first)) return 'an $noun';
    return 'a $noun';
  }

  String _plural(String noun, int n) {
    if (n == 1) return _article(noun);
    if (noun.endsWith('s')) return '$n $noun';
    return '$n ${noun}s';
  }

  String _joinNouns(List<SceneObject> objs) {
    // Drop low-confidence cables; hedge moderate ones.
    final filtered = objs.where((o) {
      if (!cableLikeLabels.contains(o.label) && o.label != 'cable') {
        return true;
      }
      return o.score >= hedgedCableMin;
    }).toList();
    final byLabel = <String, int>{};
    final hedge = <String>{};
    final order = <String>[];
    for (final o in filtered) {
      final d = displayLabel(o.label);
      if (!byLabel.containsKey(d)) order.add(d);
      byLabel[d] = (byLabel[d] ?? 0) + 1;
      if ((cableLikeLabels.contains(o.label) || o.label == 'cable') &&
          o.score < certainCableMin) {
        hedge.add(d);
      }
    }
    final parts = <String>[];
    for (final d in order) {
      final n = byLabel[d]!;
      var phrase = n >= 2 ? _plural(d, n) : _article(d);
      if (n >= 2 && d == 'cable') phrase = 'several cables';
      if (hedge.contains(d)) phrase = 'what looks like $phrase';
      parts.add(phrase);
    }
    return _join(parts);
  }

  String _join(List<String> parts) {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
