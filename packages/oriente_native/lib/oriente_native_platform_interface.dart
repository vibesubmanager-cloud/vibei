import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'oriente_native_method_channel.dart';

abstract class OrienteNativePlatform extends PlatformInterface {
  /// Constructs a OrienteNativePlatform.
  OrienteNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static OrienteNativePlatform _instance = MethodChannelOrienteNative();

  /// The default instance of [OrienteNativePlatform] to use.
  ///
  /// Defaults to [MethodChannelOrienteNative].
  static OrienteNativePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OrienteNativePlatform] when
  /// they register themselves.
  static set instance(OrienteNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
