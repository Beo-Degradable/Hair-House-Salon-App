import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/screens/Products/cart_page.dart';
import 'package:hxhmobile/screens/Products/checkout_page.dart';
import 'package:hxhmobile/utils/currency.dart';

/// Simplified, defensive Products page.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final List<Map<String, dynamic>> _loadedProducts = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  final int _pageSize = 12;

  final TextEditingController _searchCtrl = TextEditingController();
  String _category = 'All';
  bool _inStockOnly = false;
  bool _onSaleOnly = false;
  String _priceSort = 'default';

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  int _parsePrice(String? s) {
    if (s == null) return 0;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  Future<void> _loadInitial() async {
    if (_loading) return;
    _loading = true;
    setState(() {});
    try {
      // Debug: log query parameters so runtime logs show what's requested
      // ignore: avoid_print
      print('ProductsPage: _loadInitial() — category=$_category, pageSize=$_pageSize');
      Query q = FirebaseFirestore.instance.collection('products').orderBy('title');
      if (_category != 'All') q = q.where('category', isEqualTo: _category);
      final snap = await q.limit(_pageSize).get();
      final docs = snap.docs;
      // ignore: avoid_print
      print('ProductsPage: _loadInitial() — got ${docs.length} docs');
      if (docs.isNotEmpty) {
        // print first few ids for diagnosis
        // ignore: avoid_print
        print('ProductsPage: doc ids: ${docs.take(5).map((d) => d.id).toList()}');
        // print a sample of the first doc data keys
        try {
          // ignore: avoid_print
          print('ProductsPage: sample doc data keys: ${docs.first.data() is Map ? (docs.first.data() as Map).keys.toList() : docs.first.data()}');
        } catch (_) {}
      }
      final page = docs.map((d) => _docToMap(d)).toList();
      _loadedProducts.clear();
      _loadedProducts.addAll(page);
      _lastDoc = docs.isNotEmpty ? docs.last : null;
      _hasMore = docs.length >= _pageSize;
    } catch (e, st) {
      // ignore: avoid_print
      print('loadInitial error: $e\n$st');
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (_lastDoc == null) return _loadInitial();
    _loading = true;
    setState(() {});
    try {
      // Debug: log continuation query
      // ignore: avoid_print
      print('ProductsPage: _loadMore() — starting after ${_lastDoc?.id}, category=$_category');
      Query q = FirebaseFirestore.instance.collection('products').orderBy('title');
      if (_category != 'All') q = q.where('category', isEqualTo: _category);
      final snap = await q.startAfterDocument(_lastDoc!).limit(_pageSize).get();
      final docs = snap.docs;
      // ignore: avoid_print
      print('ProductsPage: _loadMore() — got ${docs.length} docs');
      final page = docs.map((d) => _docToMap(d)).toList();
      _loadedProducts.addAll(page);
      _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
      _hasMore = docs.length >= _pageSize;
    } catch (e, st) {
      // ignore: avoid_print
      print('loadMore error: $e\n$st');
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  Map<String, dynamic> _docToMap(DocumentSnapshot d) {
    final raw = d.data();
    if (raw is Map<String, dynamic>) {
      final priceStr = (raw['price'] ?? raw['cost'] ?? '').toString();

      int qty = 0;
      try {
        final qcand = raw['quantity'] ?? raw['qty'] ?? raw['stock'] ?? raw['available'] ?? raw['availableQuantity'] ?? raw['amount'];
        if (qcand is int) qty = qcand;
        else if (qcand is String) qty = int.tryParse(qcand) ?? 0;
        else if (qcand is double) qty = qcand.toInt();
        else if (qcand == true) qty = 1;
      } catch (_) {
        qty = 0;
      }
      if (qty <= 0) {
        final inStockFlag = raw['inStock'] ?? raw['isAvailable'] ?? raw['available'] ?? raw['in_stock'];
        if (inStockFlag == true) qty = 1;
      }

      final image = (raw['image'] ?? raw['imageUrl'] ?? (raw['images'] is List ? (raw['images'] as List).firstWhere((_) => true, orElse: () => '') : '') ?? '').toString();

      final onSale = (raw['onSale'] ?? raw['sale'] ?? raw['isOnSale'] ?? false) == true;

      return {
        'id': d.id,
        'title': (raw['title'] ?? raw['name'] ?? '').toString(),
        'price': priceStr,
        'priceNum': _parsePrice(priceStr),
        'category': (raw['category'] ?? '').toString(),
        'quantity': qty.toString(),
        'image': image,
        'onSale': onSale,
      };
    }
    return {'id': d.id, 'title': '', 'price': '', 'priceNum': 0, 'category': '', 'quantity': '0', 'image': '', 'onSale': false};
  }

  List<Map<String, dynamic>> _applyClientFilters() {
    final search = _searchCtrl.text.trim().toLowerCase();
    final list = _loadedProducts.where((p) {
      final title = (p['title'] ?? '').toString().toLowerCase();
      if (search.isNotEmpty && !title.contains(search)) return false;
      if (_inStockOnly) {
        final qty = int.tryParse((p['quantity'] ?? '0').toString()) ?? 0;
        if (qty <= 0) return false;
      }
      if (_onSaleOnly && (p['onSale'] ?? false) != true) return false;
      return true;
    }).toList();

    if (_priceSort == 'low') {
      list.sort((a, b) => (a['priceNum'] ?? 0).compareTo(b['priceNum'] ?? 0));
    } else if (_priceSort == 'high') {
      list.sort((a, b) => (b['priceNum'] ?? 0).compareTo(a['priceNum'] ?? 0));
    }
    return list;
  }

  void _applyFilters() {
    _lastDoc = null;
    _hasMore = true;
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyClientFilters();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          Builder(builder: (ctx) {
            return IconButton(
              icon: const Icon(Icons.shopping_cart),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartPage()));
              },
            );
          })
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products...'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              DropdownButton<String>(
                value: _category,
                items: const ["All", "Skin", "Hair", "Nails"].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v ?? 'All'),
              ),
              const SizedBox(width: 12),
              FilterChip(label: const Text('In stock'), selected: _inStockOnly, onSelected: (v) => setState(() => _inStockOnly = v)),
              const SizedBox(width: 8),
              FilterChip(label: const Text('On sale'), selected: _onSaleOnly, onSelected: (v) => setState(() => _onSaleOnly = v)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _priceSort,
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Default')),
                  DropdownMenuItem(value: 'low', child: Text('Price: Low → High')),
                  DropdownMenuItem(value: 'high', child: Text('Price: High → Low')),
                ],
                onChanged: (v) => setState(() => _priceSort = v ?? 'default'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _applyFilters, child: const Text('Apply')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _inStockOnly = false;
                  _onSaleOnly = false;
                  _priceSort = 'default';
                  _category = 'All';
                  _applyFilters();
                },
                child: const Text('Reset'),
              )
            ]),
          ),
          Expanded(
            child: _loading && _loadedProducts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final cross = width >= 900 ? 4 : width >= 600 ? 3 : 2;
                    if (filtered.isEmpty) return const Center(child: Text('No products found'));
                    return GridView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cross, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7),
                      itemCount: filtered.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= filtered.length) {
                          return _loading
                              ? const Center(child: CircularProgressIndicator())
                              : Center(child: ElevatedButton(onPressed: _loadMore, child: const Text('Load more')));
                        }
                        final p = filtered[i];
                        final title = p['title']?.toString() ?? '';
                        final price = p['price']?.toString() ?? '';
                        final image = p['image']?.toString() ?? '';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: Center(child: image.isEmpty ? const Icon(Icons.image) : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))),
                              const SizedBox(height: 8),
                              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(PhpCurrency.formatFromString(price), style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(children: [
                                OutlinedButton(onPressed: () => _addToCartSafe(p), child: const Icon(Icons.shopping_cart_outlined)),
                                const Spacer(),
                                ElevatedButton(onPressed: () => _buyNowSafe(p), child: const Text('Buy Now'))
                              ])
                            ]),
                          ),
                        );
                      },
                    );
                  }),
          )
        ],
      ),
    );
  }

  void _addToCartSafe(Map<String, dynamic> p) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in')));
      return;
    }
    final pid = p['id']?.toString() ?? '';
    final cartRef = FirebaseFirestore.instance.collection('cart').doc('${user.uid}_$pid');
    cartRef.set({
      'userUid': user.uid,
      'productId': pid,
      'title': p['title']?.toString() ?? '',
      'price': p['price']?.toString() ?? '',
      'image': p['image']?.toString() ?? '',
      'quantity': FieldValue.increment(1),
      'addedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).then((_) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartPage()));
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add to cart: $e')));
    });
  }

  void _buyNowSafe(Map<String, dynamic> p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductsCheckoutPage(items: [p])));
  }
}
