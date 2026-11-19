import 'package:oriente_domain/oriente_domain.dart';
import 'package:test/test.dart';

void main() {
  final d = SceneDescriber(minHits: 1);

  test('person sitting on chair', () {
    final objs = [
      const SceneObject(
        id: 'p',
        label: 'person',
        cx: 0.5,
        cy: 0.45,
        width: 0.25,
        height: 0.5,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'c',
        label: 'chair',
        cx: 0.5,
        cy: 0.7,
        width: 0.3,
        height: 0.35,
        score: 0.9,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs);
    expect(s.toLowerCase(), contains('sitting on'));
    expect(s.toLowerCase(), contains('chair'));
  });

  test('desk items grouped into one surface sentence', () {
    final objs = [
      const SceneObject(
        id: 't',
        label: 'dining table',
        cx: 0.5,
        cy: 0.6,
        width: 0.6,
        height: 0.35,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'l',
        label: 'laptop',
        cx: 0.4,
        cy: 0.45,
        width: 0.2,
        height: 0.15,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'm',
        label: 'mouse',
        cx: 0.55,
        cy: 0.48,
        width: 0.08,
        height: 0.06,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'k',
        label: 'keyboard',
        cx: 0.45,
        cy: 0.52,
        width: 0.25,
        height: 0.08,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'b',
        label: 'bottle',
        cx: 0.65,
        cy: 0.45,
        width: 0.08,
        height: 0.18,
        score: 0.9,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s, contains('on it'));
    expect(s, contains('laptop'));
    expect(s, contains('keyboard'));
    // Not a robotic list of separate one-word sentences.
    expect(s.split('.').where((e) => e.trim().isNotEmpty).length, lessThan(4));
  });

  test('living room inference and sofa facing tv', () {
    final objs = [
      const SceneObject(
        id: 'sofa',
        label: 'couch',
        cx: 0.25,
        cy: 0.55,
        width: 0.4,
        height: 0.35,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'tv',
        label: 'tv',
        cx: 0.75,
        cy: 0.4,
        width: 0.3,
        height: 0.25,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'table',
        label: 'dining table',
        cx: 0.35,
        cy: 0.7,
        width: 0.25,
        height: 0.2,
        score: 0.85,
        hits: 3,
      ),
      const SceneObject(
        id: 'bottle',
        label: 'bottle',
        cx: 0.35,
        cy: 0.62,
        width: 0.06,
        height: 0.12,
        score: 0.8,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s, contains('living room'));
    expect(s, contains('sofa'));
    expect(s, contains('tv'));
  });

  test('kitchen environment from anchors', () {
    final objs = [
      const SceneObject(
        id: 'r',
        label: 'refrigerator',
        cx: 0.2,
        cy: 0.45,
        width: 0.25,
        height: 0.55,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'm',
        label: 'microwave',
        cx: 0.55,
        cy: 0.4,
        width: 0.2,
        height: 0.15,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'b',
        label: 'bottle',
        cx: 0.7,
        cy: 0.55,
        width: 0.08,
        height: 0.15,
        score: 0.85,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s, contains('kitchen'));
  });

  test('person at desk with laptop and cup', () {
    final objs = [
      const SceneObject(
        id: 'p',
        label: 'person',
        cx: 0.5,
        cy: 0.42,
        width: 0.28,
        height: 0.55,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'c',
        label: 'chair',
        cx: 0.5,
        cy: 0.72,
        width: 0.3,
        height: 0.32,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 't',
        label: 'dining table',
        cx: 0.5,
        cy: 0.55,
        width: 0.55,
        height: 0.3,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'l',
        label: 'laptop',
        cx: 0.45,
        cy: 0.48,
        width: 0.2,
        height: 0.14,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'cup',
        label: 'cup',
        cx: 0.62,
        cy: 0.5,
        width: 0.07,
        height: 0.1,
        score: 0.85,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s, contains('sitting on'));
    expect(s, contains('laptop'));
  });

  test('no repeated information on second update', () {
    var state = const SceneDescriberState();
    final frame = [
      const Detection(
        label: 'tv',
        score: 0.9,
        cx: 0.2,
        cy: 0.4,
        width: 0.3,
        height: 0.25,
      ),
    ];
    for (var i = 0; i < 3; i++) {
      state = d.ingest(state, frame);
    }
    final first = d.updateSpeech(state);
    expect(first.speech, isNotNull);
    final second = d.updateSpeech(first.state);
    expect(second.speech, isNull);
  });

  test('structured hints mark SCENE_DESCRIPTION', () {
    final objs = [
      const SceneObject(
        id: 'c',
        label: 'chair',
        cx: 0.5,
        cy: 0.5,
        width: 0.2,
        height: 0.3,
        score: 0.9,
        hits: 3,
      ),
    ];
    final h = d.structuredHints(objs);
    expect(h['intent'], 'SCENE_DESCRIPTION');
    expect(h['confidence'], 'based on actual visual evidence');
    expect((h['objects'] as List).first['position'], isNotNull);
  });

  test('outdoor road cluster', () {
    final objs = [
      const SceneObject(
        id: 'car',
        label: 'car',
        cx: 0.4,
        cy: 0.5,
        width: 0.3,
        height: 0.25,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'moto',
        label: 'motorcycle',
        cx: 0.7,
        cy: 0.55,
        width: 0.2,
        height: 0.2,
        score: 0.9,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s, contains('road'));
  });

  test('view change clears said so new scene can speak', () {
    var state = const SceneDescriberState();
    final frame = [
      const Detection(
        label: 'tv',
        score: 0.9,
        cx: 0.2,
        cy: 0.4,
        width: 0.3,
        height: 0.25,
      ),
    ];
    for (var i = 0; i < 3; i++) {
      state = d.ingest(state, frame);
    }
    final first = d.updateSpeech(state);
    expect(first.speech, isNotNull);
    state = d.onViewChanged(first.state);
    final again = d.updateSpeech(state);
    expect(again.speech, isNotNull);
  });

  test('plurals', () {
    final objs = [
      const SceneObject(
        id: 'c1',
        label: 'chair',
        cx: 0.3,
        cy: 0.5,
        width: 0.2,
        height: 0.3,
        score: 0.9,
        hits: 3,
      ),
      const SceneObject(
        id: 'c2',
        label: 'chair',
        cx: 0.7,
        cy: 0.5,
        width: 0.2,
        height: 0.3,
        score: 0.9,
        hits: 3,
      ),
    ];
    expect(d.summarize(objs).toLowerCase(), contains('2 chairs'));
  });

  test('uncertain environment is not forced', () {
    final objs = [
      const SceneObject(
        id: 'b',
        label: 'bottle',
        cx: 0.5,
        cy: 0.5,
        width: 0.1,
        height: 0.2,
        score: 0.9,
        hits: 3,
      ),
    ];
    final s = d.summarize(objs).toLowerCase();
    expect(s.contains('kitchen'), isFalse);
    expect(s.contains('living room'), isFalse);
    expect(s.contains('bedroom'), isFalse);
  });
}
