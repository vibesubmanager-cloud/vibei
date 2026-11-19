import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Live CameraX preview from the same session as FrameHub analysis.
class NativeCameraPreview extends StatelessWidget {
  const NativeCameraPreview({super.key});

  static const String viewType = 'oriente/camera_preview';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(color: Color(0xFF1A1A1A));
    }
    return AndroidView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}
