import 'package:flutter/material.dart';
import 'package:hxhmobile/screens/Products/cart_page.dart';
import 'package:hxhmobile/screens/Products/checkout_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  // Firestore-backed products (fallback to empty list if stream not ready)
  List<Map<String, String>> _productsCache = const [];

  final Set<String> _selected = {};
  bool _selectionMode = false;

  int _parsePrice(String? s) {
    if (s == null) return 0;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  int get _selectedTotal {
    var total = 0;
    for (final id in _selected) {
      final p = _productsCache.firstWhere(
        (e) => e['id'] == id,
        orElse: () => {},
      );
      total += _parsePrice(p['price']);
    }
    return total;
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _buyNow(String id) {
    final p = _productsCache.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (p.isEmpty) return;
    // Navigate to checkout page with single item
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProductsCheckoutPage(items: [p])));
  }

  void _buySelected() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No products selected')));
      return;
    }
    final items = _productsCache
        .where((e) => _selected.contains(e['id']))
        .toList();
    // Keep selection state until user returns; don't clear immediately
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => ProductsCheckoutPage(items: items)),
        )
        .then((_) {
          // After returning from checkout, exit selection mode
          if (mounted) {
            setState(() {
              _selectionMode = false;
              _selected.clear();
            });
          }
        });
  }

  void _addToCart(String id) {
    final p = _productsCache.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (p.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to add to cart')),
      );
      return;
    }
    final cartDocId = '${user.uid}_${p['id']}';
    final cartRef = FirebaseFirestore.instance
        .collection('cart')
        .doc(cartDocId);
    cartRef
        .set({
          'userUid': user.uid,
          'productId': p['id'],
          'title': p['title'],
          'price': p['price'],
          'image': p['image'],
          'quantity': FieldValue.increment(1),
          'addedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .then((_) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CartPage()));
        })
        .catchError((e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to add to cart: $e')));
        });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: _cancelSelection,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('active', isEqualTo: true)
            .orderBy('sortOrder', descending: false)
            .limit(60)
            .snapshots(),
        builder: (context, snapshot) {
          final dataDocs = snapshot.data?.docs ?? [];
          _productsCache = dataDocs.map((d) {
            final data = d.data();
            return {
              'id': d.id,
              'title': (data['title'] ?? 'Product').toString(),
              'price': (data['price'] ?? '').toString(),
              'image': (data['imageUrl'] ?? '').toString(),
            };
          }).toList();
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_productsCache.isEmpty) {
            return const Center(child: Text('No products available'));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 900
                  ? 4
                  : width >= 600
                  ? 3
                  : 2; // 2 on phones
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: _productsCache.length,
                itemBuilder: (context, i) {
                  final p = _productsCache[i];
                  final id = p['id']!;
                  final title = p['title']!;
                  final price = p['price'] ?? '';
                  final selected = _selected.contains(id);
                  return InkWell(
                    onLongPress: () => _enterSelection(id),
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelected(id);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: selected
                            ? BorderSide(color: cs.primary, width: 2)
                            : BorderSide(color: Colors.transparent, width: 0),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 80,
                                width: double.infinity,
                                color: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.2,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              price,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                FittedBox(
                                  child: OutlinedButton(
                                    onPressed: () => _addToCart(id),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.shopping_cart_outlined,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                FittedBox(
                                  child: ElevatedButton(
                                    onPressed: () => _buyNow(id),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: const Text('Buy Now'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: !_selectionMode || _selected.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
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
                              'Items Selected (${_selected.length})',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₱${_selectedTotal.toString()}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _buySelected,
                        child: const Text('Buy Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
