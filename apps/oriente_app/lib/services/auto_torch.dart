import 'package:oriente_platform/oriente_platform.dart';

/// Smooth luma → auto torch (once per task, stays on until end).
class AutoTorchController {
  AutoTorchController(this._host);

  final OrienteHost _host;
  final List<double> _window = [];
  bool enabled = true;
  bool torchOn = false;
  bool _announcedStillDark = false;
  static const darkThreshold = 0.18;
  static const stillDarkThreshold = 0.12;

  Future<void> onBrightness(double luma) async {
    if (!enabled || torchOn) {
      if (torchOn && !_announcedStillDark && luma < stillDarkThreshold) {
        _announcedStillDark = true;
        await _host.speak("It's too dark to see.", interrupt: false);
      }
      return;
    }
    _window.add(luma.clamp(0.0, 1.0));
    if (_window.length > 12) _window.removeAt(0); // ~1.2s at 100ms
    if (_window.length < 8) return;
    final avg = _window.reduce((a, b) => a + b) / _window.length;
    if (avg >= darkThreshold) return;
    try {
      await _host.setTorch(true);
      torchOn = true;
      // No haptic — keep flashlight silent.
      await _host.playEarcon('thinkingStart');
    } catch (_) {
      // No flash — ignore.
    }
  }

  Future<void> end() async {
    _window.clear();
    _announcedStillDark = false;
    if (torchOn) {
      torchOn = false;
      try {
        await _host.setTorch(false);
      } catch (_) {}
    }
  }
}
