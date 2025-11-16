import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/screens/ServicesPage/services_page.dart';

class PointsPage extends StatefulWidget {
  const PointsPage({super.key});

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  int _points = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _points = 0;
        _loading = false;
      });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final pts = snap.data()?['points'];
      setState(() {
        _points = (pts is int) ? pts : (pts is num ? pts.toInt() : 0);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _points = 0;
        _loading = false;
      });
    }
  }

  Future<void> _redeemAllPoints() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_points <= 0) return;
    final pointsToUse = _points;
    final amount = pointsToUse * 100; // 1 point = 100 pesos
    final vouchers = FirebaseFirestore.instance.collection('vouchers');
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        final current = userSnap.data()?['points'];
        final currentPts = (current is int) ? current : (current is num ? current.toInt() : 0);
        if (currentPts < pointsToUse) {
          throw Exception('Not enough points');
        }
        // create voucher
        final vDoc = vouchers.doc();
        tx.set(vDoc, {
          'userUid': user.uid,
          'pointsUsed': pointsToUse,
          'amount': amount,
          'createdAt': FieldValue.serverTimestamp(),
          'used': false,
        });
        // decrement points
        tx.update(userRef, {'points': FieldValue.increment(-pointsToUse)});
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Redeemed $pointsToUse points for ₱$amount voucher')));
      }
      await _loadPoints();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to redeem points: $e')));
      }
      await _loadPoints();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Points')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your points', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Points: $_points', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Equivalent: ₱${_points * 100}', style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 12),
                          const Text('You can redeem points as a voucher. 1 point = ₱100.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _points > 0 ? _redeemAllPoints : null,
                    child: const Text('Redeem all points'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Open services page with points prefill so user can pick a service and use points
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServicesPage(prefillUsePoints: true)));
                    },
                    icon: const Icon(Icons.local_activity),
                    label: const Text('Use points to book'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      // Open vouchers list for user (optional)
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _VouchersPage()));
                    },
                    child: const Text('View my vouchers'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _VouchersPage extends StatelessWidget {
  const _VouchersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(appBar: AppBar(title: const Text('Vouchers')), body: const Center(child: Text('Sign in to view vouchers')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My Vouchers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('vouchers').where('userUid', isEqualTo: user.uid).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No vouchers found'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final used = data['used'] == true;
              final amount = data['amount'] ?? 0;
              return Card(
                child: ListTile(
                  title: Text('₱$amount voucher'),
                  subtitle: Text(used ? 'Used' : 'Available'),
                  trailing: used ? null : TextButton(onPressed: () {}, child: const Text('Use')),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
