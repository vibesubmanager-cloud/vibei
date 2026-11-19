import 'package:oriente_commands/oriente_commands.dart';

void main() {
  const p = IntentParser();
  for (final t in [
    'can you look for a bottle',
    'where is the bottle',
    "where's the bottle",
    'can you look a bottle for me',
    'find a bottle',
    "I'm looking for a water bottle",
    'I am looking for a water bottle',
    'search for the bottle please',
    'look for a bottle',
    'do you see a bottle',
    'is there a bottle',
  ]) {
    final i = p.parse(t);
    print('$t => ${i.runtimeType} $i');
  }
}
