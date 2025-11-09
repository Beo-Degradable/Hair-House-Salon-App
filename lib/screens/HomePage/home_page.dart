import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/bubble_background.dart';
import '../StylistPage/stylist_details_page.dart';
import '../AiStyles/ai_styles_page.dart';
import '../Products/cart_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String _userName = 'Guest';
  String? _selectedBranch;
  String _featuredCategory = 'All';
  late final AnimationController _fabCtrl;

  // Search state
  final TextEditingController _searchCtr = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<String> _allSuggestions = [];
  List<String> _searchResults = [];
  bool _searchActive = false;
  OverlayEntry? _suggestionsOverlay;

  // Promo carousel (Firestore-backed Promotions collection)
  final PageController _promoController = PageController(viewportFraction: 0.9);
  int _promoIndex = 0;
  int _promoCount = 0; // synced with live promotions count
  Timer? _promoTimer;

  // Deprecated local services list replaced by Firestore stream (see _servicesStream)
  List<Map<String, String>> _localServicesCache = [];

  // Firestore stylists cached for quick length checks
  List<Map<String, String>> _stylists = const [];

  List<Map<String, String>> _promotedServices() {
    // Firestore-backed: use cached services as a lightweight source for flash offers
    // You can later link promos to specific service IDs by storing those IDs in _promoMap
    if (_localServicesCache.isEmpty) return const [];
    return _localServicesCache.take(6).toList();
  }

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
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Selected: $t')),
                            );
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
    // preload services titles for search suggestions
    FirebaseFirestore.instance
        .collection('services')
        .where('active', isEqualTo: true)
        .limit(50)
        .get()
        .then((snap) {
          _localServicesCache = snap.docs.map((d) {
            final data = d.data();
            return {
              'id': d.id,
              'title': (data['title'] ?? 'Service').toString(),
              'price': (data['price'] ?? '').toString(),
              'desc': (data['description'] ?? data['desc'] ?? '').toString(),
              'branch': (data['branch'] ?? '').toString(),
              'category': (data['category'] ?? '').toString(),
            };
          }).toList();
          if (mounted) {
            setState(() {
              _allSuggestions = _localServicesCache
                  .map((e) => e['title']!)
                  .toList();
            });
          }
        });

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
    // Branch filter state (All by default)
    final branches = const ['All', 'Vergara', 'Lawas', 'Lipa', 'Tanauan'];
    _selectedBranch ??= 'All';

    List<Map<String, String>> filterByBranch(List<Map<String, String>> list) {
      if (_selectedBranch == null || _selectedBranch == 'All') return list;
      return list.where((s) => (s['branch'] ?? '') == _selectedBranch).toList();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> _servicesStream() {
      // Featured services: active, optionally filter by category later
      return FirebaseFirestore.instance
          .collection('services')
          .where('active', isEqualTo: true)
          .orderBy('sortOrder', descending: false)
          .limit(30)
          .snapshots();
    }

    final authUser = FirebaseAuth.instance.currentUser;
    Stream<QuerySnapshot<Map<String, dynamic>>> _upcomingApptStream() {
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
                                      if (mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No new notifications',
                                            ),
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
                                      if (mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Open settings'),
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
                                        decoration: const InputDecoration(
                                          hintText: 'Search services...',
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

                  // Promo carousel (live Promotions collection)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('Promotions')
                        .where('active', isEqualTo: true)
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
                      if (docs.isEmpty) return const SizedBox();
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
                            final subtitle = (data['subtitle'] ?? '')
                                .toString();
                            final deepLinkServiceId =
                                (data['deepLinkServiceId'] ?? '').toString();
                            return GestureDetector(
                              onTap: () {
                                final target = deepLinkServiceId.isNotEmpty
                                    ? deepLinkServiceId
                                    : docId;
                                _switchToServices(highlightedPromoId: target);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
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
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            subtitle,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
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
                    },
                  ),
                  const SizedBox(height: 18),

                  // Flash Offers
                  if (_promotedServices().isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Flash Offers',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        // Branch filter chips
                        SizedBox(
                          height: 38,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            scrollDirection: Axis.horizontal,
                            itemCount: branches.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final b = branches[i];
                              final selected = _selectedBranch == b;
                              return ChoiceChip(
                                label: Text(
                                  b == 'All'
                                      ? 'All Branches'
                                      : b.replaceAll(' Branch', ''),
                                ),
                                selected: selected,
                                onSelected: (_) =>
                                    setState(() => _selectedBranch = b),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Branch-specific flash offers; guarantee content per-branch with a graceful fallback
                        (() {
                          var branchFlash = filterByBranch(_promotedServices());
                          // Fallback: if a specific branch has no promos defined, surface top services from that branch as temporary flash
                          if ((_selectedBranch != null &&
                                  _selectedBranch != 'All') &&
                              branchFlash.isEmpty) {
                            branchFlash = _localServicesCache
                                .where((s) => s['branch'] == _selectedBranch)
                                .take(3)
                                .toList();
                          }
                          return SizedBox(
                            height: 120,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: branchFlash.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final svc = branchFlash[i];
                                final title =
                                    svc['title']!; // removed unused id
                                return GestureDetector(
                                  onTap: () async {
                                    // switch to Services tab (keeps navbar visible)
                                    await _switchToServices();
                                  },
                                  child: SizedBox(
                                    width: 220,
                                    child: Card(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
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
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'FLASH',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Text('20% OFF'),
                                              ],
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
                        })(),
                        const SizedBox(height: 18),
                      ],
                    ),

                  // Upcoming Appointment Alert (single card)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _upcomingApptStream(),
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
                        Text(
                          'Featured Services',
                          style: Theme.of(context).textTheme.titleMedium,
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
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _servicesStream(),
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
                              return const Text('Failed to load services');
                            }
                            final docs = snapshot.data?.docs ?? [];
                            final mapped = docs.map((d) {
                              final data = d.data();
                              return {
                                'id': d.id,
                                'title': (data['title'] ?? 'Service')
                                    .toString(),
                                'price': (data['price'] ?? '').toString(),
                                'desc':
                                    (data['description'] ?? data['desc'] ?? '')
                                        .toString(),
                                'branch': (data['branch'] ?? '').toString(),
                                'category': (data['category'] ?? '').toString(),
                              };
                            }).toList();
                            final filtered = filterByBranch(mapped)
                                .where(
                                  (s) =>
                                      _featuredCategory == 'All' ||
                                      (s['category'] ?? '') ==
                                          _featuredCategory,
                                )
                                .take(10)
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
                                  final desc = svc['desc'] ?? '';
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
                                              const SizedBox(height: 6),
                                              Text(
                                                desc,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              const Spacer(),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    price,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                  ),
                                                ],
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
                          height: 120,
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
                                              stylist: stylist,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Column(
                                        children: [
                                          Hero(
                                            tag: 'stylist_${stylist['id']}',
                                            child: const CircleAvatar(
                                              radius: 40,
                                              child: Icon(
                                                Icons.person,
                                                size: 40,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: 90,
                                            child: Text(
                                              stylist['name']!,
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                            ),
                                          ),
                                        ],
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

            // Suggestions overlay
            if (_searchActive && _searchCtr.text.trim().isNotEmpty)
              Positioned(
                top:
                    MediaQuery.of(context).padding.top +
                    MediaQuery.of(context).size.height * 0.28 -
                    20,
                left: 16,
                right: 16,
                child: _buildSuggestionsCard(),
              ),
          ],
        ),
      ),
    );
  }
}
