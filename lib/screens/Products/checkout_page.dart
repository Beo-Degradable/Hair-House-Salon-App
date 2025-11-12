import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hxhmobile/utils/currency.dart';

class ProductsCheckoutPage extends StatefulWidget {
  final List<Map<String, String>> items; // expects id, title, price, image?
  const ProductsCheckoutPage({super.key, required this.items});

  @override
  State<ProductsCheckoutPage> createState() => _ProductsCheckoutPageState();
}

class _ProductsCheckoutPageState extends State<ProductsCheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtr;
  late final TextEditingController _emailCtr;
  final TextEditingController _addressCtr = TextEditingController();
  final TextEditingController _phoneCtr = TextEditingController();

  // quantity per item id
  final Map<String, int> _qty = {};

  @override
  void initState() {
    super.initState();
    _initProfile();
    for (final it in widget.items) {
      _qty[it['id']!] = 1;
    }
  }

  Future<void> _initProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final display = prefs.getString('display_name');
    final email = prefs.getString('email');
    _nameCtr = TextEditingController(text: display ?? '');
    _emailCtr = TextEditingController(text: email ?? '');
    if (mounted) setState(() {});
  }

  int _parsePrice(String? s) {
    if (s == null) return 0;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  int get _totalPrice {
    int total = 0;
    for (final it in widget.items) {
      final id = it['id']!;
      final price = _parsePrice(it['price']);
      final q = _qty[id] ?? 1;
      total += price * q;
    }
    return total;
  }

  void _changeQty(String id, int delta) {
    setState(() {
      final current = _qty[id] ?? 1;
      final next = current + delta;
      _qty[id] = next < 1 ? 1 : next;
    });
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final name = _nameCtr.text.trim();
    final email = _emailCtr.text.trim();
    final address = _addressCtr.text.trim();
    final phone = _phoneCtr.text.trim();

    final items = widget.items.map((e) {
      final id = e['id']!;
      final qty = _qty[id] ?? 1;
      final unitPrice = e['price'] ?? '';
      final unit = _parsePrice(unitPrice);
      return {
        'id': id,
        'title': e['title'] ?? 'Product',
        'unitPrice': unitPrice,
        'quantity': qty,
        'subtotal': unit * qty,
      };
    }).toList();

    final total = _totalPrice;

    await FirebaseFirestore.instance.collection('payments').add({
      if (user != null) 'userUid': user.uid,
      'name': name,
      'email': email,
      'address': address,
      'phone': phone,
      'items': items,
      'total': total,
      'currency': 'PHP',
      'status': 'pending', // pickup & pay in store
      'mode': 'pickup',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Add notification to Firestore
    if (user != null) {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userUid': user.uid,
        'type': 'purchase',
        'title': 'Thank you for your purchase!',
        'body': 'Your product order has been received.',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Order placed for pickup')));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _emailCtr.dispose();
    _addressCtr.dispose();
    _phoneCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Details container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtr,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailCtr,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Email required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _addressCtr,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Address required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneCtr,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Phone required'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Items container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Items', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...widget.items.map((p) {
                    final id = p['id']!;
                    final title = p['title'] ?? 'Product';
                    final price = p['price'] ?? '';
                    final q = _qty[id] ?? 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          // title & price
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  PhpCurrency.formatFromString(price),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // quantity controls: - [box] +
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _changeQty(id, -1),
                          ),
                          Container(
                            width: 44,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outlineVariant),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$q'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _changeQty(id, 1),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const Text(
                    'Note: Payment is done in-store. This order reserves items for pickup.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80), // leave space for bottom bar
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
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
                        'Items (${widget.items.length})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        PhpCurrency.formatInt(_totalPrice),
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
                  onPressed: _submitOrder,
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
