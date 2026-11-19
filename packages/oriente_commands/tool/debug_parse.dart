import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';

void main() {
  const p = IntentParser();
  for (final u in [
    'can you see the word exhibitor',
    'see the word exhibitor',
    'Show me where the word entrance is written',
    'find a word',
    'find egg zib',
    'find the word exhibition',
    'where is the bottle',
  ]) {
    final i = p.parse(u);
    print('$u => ${i.runtimeType} ${_detail(i)}');
  }
  final b = p.parseBest(['find egg zib', 'find the word exhibition']);
  print('best => ${b.runtimeType} ${_detail(b)}');
}

String _detail(AppIntent i) {
  if (i is TextSearchIntent) return i.query;
  if (i is ObjectSearchIntent) return i.query;
  if (i is ClarifyIntent) return i.question;
  return '';
}
