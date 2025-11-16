import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cancellation_reason_page.dart';
import 'package:hxhmobile/utils/currency.dart';
import 'package:hxhmobile/utils/safe_casts.dart';

/// Displays the user's booked services from AppState.I.bookings
/// Each booking shows date/time range, service title, branch, stylist and price.
class MyBookingPage extends StatefulWidget {
  const MyBookingPage({super.key});

  @override
  State<MyBookingPage> createState() => _MyBookingPageState();
}

class _MyBookingPageState extends State<MyBookingPage> {
  final Set<String> _pointsProcessed = {};

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: user == null
          ? const Center(child: Text('Please sign in to view bookings'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _userAppointmentsStream(user.uid, user.email),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load bookings'));
                }
                // Sort docs by startTime descending on client
                final docs = (snapshot.data?.docs ?? [])
                  ..sort((a, b) {
                    final sa = a.data()['startTime'];
                    final sb = b.data()['startTime'];
                    final da = sa is Timestamp
                        ? sa.toDate()
                        : DateTime.fromMillisecondsSinceEpoch(0);
                    final db = sb is Timestamp
                        ? sb.toDate()
                        : DateTime.fromMillisecondsSinceEpoch(0);
                    return db.compareTo(da);
                  });
                if (docs.isEmpty) {
                  return const _EmptyBookings();
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
                    end ??= start.add(const Duration(minutes: 60));
                    final branch = (data['branch'] ?? '').toString();
                    final stylist = (data['stylistName'] ?? '').toString();
                    final status = (data['status'] ?? '').toString();
                    final isActive =
                        status != 'cancelled' &&
                        status != 'pending_cancel' &&
                        status != 'completed';

                    // New: show all booked services in one card
                    final services = safeListOfMaps(data['services']);
                    final totalDuration = (data['totalDuration'] as int?) ?? 60;
                    final priceTotal = services.fold<double>(0, (sum, s) {
                      final price = s['price'];
                      if (price is num) return sum + price;
                      if (price is String) {
                        return sum + (double.tryParse(price) ?? 0);
                      }
                      return sum;
                    });

                    // Award points if appointment is completed and not yet awarded
                    if (status == 'completed' && data['pointsAwarded'] != true && user.uid.isNotEmpty) {
                      final docId = d.id;
                      // Prevent duplicate processing in this client instance
                      if (!_pointsProcessed.contains(docId)) {
                        _pointsProcessed.add(docId);
                        // Compute points: 1 point per 100 pesos
                        final int points = (priceTotal / 100).floor();
                        if (points > 0) {
                          final usersRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                          final apptRef = FirebaseFirestore.instance.collection('appointments').doc(docId);
                          FirebaseFirestore.instance.runTransaction((tx) async {
                            final snap = await tx.get(apptRef);
                            if (snap.exists && (snap.data()?['pointsAwarded'] == true)) return;
                            // Increment user's points and mark appointment as awarded
                            tx.update(usersRef, {'points': FieldValue.increment(points)});
                            tx.update(apptRef, {
                              'pointsAwarded': true,
                              'pointsEarned': points,
                              'pointsAwardedAt': FieldValue.serverTimestamp(),
                            });
                          }).catchError((e) {
                            // Best-effort; log or notify user
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to award points: $e')));
                            }
                          });
                        } else {
                          // Still mark as processed to avoid repeated checks
                          final apptRef = FirebaseFirestore.instance.collection('appointments').doc(d.id);
                          apptRef.set({'pointsAwarded': true, 'pointsEarned': 0}, SetOptions(merge: true));
                        }
                      }
                    }

                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Booked Services',
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(fontSize: 22),
                            ),
                            ...services.map(
                              (s) => Text(
                                '- ${s['title'] ?? 'Service'} (${s['duration'] ?? ''})',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Price: ₱${priceTotal.toStringAsFixed(2)}',
                            ),
                            Text('Total Duration: $totalDuration min'),
                          ],
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
                            if (isActive)
                              TextButton.icon(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.redAccent,
                                ),
                                label: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CancellationReasonPage(
                                        appointmentId: d.id,
                                        appointmentStart: start!,
                                        serviceName: services.isNotEmpty
                                            ? services[0]['title'] ?? ''
                                            : '',
                                        currentStatus: status,
                                      ),
                                    ),
                                  );
                                },
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

  // Primary stream: if clientUid indexed, direct query. If not found (e.g., legacy docs
  // missing clientUid but have clientEmail), we fallback client-side in the builder.
  Stream<QuerySnapshot<Map<String, dynamic>>> _userAppointmentsStream(
    String uid,
    String? email,
  ) {
    // Remove server-side orderBy to avoid composite index requirement.
    // We'll sort client-side by startTime.
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .snapshots();
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

class _EmptyBookings extends StatelessWidget {
  const _EmptyBookings();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'You have no appointments',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Book a service to see it listed here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
