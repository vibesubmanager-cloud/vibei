import 'package:oriente_commands/oriente_commands.dart';
void main() {
  const p = IntentParser();
  print(p.parse('look a bottle for me').runtimeType);
  print(p.parse('look a bottle').runtimeType);
  print(p.parse('look for a bottle').runtimeType);
}
