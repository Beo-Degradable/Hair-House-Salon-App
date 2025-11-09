import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  ThemeController._internal();

  static const _prefKey = 'theme_mode'; // 'light' | 'dark' | 'system'

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefKey);
    switch (v) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      case 'system':
        _mode = ThemeMode.system;
        break;
      default:
        _mode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final v = m == ThemeMode.light
        ? 'light'
        : m == ThemeMode.system
        ? 'system'
        : 'dark';
    await prefs.setString(_prefKey, v);
  }

  Future<void> toggleDark(bool value) async {
    await setMode(value ? ThemeMode.dark : ThemeMode.light);
  }
}
