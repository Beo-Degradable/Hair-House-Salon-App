import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cancellation_reason_page.dart';

/// Displays the user's booked services from AppState.I.bookings
/// Each booking shows date/time range, service title, branch, stylist and price.
class MyBookingPage extends StatelessWidget {
  const MyBookingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: user == null
          ? const Center(child: Text('Please sign in to view bookings'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('appointments')
                  .where('clientUid', isEqualTo: user.uid)
                  .orderBy('startTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load bookings'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No bookings yet'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final startField = data['startTime'];
                    final endField = data['endTime'];
                    DateTime? start;
                    DateTime? end;
                    if (startField is Timestamp) start = startField.toDate();
                    if (endField is Timestamp) end = endField.toDate();
                    start ??= DateTime.now();
                    final durationMin = (data['duration'] as int?) ?? 60;
                    end ??= start.add(Duration(minutes: durationMin));
                    final title = (data['serviceName'] ?? 'Service').toString();
                    final priceRaw = data['price'];
                    final branch = (data['branch'] ?? '').toString();
                    final stylist = (data['stylistName'] ?? '').toString();
                    final status = (data['status'] ?? '').toString();
                    String priceDisplay = '';
                    if (priceRaw is num) {
                      priceDisplay = '₱${priceRaw.toString()}';
                    } else if (priceRaw != null) {
                      priceDisplay = priceRaw.toString();
                    }
                    final hoursUntil = start.difference(DateTime.now()).inHours;
                    final cancellable =
                        status != 'cancelled' &&
                        status != 'pending_cancel' &&
                        hoursUntil >= 0;

                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          child: Text(title.isNotEmpty ? title[0] : '?'),
                        ),
                        title: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(_formatRange(start, end)),
                            if (branch.isNotEmpty || stylist.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (branch.isNotEmpty) 'Branch: $branch',
                                  if (stylist.isNotEmpty) 'Stylist: $stylist',
                                ].join(' • '),
                              ),
                            ],
                            const SizedBox(height: 4),
                            if (status.isNotEmpty)
                              Text(
                                'Status: $status',
                                style: TextStyle(
                                  color: status == 'cancelled'
                                      ? Colors.redAccent
                                      : status == 'pending_cancel'
                                      ? Colors.orangeAccent
                                      : Colors.greenAccent,
                                ),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              priceDisplay,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (cancellable)
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CancellationReasonPage(
                                        appointmentId: d.id,
                                        appointmentStart: start!,
                                        serviceName: title,
                                        currentStatus: status,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Cancel'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatRange(DateTime start, DateTime end) {
    return '${_formatDate(start)}  ${_formatTime(start)} - ${_formatTime(end)}';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m2 = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$h12:$m2 $ampm';
  }
}
