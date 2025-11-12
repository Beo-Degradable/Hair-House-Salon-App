import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hxhmobile/services/app_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// SettingsPage shows a mix of local-only preferences (appearance, export/reset)
/// and roaming preferences synced to Firestore (reminders, lead time, badge, checkout navigation).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocStream =
        user == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? const <String, dynamic>{};

          // Firestore-backed values with local fallbacks
          final remindersEnabled =
              (data['remindersEnabled'] as bool?) ??
              AppState.I.remindersEnabled;
          final reminderLeadHours = (data['reminderLeadHours'] is num)
              ? (data['reminderLeadHours'] as num).toInt()
              : AppState.I.reminderLeadHours;
          final badgeEnabled =
              (data['badgeEnabled'] as bool?) ?? AppState.I.badgeEnabled;
          final navigateHistory =
              (data['navigateToHistoryOnCheckout'] as bool?) ??
              AppState.I.navigateToHistoryOnCheckout;

          return AnimatedBuilder(
            animation: AppState.I,
            builder: (context, _) {
              return ListView(
                children: [
                  // ...existing code...
                  const Divider(),
                  const ListTile(
                    title: Text('Notifications'),
                    subtitle: Text('Reminders and badges'),
                  ),
                  SwitchListTile(
                    title: const Text('Appointment reminders'),
                    subtitle: const Text('Get a reminder before your booking'),
                    value: remindersEnabled,
                    onChanged: (v) async {
                      AppState.I.setRemindersEnabled(v);
                      if (user != null) {
                        await _mergeUserSettings({'remindersEnabled': v});
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Reminder lead time'),
                    subtitle: Text('$reminderLeadHours hour(s) before'),
                    trailing: DropdownButton<int>(
                      value: reminderLeadHours,
                      items: const [24, 3, 1]
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e,
                              child: Text('$e h'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        if (v != null) {
                          AppState.I.setReminderLeadHours(v);
                          if (user != null) {
                            await _mergeUserSettings({'reminderLeadHours': v});
                          }
                        }
                      },
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Show red-dot badge'),
                    subtitle: const Text(
                      'Indicate unread notifications on Home',
                    ),
                    value: badgeEnabled,
                    onChanged: (v) async {
                      AppState.I.setBadgeEnabled(v);
                      if (user != null) {
                        await _mergeUserSettings({'badgeEnabled': v});
                      }
                    },
                  ),

                  const Divider(),
                  const ListTile(
                    title: Text('Checkout'),
                    subtitle: Text('After purchase actions'),
                  ),
                  SwitchListTile(
                    title: const Text('Go to History after checkout'),
                    value: navigateHistory,
                    onChanged: (v) async {
                      AppState.I.setNavigateToHistoryOnCheckout(v);
                      if (user != null) {
                        await _mergeUserSettings({
                          'navigateToHistoryOnCheckout': v,
                        });
                      }
                    },
                  ),

                  const Divider(),
                  const ListTile(title: Text('Data & Storage')),
                  ListTile(
                    leading: const Icon(Icons.save_alt_outlined),
                    title: const Text('Export data (JSON)'),
                    subtitle: const Text('Copy your app data as JSON'),
                    onTap: () async {
                      final json = AppState.I.exportStateJson();
                      await Clipboard.setData(ClipboardData(text: json));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Data copied to clipboard'),
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: const Text('Reset app data'),
                    subtitle: const Text(
                      'Clear cart, history, bookings and notifications',
                    ),
                    onTap: () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reset app data?'),
                          content: const Text(
                            'This will clear cart, history, bookings and notifications. This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      );
                      if (sure == true) {
                        await AppState.I.resetAll();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('App data reset')),
                          );
                        }
                      }
                    },
                  ),

                  const Divider(),
                  const ListTile(title: Text('Account')),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Log out'),
                    onTap: () async {
                      bool proceed = true;
                      if (AppState.I.confirmationsEnabled) {
                        proceed =
                            await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Log out?'),
                                content: const Text(
                                  'You will need to log in again next time.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Log out'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      }
                      if (!proceed) return;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('is_logged_in', false);
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (_) {}
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _mergeUserSettings(Map<String, dynamic> patch) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
