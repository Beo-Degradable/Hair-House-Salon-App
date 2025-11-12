import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/services/app_state.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Helper: Upcoming appointments within lead window
    Stream<QuerySnapshot<Map<String, dynamic>>> upcomingAppts() {
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

    // Helper: User notifications from Firestore
    Stream<QuerySnapshot<Map<String, dynamic>>> userNotifications() {
      if (user == null) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection('notifications')
          .where('userUid', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .snapshots();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: userNotifications(),
        builder: (context, notifSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: upcomingAppts(),
            builder: (context, apptSnapshot) {
              final notifications = <Map<String, dynamic>>[];
              if (notifSnapshot.hasData) {
                for (final d in notifSnapshot.data!.docs) {
                  final data = d.data();
                  notifications.add({
                    'id': d.id,
                    'title': data['title'] ?? '',
                    'body': data['body'] ?? '',
                    'type': data['type'] ?? '',
                    'timestamp': data['timestamp'],
                    'read': data['read'] ?? false,
                  });
                }
              }
              final upcoming = <Map<String, dynamic>>[];
              if (apptSnapshot.hasData) {
                for (final d in apptSnapshot.data!.docs) {
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
                    'type': 'reminder',
                  });
                }
              }
              final combined = [...notifications, ...upcoming];
              if (combined.isEmpty) {
                return const Center(child: Text('No notifications'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: combined.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final it = combined[i];
                  final isReminder = it['type'] == 'reminder';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isReminder
                            ? Icons.event_available
                            : Icons.notifications_active_outlined,
                      ),
                      title: Text(it['title']?.toString() ?? ''),
                      subtitle: Text(it['body']?.toString() ?? ''),
                      trailing: !isReminder
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.done),
                                  tooltip: 'Mark as read',
                                  onPressed: () async {
                                    final id = it['id'];
                                    await FirebaseFirestore.instance
                                        .collection('notifications')
                                        .doc(id)
                                        .update({'read': true});
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    final id = it['id'];
                                    await FirebaseFirestore.instance
                                        .collection('notifications')
                                        .doc(id)
                                        .delete();
                                  },
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
