import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/currency.dart';

class PurchasedProductsPage extends StatelessWidget {
  const PurchasedProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    Stream<QuerySnapshot<Map<String, dynamic>>> purchasesStream() {
      if (user == null) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection('payments')
          .where('userUid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Purchased Products')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: purchasesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No purchased products yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final items = (data['items'] as List?) ?? [];
              final total = data['total'] ?? 0;
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        createdAt != null
                            ? 'Purchased on ${createdAt.month}/${createdAt.day}/${createdAt.year}'
                            : 'Date unknown',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...items.map((item) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(item['title'] ?? 'Product')),
                            Text('x${item['quantity'] ?? 1}'),
                            Text(
                              PhpCurrency.formatFromString(
                                item['unitPrice'] ?? '0',
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total: ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(PhpCurrency.format(total)),
                        ],
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
}
