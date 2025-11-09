import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ChangeNotifier-based AppState that stores in-memory lists and persists
/// them to SharedPreferences under a single JSON key. This provides the
/// basic API used across the app: cart, history, bookings, notifications and
/// several persisted settings.
class AppState extends ChangeNotifier {
  AppState._internal();
  static final AppState I = AppState._internal();

  static const _prefsKey = 'hxhmobile_app_state_v1';

  // In-memory state
  final List<Map<String, dynamic>> bookings = [];
  final List<Map<String, String>> history = [];
  final List<Map<String, String>> cart = [];
  final List<Map<String, dynamic>> notifications = [];

  // Settings/defaults
  bool remindersEnabled = true;
  int reminderLeadHours = 24;
  bool confirmationsEnabled = true;
  bool badgeEnabled = true;
  bool navigateToHistoryOnCheckout = true;

  // Basic lifecycle: load persisted state
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final obj = jsonDecode(raw) as Map<String, dynamic>;

      // bookings
      bookings.clear();
      if (obj['bookings'] is List) {
        for (final b in obj['bookings']) {
          if (b is Map) bookings.add(Map<String, dynamic>.from(b));
        }
      }

      // history
      history.clear();
      if (obj['history'] is List) {
        for (final h in obj['history']) {
          if (h is Map) history.add(Map<String, String>.from(h));
        }
      }

      // cart
      cart.clear();
      if (obj['cart'] is List) {
        for (final c in obj['cart']) {
          if (c is Map) cart.add(Map<String, String>.from(c));
        }
      }

      // notifications
      notifications.clear();
      if (obj['notifications'] is List) {
        for (final n in obj['notifications']) {
          if (n is Map) notifications.add(Map<String, dynamic>.from(n));
        }
      }

      remindersEnabled = obj['remindersEnabled'] ?? remindersEnabled;
      reminderLeadHours = obj['reminderLeadHours'] ?? reminderLeadHours;
      confirmationsEnabled =
          obj['confirmationsEnabled'] ?? confirmationsEnabled;
      badgeEnabled = obj['badgeEnabled'] ?? badgeEnabled;
      navigateToHistoryOnCheckout =
          obj['navigateToHistoryOnCheckout'] ?? navigateToHistoryOnCheckout;
    } catch (e) {
      // ignore parse errors and continue with defaults
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final obj = <String, dynamic>{
      'bookings': bookings,
      'history': history,
      'cart': cart,
      'notifications': notifications,
      'remindersEnabled': remindersEnabled,
      'reminderLeadHours': reminderLeadHours,
      'confirmationsEnabled': confirmationsEnabled,
      'badgeEnabled': badgeEnabled,
      'navigateToHistoryOnCheckout': navigateToHistoryOnCheckout,
    };
    await prefs.setString(_prefsKey, jsonEncode(obj));
  }

  // Cart operations
  void addToCart(Map<String, String> item) {
    cart.add(Map.from(item));
    _persist();
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    _persist();
    notifyListeners();
  }

  /// Purchase the provided [items] or the current cart if [items] is null.
  /// Moves items into history with a timestamp.
  void purchaseItems([Iterable<Map<String, String>>? items]) {
    final now = DateTime.now().toIso8601String();
    final source = items ?? cart;
    for (final c in source) {
      final entry = Map<String, String>.from(c);
      entry['time'] = now;
      history.add(entry);
    }
    // If we purchased the cart (no explicit items passed), clear it.
    if (items == null) cart.clear();
    _persist();
    notifyListeners();
  }

  // History
  void clearHistory() {
    history.clear();
    _persist();
    notifyListeners();
  }

  // Bookings
  void addBooking({
    required String serviceId,
    required String serviceTitle,
    required String servicePrice,
    required DateTime date,
    required int durationMinutes,
    required String branch,
    required String stylist,
  }) {
    final start = date.toIso8601String();
    final end = date.add(Duration(minutes: durationMinutes)).toIso8601String();
    bookings.add({
      'serviceId': serviceId,
      'serviceTitle': serviceTitle,
      'servicePrice': servicePrice,
      'date': start,
      'end': end,
      'durationMinutes': durationMinutes,
      'branch': branch,
      'stylist': stylist,
    });
    _persist();
    notifyListeners();
  }

  // Notifications
  void addNotification(Map<String, dynamic> note) {
    notifications.add(Map.from(note));
    _persist();
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (final n in notifications) {
      n['read'] = true;
    }
    _persist();
    notifyListeners();
  }

  void clearNotifications() {
    notifications.clear();
    _persist();
    notifyListeners();
  }

  /// Simulate a refresh of notifications — in a real app you'd fetch from
  /// a server. Here we simply mark any 'new' notifications as present.
  Future<void> refresh() async {
    // no-op simulation; keep for API compatibility
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifyListeners();
  }

  // Settings mutators
  void setRemindersEnabled(bool v) {
    remindersEnabled = v;
    _persist();
    notifyListeners();
  }

  void setReminderLeadHours(int h) {
    reminderLeadHours = h;
    _persist();
    notifyListeners();
  }

  void setBadgeEnabled(bool v) {
    badgeEnabled = v;
    _persist();
    notifyListeners();
  }

  void setNavigateToHistoryOnCheckout(bool v) {
    navigateToHistoryOnCheckout = v;
    _persist();
    notifyListeners();
  }

  // Export / reset
  String exportStateJson() {
    final obj = <String, dynamic>{
      'bookings': bookings,
      'history': history,
      'cart': cart,
      'notifications': notifications,
      'remindersEnabled': remindersEnabled,
      'reminderLeadHours': reminderLeadHours,
      'confirmationsEnabled': confirmationsEnabled,
      'badgeEnabled': badgeEnabled,
      'navigateToHistoryOnCheckout': navigateToHistoryOnCheckout,
    };
    return jsonEncode(obj);
  }

  Future<void> resetAll() async {
    bookings.clear();
    history.clear();
    cart.clear();
    notifications.clear();
    remindersEnabled = true;
    reminderLeadHours = 24;
    confirmationsEnabled = true;
    badgeEnabled = true;
    navigateToHistoryOnCheckout = true;
    await _persist();
    notifyListeners();
  }
}
