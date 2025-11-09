import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Android-only local notification helper for appointment reminders.
///
/// Notes:
/// - Does not alter any UI or existing functions. Safe to import and call.
/// - Schedules a high-importance notification before an appointment.
/// - Payload includes a route hint ("/appointments") and optional appointmentId.
/// - To navigate when tapped, handle it in your app start (optional), e.g. by
///   checking notification launch details and pushing the Appointments page.
class AndroidNotificationService {
  AndroidNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Ensure plugin and timezone are initialized (idempotent).
  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    // Init timezone database (best-effort).
    try {
      tz.initializeTimeZones();
      // Let tz use the device's local zone if available.
      // If we can't determine an exact IANA zone, tz.local will still work with wall clock times.
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = const InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      // Optional: you can listen for taps while app is in foreground/background.
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('Notification tapped: ${resp.payload}');
        // Intentionally no navigation here to avoid modifying app flow/layout.
        // You may wire this in main.dart to route to '/appointments' if desired.
      },
    );

    // Android 13+ requires POST_NOTIFICATIONS runtime permission.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Schedule a reminder for an upcoming appointment on Android.
  ///
  /// - [appointmentStart] is the actual appointment start time (local time).
  /// - [leadMinutes] is how many minutes before the start to notify the user.
  /// - [serviceName] and [stylistName] are used to compose the notification text.
  /// - [appointmentId] is embedded in payload for deep linking (optional).
  ///
  /// This function is safe to call without prior initialization; it will
  /// initialize on demand.
  static Future<void> scheduleAppointmentReminder({
    required DateTime appointmentStart,
    int leadMinutes = 30,
    required String serviceName,
    String? stylistName,
    String? appointmentId,
  }) async {
    await ensureInitialized();

    final scheduled = appointmentStart.subtract(Duration(minutes: leadMinutes));
    if (scheduled.isBefore(DateTime.now())) {
      // Don't schedule in the past.
      return;
    }

    const channelId = 'appointments_channel';
    const channelName = 'Appointments';
    const channelDesc = 'Reminders for upcoming appointments';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      styleInformation: const DefaultStyleInformation(true, true),
    );

    final details = NotificationDetails(android: androidDetails);

    final title = 'Appointment reminder';
    final body = stylistName != null && stylistName.trim().isNotEmpty
        ? '$serviceName with $stylistName is coming up'
        : '$serviceName is coming up';

    final payload = 'route=/appointments&appointmentId=${appointmentId ?? ''}';

    // Use timezone-aware schedule to improve reliability.
    final tzTime = tz.TZDateTime.from(scheduled, tz.local);

    // Use a derived notification id to avoid collisions if you schedule many.
    final id =
        appointmentId?.hashCode ?? tzTime.millisecondsSinceEpoch & 0x7fffffff;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
      matchDateTimeComponents: null,
    );
  }
}
