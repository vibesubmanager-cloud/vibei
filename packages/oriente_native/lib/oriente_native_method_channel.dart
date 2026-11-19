import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'oriente_native_platform_interface.dart';

/// An implementation of [OrienteNativePlatform] that uses method channels.
class MethodChannelOrienteNative extends OrienteNativePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('oriente_native');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
