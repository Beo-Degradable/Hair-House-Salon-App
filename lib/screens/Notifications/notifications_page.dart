import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/services/app_state.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = AppState.I.notifications;
    final user = FirebaseAuth.instance.currentUser;
    // Upcoming appointments within lead window
    Stream<QuerySnapshot<Map<String, dynamic>>> _upcomingAppts() {
      if (user == null) return const Stream.empty();
      final now = DateTime.now();
      final lead = Duration(hours: AppState.I.reminderLeadHours);
      final until = now.add(lead);
      return FirebaseFirestore.instance
          .collection('appointments')
          .where('clientUid', isEqualTo: user.uid)
          .where('startTime', isGreaterThan: Timestamp.fromDate(now))
          .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(until))
          .orderBy('startTime')
          .snapshots();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: () => AppState.I.markAllNotificationsRead(),
              icon: const Icon(Icons.mark_email_read_outlined),
            ),
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: () => AppState.I.clearNotifications(),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _upcomingAppts(),
        builder: (context, snapshot) {
          final upcoming = <Map<String, dynamic>>[];
          if (snapshot.hasData) {
            for (final d in snapshot.data!.docs) {
              final data = d.data();
              final start = data['startTime'];
              DateTime? startDt;
              if (start is Timestamp) startDt = start.toDate();
              final service = (data['serviceName'] ?? 'Service').toString();
              final stylist = (data['stylistName'] ?? '').toString();
              final when = startDt != null
                  ? '${startDt.month}/${startDt.day} ${TimeOfDay.fromDateTime(startDt).format(context)}'
                  : '';
              upcoming.add({
                'title': 'Appointment reminder',
                'body': stylist.isNotEmpty
                    ? '$service with $stylist at $when'
                    : '$service at $when',
                'read': false,
                'isReminder': true,
              });
            }
          }

          final combined = [
            // Recent reminders first
            ...upcoming,
            // Then user/system notifications (purchases etc.)
            ...items.reversed,
          ];

          if (combined.isEmpty) {
            return const Center(child: Text('No notifications'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: combined.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final it = combined[i];
              final isReminder = it['isReminder'] == true;
              return Card(
                child: ListTile(
                  leading: Icon(
                    isReminder
                        ? Icons.event_available
                        : ((it['read'] as bool?) == true
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined),
                  ),
                  title: Text(it['title']?.toString() ?? ''),
                  subtitle: Text(it['body']?.toString() ?? ''),
                  onTap: () {
                    if (!isReminder) {
                      it['read'] = true;
                      AppState.I.refresh();
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
