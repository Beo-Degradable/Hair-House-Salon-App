import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    Stream<QuerySnapshot<Map<String, dynamic>>> historyStream() {
      if (user == null) return const Stream.empty();
      // Remove server-side orderBy to avoid composite index requirement; we'll sort client-side.
      return FirebaseFirestore.instance
          .collection('history')
          .where('userUid', isEqualTo: user.uid)
          .snapshots();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (user != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: historyStream(),
              builder: (context, snap) {
                final hasItems = (snap.data?.docs.isNotEmpty ?? false);
                if (!hasItems) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Clear history',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear history?'),
                        content: const Text(
                          'This will remove all past purchases.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final batch = FirebaseFirestore.instance.batch();
                    for (final d in snap.data!.docs) {
                      batch.delete(d.reference);
                    }
                    await batch.commit();
                  },
                  icon: const Icon(Icons.delete_outline),
                );
              },
            ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Sign in to view history'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: historyStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load history'));
                }
                final docs = (snapshot.data?.docs ?? [])
                  ..sort((a, b) {
                    final ta = a.data()['timestamp'];
                    final tb = b.data()['timestamp'];
                    DateTime da;
                    DateTime db;
                    if (ta is Timestamp) {
                      da = ta.toDate();
                    } else if (ta is String) {
                      da =
                          DateTime.tryParse(ta) ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                    } else {
                      da = DateTime.fromMillisecondsSinceEpoch(0);
                    }
                    if (tb is Timestamp) {
                      db = tb.toDate();
                    } else if (tb is String) {
                      db =
                          DateTime.tryParse(tb) ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                    } else {
                      db = DateTime.fromMillisecondsSinceEpoch(0);
                    }
                    return db.compareTo(da); // descending
                  });
                if (docs.isEmpty) {
                  return const Center(child: Text('No purchases yet'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final it = d.data();
                    final title = (it['title'] ?? it['serviceName'] ?? 'Item')
                        .toString();
                    final ts = it['timestamp'];
                    String timeStr = '';
                    if (ts is Timestamp) {
                      final dt = ts.toDate();
                      timeStr =
                          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } else if (ts is String) {
                      timeStr = ts;
                    }
                    final priceRaw = (it['price'] ?? it['amount'] ?? '')
                        .toString();
                    final action = (it['action'] ?? '').toString();
                    final reason = (it['reason'] ?? '').toString();
                    final subtitle = [
                      if (timeStr.isNotEmpty) timeStr,
                      if (action.isNotEmpty) 'Action: $action',
                      if (reason.isNotEmpty) 'Reason: $reason',
                    ].join(' • ');
                    return ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: Text(priceRaw),
                    );
                  },
                );
              },
            ),
    );
  }
}
