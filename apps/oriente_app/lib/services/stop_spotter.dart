import 'package:oriente_platform/oriente_platform.dart';

/// Always-on stop spotter removed. Stub kept so existing imports compile.
class StopSpotter {
  StopSpotter(this._host);

  // ignore: unused_field
  final OrienteHost _host;
  void Function(StopAction action)? onStop;
  Duration? lastLatency;

  void setCurrentTts(String text) {}

  void arm() {}

  void disarm() {}

  void dispose() {}
}

enum StopAction { stopTask, muteSpeechOnly }
