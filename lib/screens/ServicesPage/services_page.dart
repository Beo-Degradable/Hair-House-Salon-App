import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hxhmobile/screens/AppointmentPage/booking_page.dart';
import 'package:hxhmobile/utils/currency.dart';

class ServicesPage extends StatefulWidget {
  final String? highlightedPromoId;
  const ServicesPage({Key? key, this.highlightedPromoId}) : super(key: key);

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage>
    with TickerProviderStateMixin {
  // Animation for highlight
  late AnimationController _highlightController;
  late Animation<double> _highlightScale;
  String? _activeHighlight;
  late final ScrollController _scrollController;
  String _category = 'All';
  String? _pendingHighlightedId;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900), // Smooth and quick
    );
    _highlightScale = Tween<double>(
      begin: 1.0,
      end: 1.07,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_highlightController);
    _loadHighlight();
  }

  Future<void> _loadHighlight() async {
    final prefs = await SharedPreferences.getInstance();
    final highlight = prefs.getString('highlighted_promo_id');
    if (highlight != null && highlight.isNotEmpty) {
      setState(() {
        _activeHighlight = highlight;
      });
      _highlightController.forward();
      Future.delayed(const Duration(seconds: 2), () async {
        if (mounted) {
          setState(() {
            _activeHighlight = null;
          });
          _highlightController.reverse();
          await prefs.remove('highlighted_promo_id');
        }
      });
    }
  }

  // Live services stream from Firestore `services` collection.
  // Expected document fields: title, duration, price, image(optional), category(optional)
  // We map doc.id to 'id' to preserve existing logic (promo highlighting assumes ids like s1..s9).
  Stream<List<Map<String, dynamic>>> _servicesStream() {
    return FirebaseFirestore.instance
        .collection('services')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              // prefer `title` but many docs use `name`
              'title': (data['title'] ?? data['name'] ?? 'Untitled').toString(),
              // duration may be stored as a string or minutes int
              'duration': (data['duration'] ?? data['durationMinutes'] ?? '')
                  .toString(),
              // ensure price is a string to avoid cast errors when the field is numeric
              'price': data['price'] != null ? data['price'].toString() : '',
              'image': data['image']?.toString() ?? '',
              // some docs use `type` instead of `category`
              'category': (data['category'] ?? data['type'] ?? '').toString(),
            };
          }).toList(),
        );
  }

  // Sample promo -> service ids map
  Map<String, List<String>> get _promoMap => {
    'p1': ['s1', 's2'],
    'p2': ['s3', 's4'],
    'p3': ['s7', 's8', 's9'],
  };

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.highlightedPromoId ?? _pendingHighlightedId;
    final promotedIds = highlighted != null
        ? (_promoMap[highlighted] ?? [])
        : <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Category filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) {
                  const cats = ['All', 'Hair', 'Skin', 'Nails'];
                  final c = cats[i];
                  final sel = _category == c;
                  return ChoiceChip(
                    label: Text(c),
                    selected: sel,
                    onSelected: (_) => setState(() => _category = c),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: const ['All', 'Hair', 'Skin', 'Nails'].length,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _servicesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading services: ${snapshot.error}'),
                  );
                }
                final services = snapshot.data ?? [];
                if (services.isEmpty) {
                  return const Center(child: Text('No services available'));
                }

                final width = MediaQuery.of(context).size.width;
                final crossAxisCount = width >= 900
                    ? 4
                    : width >= 600
                    ? 3
                    : 2;
                final cs = Theme.of(context).colorScheme;

                final filtered = services.where((s) {
                  if (_category == 'All') return true;
                  final title = (s['title'] ?? '').toString().toLowerCase();
                  if (_category == 'Hair') {
                    return title.contains('hair') ||
                        title.contains('shampoo') ||
                        title.contains('color') ||
                        title.contains('highlight');
                  }
                  if (_category == 'Skin') {
                    return title.contains('facial') || title.contains('makeup');
                  }
                  if (_category == 'Nails') {
                    return title.contains('nail');
                  }
                  return true;
                }).toList();

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final svc = filtered[i];
                    final id = svc['id'] as String;
                    final title = svc['title'] as String;
                    final duration = (svc['duration'] ?? '') as String;
                    final price = (svc['price'] ?? '') as String;
                    final promoted = promotedIds.contains(id);
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookingPage(
                              serviceId: id,
                              serviceTitle: title,
                              servicePrice: price,
                              serviceDuration: duration,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedBuilder(
                        animation: _highlightController,
                        builder: (context, child) {
                          final isHighlighted = _activeHighlight == svc['id'];
                          final scale = isHighlighted
                              ? _highlightScale.value
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              decoration: BoxDecoration(
                                border: isHighlighted
                                    ? Border.all(
                                        color: Color(0xFFB8860B),
                                        width: 3,
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: (promoted && (_activeHighlight == id))
                                      ? BorderSide(
                                          color: Colors.amber,
                                          width: 3,
                                        )
                                      : BorderSide(
                                          color: Colors.transparent,
                                          width: 0,
                                        ),
                                ),
                                elevation: 3,
                                color: promoted
                                    ? cs.primary.withAlpha(20)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          height: 80,
                                          width: double.infinity,
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.2),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.image,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              duration,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        PhpCurrency.formatFromString(price),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
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
          ),
        ],
      ),
      // No bottomNavigationBar (multi-select removed)
    );
  }
}
