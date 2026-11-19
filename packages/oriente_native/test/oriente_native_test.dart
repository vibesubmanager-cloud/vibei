import 'package:flutter_test/flutter_test.dart';
import 'package:oriente_native/oriente_native.dart';
import 'package:oriente_native/oriente_native_platform_interface.dart';
import 'package:oriente_native/oriente_native_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockOrienteNativePlatform
    with MockPlatformInterfaceMixin
    implements OrienteNativePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final OrienteNativePlatform initialPlatform = OrienteNativePlatform.instance;

  test('$MethodChannelOrienteNative is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelOrienteNative>());
  });

  test('getPlatformVersion', () async {
    OrienteNative orienteNativePlugin = OrienteNative();
    MockOrienteNativePlatform fakePlatform = MockOrienteNativePlatform();
    OrienteNativePlatform.instance = fakePlatform;

    expect(await orienteNativePlugin.getPlatformVersion(), '42');
  });
}
