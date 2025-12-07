import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Products/products_page.dart';
import '../ServicesPage/services_page.dart';
import '../../widgets/bubble_background.dart';
import '../StylistPage/stylist_details_page.dart';
import '../AiStyles/ai_styles_page.dart';
import '../Products/cart_page.dart';
import '../Settings/settings_page.dart';
import '../Notifications/notifications_page.dart';
import '../AppointmentPage/booking_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String _userName = 'Guest';
  String _featuredCategory = 'All';
  late final AnimationController _fabCtrl;

  // Search state
  final TextEditingController _searchCtr = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<String> _allSuggestions = [];
  List<String> _searchResults = [];
  bool _searchActive = false;
  OverlayEntry? _suggestionsOverlay;
  // Removed unused fields (_bouncingId, _bounceCtrl, _servicesKey)

  // Caches
  List<Map<String, String>> _localServicesCache = [];
  List<Map<String, String>> _localProductsCache = [];

  // Promo carousel (Firestore-backed Promotions collection)
  final PageController _promoController = PageController(viewportFraction: 0.9);
  int _promoIndex = 0;
  // (moved _promoCount definition near top of class to group state vars)

  // Helper: format price with Philippine peso sign and simple comma grouping
  String _formatPeso(String raw) {
    if (raw.isEmpty) return '₱—';
    // Strip any non-numeric, keep digits, optional minus, and dot
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final val = double.tryParse(cleaned);
    if (val == null) return '₱—';
    final bool isInt = val % 1 == 0;
    String numberStr = isInt ? val.toInt().toString() : val.toStringAsFixed(2);
    // Insert commas for thousands
    String withCommas(String s) {
      String integerPart = s;
      String decimalPart = '';
      final dotIndex = s.indexOf('.');
      if (dotIndex != -1) {
        integerPart = s.substring(0, dotIndex);
        decimalPart = s.substring(dotIndex); // keep dot
      }
      final chars = integerPart.split('').reversed.toList();
      final buf = StringBuffer();
      for (int i = 0; i < chars.length; i++) {
        if (i != 0 && i % 3 == 0) buf.write(',');
        buf.write(chars[i]);
      }
      final grouped = buf.toString().split('').reversed.join();
      return '$grouped$decimalPart';
    }

    return '₱${withCommas(numberStr)}';
  }

  // Primary featured services stream: active + order by sortOrder (requires composite index if combining where/orderBy)
  Stream<QuerySnapshot<Map<String, dynamic>>> _servicesStreamPrimary() {
    return FirebaseFirestore.instance
        .collection('services')
        .orderBy('sortOrder', descending: false)
        .snapshots();
  }

  // Fallback: remove orderBy to avoid missing index errors while still filtering by active
  Stream<QuerySnapshot<Map<String, dynamic>>> _servicesStreamFallback() {
    return FirebaseFirestore.instance.collection('services').snapshots();
  }

  // Alternate flag fallback: some datasets may use `isActive` instead of `active`
  Stream<QuerySnapshot<Map<String, dynamic>>> _servicesStreamFallbackAlt() {
    return FirebaseFirestore.instance.collection('services').snapshots();
  }

  Widget _buildPromosPager(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return SizedBox(
      height: 160,
      child: PageView.builder(
        controller: _promoController,
        itemCount: docs.length,
        onPageChanged: (i) => setState(() => _promoIndex = i),
        itemBuilder: (ctx, i) {
          final data = docs[i].data();
          final docId = docs[i].id;
          final title = (data['title'] ?? '').toString();
          final subtitle = (data['subtitle'] ?? '').toString();
          final deepLinkServiceId = (data['deepLinkServiceId'] ?? '')
              .toString();
          return GestureDetector(
            onTap: () {
              final target = deepLinkServiceId.isNotEmpty
                  ? deepLinkServiceId
                  : docId;
              _switchToServices(highlightedPromoId: target);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _servicesFallbackList(
    List<Map<String, String>> Function(List<Map<String, String>>)
    filterByBranch,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _servicesStreamFallback(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Try alternative flag
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _servicesStreamFallbackAlt(),
            builder: (context, altSnap) {
              if (altSnap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = altSnap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text('No featured services');
              }
              return _mapServicesDocs(filterByBranch, docs);
            },
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          // Alt flag
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _servicesStreamFallbackAlt(),
            builder: (context, altSnap) {
              final altDocs = altSnap.data?.docs ?? [];
              if (altDocs.isEmpty) return const Text('No featured services');
              return _mapServicesDocs(filterByBranch, altDocs);
            },
          );
        }
        return _mapServicesDocs(filterByBranch, docs);
      },
    );
  }

  Widget _mapServicesDocs(
    List<Map<String, String>> Function(List<Map<String, String>>)
    filterByBranch,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final mapped = docs.map((d) {
      final data = d.data();
      // Prefer 'name', then 'title', then fallback
      final name = (data['name'] ?? '').toString();
      final title = (data['title'] ?? '').toString();
      final displayName = name.isNotEmpty
          ? name
          : (title.isNotEmpty ? title : 'Service');
      return {
        'id': d.id,
        'title': displayName,
        'price': (data['price'] ?? '').toString(),
        // desc intentionally omitted from UI
        'desc': (data['description'] ?? data['desc'] ?? '').toString(),
        'branch': (data['branch'] ?? '').toString(),
        'category': (data['category'] ?? '').toString(),
      };
    }).toList();
    final filtered = filterByBranch(mapped)
        .where(
          (s) =>
              _featuredCategory == 'All' ||
              (s['category'] ?? '') == _featuredCategory,
        )
        .toList();
    if (filtered.isEmpty) return const Text('No featured services');
    return SizedBox(
      height: 160,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final svc = filtered[i];
          final title = svc['title']!;
          final price = svc['price'] ?? '';
          return SizedBox(
            width: 220,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      _formatPeso(price),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingPage(
                                serviceId: svc['id'],
                                serviceTitle: svc['title'],
                                servicePrice: svc['price'],
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Book Now'),
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
  }

  // (Flash Offers section removed per request)

  int _promoCount = 0; // synced with live promotions count
  Timer? _promoTimer;

  // Firestore stylists cached for quick length checks
  List<Map<String, String>> _stylists = const [];
  // Removed legacy _promotedServices() – flash offers now stream from Firestore directly.

  // Removed unused _promoForService and _logout after UI refactor.

  Future<void> _switchToServices({String? highlightedPromoId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_nav_index', 1);
    if (highlightedPromoId != null) {
      await prefs.setString('highlighted_promo_id', highlightedPromoId);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _onSearchChange() {
    try {
      final q = _searchCtr.text.trim().toLowerCase();
      setState(() {
        if (q.isEmpty) {
          _searchResults = [];
          _removeSuggestionsOverlay();
        } else {
          _searchResults = _allSuggestions
              .where((s) => s.toLowerCase().contains(q))
              .toList();
          _showSuggestionsOverlay();
        }
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _removeSuggestionsOverlay();
      });
    }
  }

  void _closeSearch() {
    _searchCtr.clear();
    _searchFocus.unfocus();
    setState(() => _searchActive = false);
    _removeSuggestionsOverlay();
  }

  Widget _buildSuggestionsCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Material(
          color: Colors.transparent,
          child: Card(
            elevation: 14,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              height: 160,
              child: _searchResults.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Text('No results'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final t = _searchResults[i];
                        return ListTile(
                          leading: const Icon(Icons.search),
                          title: Text(t),
                          onTap: () async {
                            final prefs = await SharedPreferences.getInstance();
                            final isProduct = _localProductsCache.any(
                              (p) => p['title'] == t,
                            );
                            final isService = _localServicesCache.any(
                              (s) => s['title'] == t,
                            );
                            if (isProduct) {
                              await prefs.setInt(
                                'last_nav_index',
                                2,
                              ); // Products tab
                              await prefs.setString('highlighted_title', t);
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/home');
                            } else if (isService) {
                              final svc = _localServicesCache.firstWhere(
                                (s) => s['title'] == t,
                                orElse: () => {},
                              );
                              await prefs.setInt(
                                'last_nav_index',
                                1,
                              ); // Services tab
                              await prefs.setString(
                                'highlighted_promo_id',
                                svc['id'] ?? t,
                              );
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/home');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Selected: $t')),
                              );
                            }
                            _closeSearch();
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSuggestionsOverlay() {
    if (_suggestionsOverlay != null) return;
    final overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top:
              MediaQuery.of(context).padding.top +
              MediaQuery.of(context).size.height * 0.28 -
              20,
          left: 0,
          right: 0,
          child: _buildSuggestionsCard(),
        );
      },
    );
    Overlay.of(context).insert(overlay);
    _suggestionsOverlay = overlay;
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _searchResults = [];
    _allSuggestions = [];
    _searchCtr.addListener(_onSearchChange);

    // FAB animation controller (pulsing/color/rotation)
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _promoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_promoCount == 0) return;
      _promoIndex = (_promoIndex + 1) % _promoCount;
      _promoController.animateToPage(
        _promoIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
    _preloadServicesCache();
    _preloadProductsCache();

    // subscribe to stylists
    FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'stylist')
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) {
                final data = d.data();
                return {
                  'id': d.id,
                  'name': (data['name'] ?? '').toString(),
                  'branch': (data['branch'] ?? '').toString(),
                  'exp': (data['experience'] ?? '').toString(),
                  'specialization': (data['specialization'] ?? '').toString(),
                };
              })
              .where((m) => (m['name'] ?? '').isNotEmpty)
              .toList();
          if (mounted) setState(() => _stylists = list);
        });
  }

  Future<void> _preloadServicesCache() async {
    // Try primary query first
    try {
      final snap = await FirebaseFirestore.instance
          .collection('services')
          .where('active', isEqualTo: true)
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        _assignLocalServicesFromSnap(snap);
        return;
      }
      // Fallback 1: different boolean key commonly used
      final snap2 = await FirebaseFirestore.instance
          .collection('services')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .get();
      if (snap2.docs.isNotEmpty) {
        _assignLocalServicesFromSnap(snap2);
        return;
      }
      // Fallback 2: no active filter (last resort)
      final snap3 = await FirebaseFirestore.instance
          .collection('services')
          .limit(50)
          .get();
      _assignLocalServicesFromSnap(snap3);
    } catch (e) {
      // As a last resort, perform the simplest query to avoid index issues
      try {
        final snap = await FirebaseFirestore.instance
            .collection('services')
            .limit(30)
            .get();
        _assignLocalServicesFromSnap(snap);
      } catch (_) {}
    }
  }

  Future<void> _preloadProductsCache() async {
    // Try primary query first
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('active', isEqualTo: true)
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        _assignLocalProductsFromSnap(snap);
        return;
      }
      // Fallback 1: different boolean key commonly used
      final snap2 = await FirebaseFirestore.instance
          .collection('products')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .get();
      if (snap2.docs.isNotEmpty) {
        _assignLocalProductsFromSnap(snap2);
        return;
      }
      // Fallback 2: no active filter (last resort)
      final snap3 = await FirebaseFirestore.instance
          .collection('products')
          .limit(50)
          .get();
      _assignLocalProductsFromSnap(snap3);
    } catch (e) {
      // As a last resort, perform the simplest query to avoid index issues
      try {
        final snap = await FirebaseFirestore.instance
            .collection('products')
            .limit(30)
            .get();
        _assignLocalProductsFromSnap(snap);
      } catch (_) {}
    }
  }

  void _assignLocalServicesFromSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map((d) {
      final data = d.data();
      final name = (data['name'] ?? '').toString();
      final title = (data['title'] ?? '').toString();
      final displayName = name.isNotEmpty
          ? name
          : (title.isNotEmpty ? title : 'Service');
      return {
        'id': d.id,
        'title': displayName,
        'price': (data['price'] ?? '').toString(),
        'desc': (data['description'] ?? data['desc'] ?? '').toString(),
        'branch': (data['branch'] ?? '').toString(),
        'category': (data['category'] ?? '').toString(),
      };
    }).toList();
    _localServicesCache = list;
    _updateAllSuggestions();
  }

  void _assignLocalProductsFromSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map((d) {
      final data = d.data();
      final name = (data['name'] ?? '').toString();
      final title = (data['title'] ?? '').toString();
      final displayName = name.isNotEmpty
          ? name
          : (title.isNotEmpty ? title : 'Product');
      return {
        'id': d.id,
        'title': displayName,
        'price': (data['price'] ?? '').toString(),
        'desc': (data['description'] ?? data['desc'] ?? '').toString(),
        'branch': (data['branch'] ?? '').toString(),
        'category': (data['category'] ?? '').toString(),
      };
    }).toList();
    _localProductsCache = list;
    _updateAllSuggestions();
  }

  void _updateAllSuggestions() {
    final servicesTitles = _localServicesCache.map((e) => e['title']!).toList();
    final productsTitles = _localProductsCache.map((e) => e['title']!).toList();
    _allSuggestions = [...servicesTitles, ...productsTitles];
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchCtr.removeListener(_onSearchChange);
    _searchCtr.dispose();
    _searchFocus.dispose();
    _promoTimer?.cancel();
    _promoController.dispose();
    _removeSuggestionsOverlay();
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getString('first_name');
    final last = prefs.getString('last_name');
    String name;
    if (first != null && first.isNotEmpty) {
      name = (last != null && last.isNotEmpty) ? '$first $last' : first;
    } else {
      final email = prefs.getString('email');
      if (email != null && email.isNotEmpty) {
        name = email.split('@')[0];
      } else {
        name = 'Guest';
      }
    }
    if (mounted) setState(() => _userName = name);
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    // Flash Offers filter removed

    final authUser = FirebaseAuth.instance.currentUser;
    Stream<QuerySnapshot<Map<String, dynamic>>> upcomingApptStream() {
      if (authUser == null) return const Stream.empty();
      return FirebaseFirestore.instance
          .collection('appointments')
          .where('clientUid', isEqualTo: authUser.uid)
          .where('startTime', isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('startTime', descending: false)
          .limit(1)
          .snapshots();
    }

    return Scaffold(
      appBar: null,
      floatingActionButton: AnimatedBuilder(
        animation: _fabCtrl,
        builder: (context, child) {
          final cs = Theme.of(context).colorScheme;
          final t = (math.sin(_fabCtrl.value * 2 * math.pi) + 1) / 2;
          final bg = Color.lerp(cs.primary, cs.tertiary, t) ?? cs.primary;
          final scale = 0.95 + 0.1 * math.sin(_fabCtrl.value * 2 * math.pi);
          final iconScale = 1.0 + 0.08 * math.sin(_fabCtrl.value * 2 * math.pi);
          final iconAngle = 0.25 * math.sin(_fabCtrl.value * 2 * math.pi);

          return Transform.scale(
            scale: scale,
            child: FloatingActionButton.extended(
              heroTag: 'ai_styles_fab',
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AiStylesPage()));
              },
              backgroundColor: bg,
              foregroundColor: Colors.white,
              icon: Transform.rotate(
                angle: iconAngle,
                child: Transform.scale(
                  scale: iconScale,
                  child: const Icon(Icons.camera_alt_outlined),
                ),
              ),
              label: const Text('Try AI'),
            ),
          );
        },
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: BubbleBackground(
                bubbleColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.03),
              ),
            ),
            SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    height: MediaQuery.of(context).size.height * 0.28,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${_timeGreeting()}, $_userName',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Cart should appear right before notification
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const CartPage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.shopping_cart_outlined,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const NotificationsPage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.notifications,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const SettingsPage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.settings,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Find the best services and book your appointment',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 10),
                          // Search
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: Icon(Icons.search),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchCtr,
                                        focusNode: _searchFocus,
                                        onTap: () => setState(
                                          () => _searchActive = true,
                                        ),
                                        inputFormatters: [
                                          // Only allow letters, numbers, and spaces
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[a-zA-Z0-9 ]'),
                                          ),
                                        ],
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Search services and products...',
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    Visibility(
                                      visible:
                                          _searchActive &&
                                          _searchCtr.text.isNotEmpty,
                                      child: IconButton(
                                        onPressed: () => _searchCtr.clear(),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Category chips removed per request
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Promo carousel: 'promos' collection, only type == 'Promo'
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('promos')
                        .where('active', isEqualTo: true)
                        .where('type', isEqualTo: 'Promo')
                        .orderBy('sortOrder')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          final newCount = docs.length;
                          if (newCount != _promoCount) {
                            setState(() {
                              _promoCount = newCount;
                              _promoIndex = _promoCount == 0
                                  ? 0
                                  : _promoIndex % _promoCount;
                            });
                          }
                        }
                      });
                      if (docs.isEmpty) return const SizedBox(height: 0);
                      return _buildPromosPager(context, docs);
                    },
                  ),
                  const SizedBox(height: 18),
                  // Flash Offers (heading only)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Flash Offers',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Flash Offers Firestore section
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('promotions')
                        .where('type', isEqualTo: 'Flash Offers')
                        .where('status', isEqualTo: 'active')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text('No flash offers available'),
                        );
                      }
                      // DEBUG: Show raw Firestore documents
                      return Column(
                        children: [
                          SizedBox(
                            height: 160,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (ctx, i) {
                                final data = docs[i].data();
                                final title = (data['title'] ?? '').toString();
                                final subtitle = (data['subtitle'] ?? '')
                                    .toString();
                                final startDate = data['startDate'];
                                final endDate = data['endDate'];
                                String dateStr = '';
                                if (startDate != null && endDate != null) {
                                  DateTime? start, end;
                                  if (startDate is Timestamp) {
                                    start = startDate.toDate();
                                  }
                                  if (endDate is Timestamp) {
                                    end = endDate.toDate();
                                  }
                                  if (start != null && end != null) {
                                    dateStr =
                                        'From ${start.month}/${start.day}/${start.year} to ${end.month}/${end.day}/${end.year}';
                                  }
                                }
                                final linkedServiceId =
                                    (data['deepLinkServiceId'] ??
                                            data['serviceId'] ??
                                            data['targetServiceId'] ??
                                            '')
                                        .toString();
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    if (linkedServiceId.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'This offer is not linked to a bookable service.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => BookingPage(
                                          serviceId: linkedServiceId,
                                          serviceTitle: title,
                                          servicePrice: (data['price'] ?? '')
                                              .toString(),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: const Color(0xFFB8860B),
                                        width: 3,
                                      ),
                                    ),
                                    elevation: 6,
                                    child: Container(
                                      width: 220,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFB8860B),
                                          width: 3,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(
                                                    0xFFB8860B,
                                                  ),
                                                ),
                                          ),
                                          if (subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              subtitle,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                          const Spacer(),
                                          if (dateStr.isNotEmpty)
                                            Text(
                                              dateStr,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Raw debug output
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // Upcoming Appointment Alert (single card)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: upcomingApptStream(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox();
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) return const SizedBox();
                      final data = docs.first.data();
                      final serviceName = (data['serviceName'] ?? 'Service')
                          .toString();
                      final start = data['startTime'];
                      DateTime? startDt;
                      if (start is Timestamp) startDt = start.toDate();
                      final stylist = (data['stylistName'] ?? '').toString();
                      final branch = (data['branch'] ?? '').toString();
                      final dateStr = startDt != null
                          ? '${startDt.month}/${startDt.day} ${TimeOfDay.fromDateTime(startDt).format(context)}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Card(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Row(
                              children: [
                                const Icon(Icons.event_available, size: 40),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Upcoming Appointment',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(serviceName),
                                      if (stylist.isNotEmpty)
                                        Text('With $stylist'),
                                      if (branch.isNotEmpty ||
                                          dateStr.isNotEmpty)
                                        Text(
                                          '$branch${branch.isNotEmpty && dateStr.isNotEmpty ? ' • ' : ''}$dateStr',
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed('/appointments');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Featured Services (Firestore)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Featured Services',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            TextButton(
                              onPressed: () async {
                                await _switchToServices();
                              },
                              child: const Text('See More'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Featured category filter chips (independent of branch)
                        SizedBox(
                          height: 38,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: const [
                              'All',
                              'Hair',
                              'Skin',
                              'Nails',
                            ].length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              const cats = ['All', 'Hair', 'Skin', 'Nails'];
                              final c = cats[i];
                              final selected = _featuredCategory == c;
                              return ChoiceChip(
                                label: Text(c),
                                selected: selected,
                                onSelected: (_) =>
                                    setState(() => _featuredCategory = c),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Featured services with resilient fallbacks
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _servicesStreamPrimary(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 160,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              // Fallback without orderBy (likely missing index)
                              // Do not branch-filter featured services
                              return _servicesFallbackList((l) => l);
                            }
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              // Try a simpler stream if primary returns nothing
                              return _servicesFallbackList((l) => l);
                            }
                            final mapped = docs.map((d) {
                              final data = d.data();
                              return {
                                'id': d.id,
                                'title': (data['title'] ?? 'Service')
                                    .toString(),
                                'price': (data['price'] ?? '').toString(),
                                // desc intentionally omitted from UI
                                'desc':
                                    (data['description'] ?? data['desc'] ?? '')
                                        .toString(),
                                'branch': (data['branch'] ?? '').toString(),
                                'category': (data['category'] ?? '').toString(),
                              };
                            }).toList();
                            final filtered = mapped
                                .where(
                                  (s) =>
                                      _featuredCategory == 'All' ||
                                      (s['category'] ?? '') ==
                                          _featuredCategory,
                                )
                                .toList();
                            if (filtered.isEmpty) {
                              return const Text('No featured services');
                            }
                            return SizedBox(
                              height: 160,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                scrollDirection: Axis.horizontal,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (ctx, i) {
                                  final svc = filtered[i];
                                  final title = svc['title']!;
                                  final price = svc['price'] ?? '';
                                  return GestureDetector(
                                    onTap: () async {
                                      await _switchToServices();
                                    },
                                    child: SizedBox(
                                      width: 220,
                                      child: Card(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 4,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                title,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleMedium,
                                              ),
                                              const Spacer(),
                                              Text(
                                                _formatPeso(price),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
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
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),

                  // Meet Our Stylists (Firestore-backed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Meet Our Stylists',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: _stylists.isEmpty
                              ? const Center(child: Text('No stylists'))
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _stylists.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 16),
                                  itemBuilder: (ctx, i) {
                                    final stylist = _stylists[i];
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => StylistDetailsPage(
                                              userId: stylist['id'],
                                              stylist: stylist,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: 120,
                                        height: 160,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          border: Border.all(
                                            color: const Color(0xFFB8860B),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            Hero(
                                              tag: 'stylist_${stylist['id']}',
                                              child: CircleAvatar(
                                                radius: 40,
                                                child: Icon(
                                                  Icons.person,
                                                  size: 40,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              stylist['name']!,
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
