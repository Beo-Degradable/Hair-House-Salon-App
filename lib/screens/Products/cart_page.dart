import 'package:flutter/material.dart';
import 'package:hxhmobile/screens/Products/checkout_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/utils/currency.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _selectionMode = false;
  final Set<String> _selectedDocIds = {};

  void _enterSelection(String docId) {
    setState(() {
      _selectionMode = true;
      _selectedDocIds.add(docId);
    });
  }

  void _toggleSelected(String docId) {
    setState(() {
      if (_selectedDocIds.contains(docId)) {
        _selectedDocIds.remove(docId);
      } else {
        _selectedDocIds.add(docId);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedDocIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    Stream<QuerySnapshot<Map<String, dynamic>>> cartStream() {
      if (user == null) return const Stream.empty();
      // Avoid composite index requirement by skipping server-side orderBy;
      // we'll sort by addedAt on the client.
      return FirebaseFirestore.instance
          .collection('cart')
          .where('userUid', isEqualTo: user.uid)
          .snapshots();
    }

    int parsePrice(String? s) {
      if (s == null) return 0;
      final d = s.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(d) ?? 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: _cancelSelection,
              icon: const Icon(Icons.close),
            ),
          if (user != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: cartStream(),
              builder: (context, snap) {
                final hasItems = (snap.data?.docs.isNotEmpty ?? false);
                if (!hasItems) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Clear cart',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear cart?'),
                        content: const Text('Remove all items from your cart?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final docs = snap.data!.docs;
                    final batch = FirebaseFirestore.instance.batch();
                    for (final d in docs) {
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
          ? const Center(child: Text('Sign in to view cart'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: cartStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load cart'));
                }
                var docs = snapshot.data?.docs ?? [];
                // Sort by addedAt desc if present
                docs.sort((a, b) {
                  final ta = a.data()['addedAt'];
                  final tb = b.data()['addedAt'];
                  final da = ta is Timestamp
                      ? ta.toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  final db = tb is Timestamp
                      ? tb.toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                });
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Your cart is empty for now.'),
                  );
                }
                return LayoutBuilder(
                  builder: (ctx, constraints) {
                    // Use a shrink-wrapped ListView inside a Scrollbar to avoid bottom overflow in very tight layouts.
                    return Scrollbar(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        // extra bottom padding so bottom bar doesn't cover last item
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final d = docs[i];
                          final it = d.data();
                          final docId = d.id;
                          final selected = _selectedDocIds.contains(docId);
                          final title = (it['title'] ?? 'Item').toString();
                          final rawPrice = (it['price'] ?? '').toString();
                          final quantity = (it['quantity'] is num)
                              ? (it['quantity'] as num).toInt()
                              : null;
                          return InkWell(
                            onLongPress: () => _enterSelection(docId),
                            onTap: () {
                              if (_selectionMode) _toggleSelected(docId);
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 60),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                selected: selected,
                                leading: const Icon(
                                  Icons.shopping_bag_outlined,
                                ),
                                title: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: quantity != null
                                    ? Text('Qty: $quantity')
                                    : null,
                                trailing: _selectionMode
                                    ? Text(
                                        PhpCurrency.formatFromString(rawPrice),
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            PhpCurrency.formatFromString(
                                              rawPrice,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            height: 26,
                                            child: OutlinedButton(
                                              onPressed: () {
                                                final item = <String, String>{
                                                  'id':
                                                      (it['productId'] ?? docId)
                                                          .toString(),
                                                  'title': title,
                                                  'price': rawPrice,
                                                  'image': (it['image'] ?? '')
                                                      .toString(),
                                                };
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ProductsCheckoutPage(
                                                          items: [item],
                                                        ),
                                                  ),
                                                );
                                              },
                                              style: OutlinedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                              ),
                                              child: const Text(
                                                'Buy Now',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: user == null
          ? null
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: cartStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    snapshot.hasError) {
                  return const SizedBox.shrink();
                }
                var docs = snapshot.data?.docs ?? [];
                docs.sort((a, b) {
                  final ta = a.data()['addedAt'];
                  final tb = b.data()['addedAt'];
                  final da = ta is Timestamp
                      ? ta.toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  final db = tb is Timestamp
                      ? tb.toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                });
                if (!_selectionMode ||
                    _selectedDocIds.isEmpty ||
                    docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                final selectedDocs = docs
                    .where((d) => _selectedDocIds.contains(d.id))
                    .toList();
                final items = selectedDocs.map((d) => d.data()).toList();
                final total = items.fold<int>(
                  0,
                  (acc, e) => acc + parsePrice(e['price']?.toString()),
                );
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Items Selected (${_selectedDocIds.length})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  PhpCurrency.formatInt(total),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                final selectedItems = selectedDocs.map((d) {
                                  final it = d.data();
                                  return <String, String>{
                                    'id': (it['productId'] ?? d.id).toString(),
                                    'title': (it['title'] ?? 'Product')
                                        .toString(),
                                    'price': (it['price'] ?? '').toString(),
                                    'image': (it['image'] ?? '').toString(),
                                  };
                                }).toList();
                                Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (_) => ProductsCheckoutPage(
                                          items: selectedItems,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (!mounted) return;
                                      _cancelSelection();
                                    });
                              },
                              child: const Text(
                                'Buy Now',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
