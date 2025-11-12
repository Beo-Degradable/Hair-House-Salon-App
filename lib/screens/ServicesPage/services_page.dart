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
  bool _activeHighlight = false;
  String _category = 'All';
  String? _pendingHighlightedId;
  final Set<String> _selectedIds = <String>{};
  final Map<String, Map<String, String>> _selectedMap = {};
  bool _multiSelect = false;

  double get _selectedTotal {
    double sum = 0;
    for (final m in _selectedMap.values) {
      final raw = (m['price'] ?? '').toString();
      // Extract numeric like 199, 199.99 from strings with currency symbols
      final match = RegExp(r"[-+]?[0-9]*\.?[0-9]+").firstMatch(raw);
      if (match != null) {
        sum += double.tryParse(match.group(0)!) ?? 0;
      }
    }
    return sum;
  }

  void _toggleSelect(Map<String, dynamic> svc) {
    final id = (svc['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedMap.remove(id);
        if (_selectedIds.isEmpty && _multiSelect) {
          _multiSelect = false; // auto-exit if nothing selected
        }
      } else {
        _selectedIds.add(id);
        _selectedMap[id] = {
          'id': id,
          'title': (svc['title'] ?? '').toString(),
          'price': (svc['price'] ?? '').toString(),
          'duration': (svc['duration'] ?? '').toString(),
        };
      }
    });
  }

  void _enterMultiSelect(Map<String, dynamic> svc) {
    if (!_multiSelect) {
      setState(() {
        _multiSelect = true;
      });
    }
    _toggleSelect(svc);
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectedMap.clear();
      _multiSelect = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _highlightScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).chain(CurveTween(curve: Curves.elasticOut)).animate(_highlightController);
    if (widget.highlightedPromoId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final pid = prefs.getString('highlighted_promo_id');
        if (pid != null) {
          await prefs.remove('highlighted_promo_id');
          if (mounted) setState(() => _pendingHighlightedId = pid);
          if (mounted) setState(() => _activeHighlight = true);
          _highlightController.forward();
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _activeHighlight = false);
              _highlightController.reverse();
            }
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _activeHighlight = true);
        _highlightController.forward();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _activeHighlight = false);
            _highlightController.reverse();
          }
        });
      });
    }
    _highlightController.dispose();
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
        actions: _multiSelect
            ? [
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
              ]
            : null,
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
                    final isSelected = _selectedIds.contains(id);
                    return InkWell(
                      onTap: () {
                        if (_multiSelect) {
                          _toggleSelect(svc);
                        } else {
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
                        }
                      },
                      onLongPress: () => _enterMultiSelect(svc),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedBuilder(
                        animation: _highlightController,
                        builder: (context, child) {
                          final scale = (promoted && _activeHighlight)
                              ? _highlightScale.value
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: Stack(
                              children: [
                                Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: (promoted && _activeHighlight)
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
                                      ? cs.primary.withValues(alpha: 0.08)
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? cs.primary
                                          : cs.surface,
                                      border: Border.all(
                                        color: isSelected
                                            ? cs.primary
                                            : cs.outlineVariant,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check
                                          : Icons.radio_button_unchecked,
                                      size: 18,
                                      color: isSelected
                                          ? cs.onPrimary
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
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
      bottomNavigationBar: (!_multiSelect || _selectedIds.isEmpty)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selectedIds.length} selected',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            PhpCurrency.format(_selectedTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final initial = _selectedMap.values
                            .map(
                              (e) => {
                                'id': e['id'] ?? '',
                                'title': e['title'] ?? '',
                                'price': e['price'] ?? '',
                                'duration': e['duration'] ?? '',
                              },
                            )
                            .toList();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                BookingPage(initialServices: initial),
                          ),
                        );
                        _clearSelection();
                      },
                      icon: const Icon(Icons.shopping_bag),
                      label: const Text('Book'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
