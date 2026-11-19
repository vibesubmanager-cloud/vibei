import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

final veThemeModeProvider =
    StateNotifierProvider<VeThemeModeNotifier, VeThemeMode>((ref) {
  return VeThemeModeNotifier();
});

class VeThemeModeNotifier extends StateNotifier<VeThemeMode> {
  VeThemeModeNotifier() : super(VeThemeMode.dark) {
    _load();
  }

  static const _key = 'veThemeMode';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    state = switch (raw) {
      'system' => VeThemeMode.system,
      'light' => VeThemeMode.light,
      'highContrast' => VeThemeMode.highContrast,
      _ => VeThemeMode.dark,
    };
  }

  Future<void> setMode(VeThemeMode mode) async {
    state = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      switch (mode) {
        VeThemeMode.system => 'system',
        VeThemeMode.dark => 'dark',
        VeThemeMode.light => 'light',
        VeThemeMode.highContrast => 'highContrast',
      },
    );
  }
}

ThemeData resolveVeTheme(VeThemeMode mode, Brightness platform) {
  switch (mode) {
    case VeThemeMode.dark:
      return OrienteTheme.dark();
    case VeThemeMode.light:
      return OrienteTheme.lightTheme();
    case VeThemeMode.highContrast:
      return OrienteTheme.highContrast();
    case VeThemeMode.system:
      return platform == Brightness.dark
          ? OrienteTheme.dark()
          : OrienteTheme.lightTheme();
  }
}
