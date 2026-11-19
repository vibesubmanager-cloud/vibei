import 'package:oriente_commands/oriente_commands.dart';
import 'package:test/test.dart';

void main() {
  const parser = TaskCommandParser();

  test('pause / resume / next / previous / stop reading', () {
    expect(parser.parseReadControl('pause reading'), 'pause');
    expect(parser.parseReadControl('continue reading'), 'resume');
    expect(parser.parseReadControl('resume'), 'resume');
    expect(parser.parseReadControl('read the next paragraph'), 'next');
    expect(parser.parseReadControl('repeat the last paragraph'), 'previous');
    expect(parser.parseReadControl('read that again'), 'previous');
    expect(parser.parseReadControl('stop reading'), 'stop');
  });
}
