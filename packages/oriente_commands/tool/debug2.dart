import 'package:oriente_commands/oriente_commands.dart';
import 'package:oriente_domain/oriente_domain.dart';

void main() {
  const p = IntentParser();
  const u = 'hello can you look a bottle for me';
  final i = p.parse(u);
  print(i.runtimeType);
  if (i is ObjectSearchIntent) print(i.query);
  if (i is TextSearchIntent) print(i.query);
  if (i is ClarifyIntent) print(i.question);
  if (i is DescribeIntent) print('describe');
  if (i is UnsupportedIntent) print(i.message);
}
