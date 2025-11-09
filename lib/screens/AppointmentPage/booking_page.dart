import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'time_slots_overlay.dart';
import 'package:hxhmobile/screens/Profile/widgets/my_booking_page.dart';

class BookingPage extends StatefulWidget {
  final String serviceId;
  final String serviceTitle;
  final String? servicePrice;
  final String? serviceDuration; // e.g. '1 hr 30 min' or '30 min'

  const BookingPage({
    Key? key,
    required this.serviceId,
    required this.serviceTitle,
    this.servicePrice,
    this.serviceDuration,
  }) : super(key: key);

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  // Static branches kept for layout consistency; stylists filtered by this value from Firestore
  final List<String> _branches = const [
    'Central Branch',
    'East Branch',
    'West Branch',
  ];

  String _selectedBranch = 'Central Branch';
  String? _selectedStylist;
  bool _allowOtherBranchStylist = false;
  DateTime _selectedDate = DateTime.now();
  // stylist search + controller for avatar scroller
  final TextEditingController _stylistSearchCtr = TextEditingController();
  String _stylistQuery = '';
  // live stylists pulled from users collection
  List<Map<String, String>> _stylists = const [];

  // booked services starts with the selected service from Home
  List<Map<String, String>> _bookedServices = [];

  // sample suggested services (could be populated from a service API)
  final List<Map<String, String>> _suggested = const [
    {'id': 's2', 'title': 'Shampoo & Blow-dry', 'price': '₱1,200'},
    {'id': 's5', 'title': 'Beard Trim', 'price': '₱800'},
    {'id': 's7', 'title': 'Nail Care', 'price': '₱2,000'},
  ];

  @override
  void initState() {
    super.initState();
    _bookedServices.add({
      'id': widget.serviceId,
      'title': widget.serviceTitle,
      'price': widget.servicePrice ?? '',
      'duration': widget.serviceDuration ?? '',
    });
    // start listening to stylists
    _subscribeStylists();
    // stylist search listener
    _stylistSearchCtr.addListener(_onStylistSearchChanged);
  }

  void _subscribeStylists() {
    FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'stylist')
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) {
                final data = d.data();
                return {
                  'name': (data['name'] ?? '').toString(),
                  'branch': (data['branch'] ?? '').toString(),
                };
              })
              .where((m) => (m['name'] ?? '').isNotEmpty)
              .toList();
          if (!mounted) return;
          setState(() {
            _stylists = list;
            // if no selected stylist yet, pick first from current branch if available
            final options = _stylistsForSelection;
            if (_selectedStylist == null && options.isNotEmpty) {
              _selectedStylist = options.first;
            }
          });
        });
  }

  void _onStylistSearchChanged() {
    setState(() => _stylistQuery = _stylistSearchCtr.text.trim().toLowerCase());
  }

  List<String> get _stylistsForSelection {
    // build from Firestore stylists list, filter by branch unless allowed from other branches
    final base = _allowOtherBranchStylist
        ? _stylists
        : _stylists.where((m) => (m['branch'] ?? '') == _selectedBranch);
    final names = base.map((m) => m['name']!.trim()).where((s) => s.isNotEmpty);
    final filtered = _stylistQuery.isEmpty
        ? names
        : names.where((s) => s.toLowerCase().contains(_stylistQuery));
    return filtered.toSet().toList();
  }

  void _addSuggested(Map<String, String> svc) {
    if (!_bookedServices.any((s) => s['id'] == svc['id'])) {
      setState(() => _bookedServices.add(svc));
    }
  }

  Future<void> _confirmBooking() async {
    final stylist = _selectedStylist ?? 'No stylist';
    final branch = _selectedBranch;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    String clientEmail = user?.email ?? '';
    String clientName = '';
    try {
      // Try Firestore profile for display name
      if (user != null) {
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        clientName = (profile.data()?['name'] ?? '').toString();
      }
      if (clientName.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        clientName = prefs.getString('display_name') ?? '';
        clientEmail = prefs.getString('email') ?? clientEmail;
      }
    } catch (_) {}

    final batch = FirebaseFirestore.instance.batch();
    for (final s in _bookedServices) {
      final durStr = s['duration'];
      int durMin = 60;
      if (durStr != null && durStr.isNotEmpty) {
        durMin = _parseDurationToMinutes(durStr);
      }
      final startTime = _selectedDate;
      final endTime = startTime.add(Duration(minutes: durMin));
      final doc = FirebaseFirestore.instance.collection('appointments').doc();
      batch.set(doc, {
        'clientName': clientName.isNotEmpty
            ? clientName
            : (clientEmail.split('@').first),
        'clientEmail': clientEmail,
        'serviceId': s['id'] ?? '',
        'serviceName': s['title'] ?? 'Service',
        'price': s['price'] ?? '',
        'duration': durMin, // minutes
        'branch': branch,
        'stylistName': stylist,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (user != null) 'clientUid': user.uid,
      });
    }
    await batch.commit();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MyBookingPage()));
  }

  int _parseDurationToMinutes(String s) {
    // Accepts formats like '1 hr 30 min', '30 min', '2 hr'
    final lower = s.toLowerCase();
    final hrMatch = RegExp(r'(\d+)\s*hr').firstMatch(lower);
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(lower);
    int total = 0;
    if (hrMatch != null) {
      final h = int.tryParse(hrMatch.group(1) ?? '0') ?? 0;
      total += h * 60;
    }
    if (minMatch != null) {
      final m = int.tryParse(minMatch.group(1) ?? '0') ?? 0;
      total += m;
    }
    if (total == 0) return 60;
    return total;
  }

  @override
  void dispose() {
    _stylistSearchCtr.removeListener(_onStylistSearchChanged);
    _stylistSearchCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // stylistsForBranch variable removed (unused); use _stylistsForSelection directly below.

    return Scaffold(
      appBar: AppBar(title: const Text('Book Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.serviceTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            if ((widget.servicePrice ?? '').isNotEmpty)
              Text(
                'Price: ${widget.servicePrice}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),

            // Branch selection
            const Text('Select branch'),
            const SizedBox(height: 6),
            DropdownButton<String>(
              value: _selectedBranch,
              isExpanded: true,
              items: _branches
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedBranch = v;
                  // reset selection; will re-pick first stylist from stream list
                  final options = _stylistsForSelection;
                  _selectedStylist = options.isNotEmpty ? options.first : null;
                  _stylistSearchCtr.clear();
                });
              },
            ),
            const SizedBox(height: 12),

            // Stylist selection + allow stylist from other branch
            Row(
              children: [
                Expanded(child: const Text('Choose stylist')),
                Checkbox(
                  value: _allowOtherBranchStylist,
                  onChanged: (v) => setState(() {
                    _allowOtherBranchStylist = v ?? false;
                    // reset search and selection to first available
                    _stylistSearchCtr.clear();
                    final list = _stylistsForSelection;
                    _selectedStylist = list.isNotEmpty ? list.first : null;
                  }),
                ),
                const Text('Select from other branch'),
              ],
            ),
            const SizedBox(height: 8),

            // Search + avatar scroller for stylists
            TextField(
              controller: _stylistSearchCtr,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search stylist...',
                suffixIcon: _stylistQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _stylistSearchCtr.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: _stylistsForSelection.isEmpty
                  ? const Center(child: Text('No stylists found'))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _stylistsForSelection.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (ctx, i) {
                        final s = _stylistsForSelection[i];
                        final isSelected = s == _selectedStylist;
                        final initials = s
                            .split(' ')
                            .where((p) => p.isNotEmpty)
                            .map((p) => p[0])
                            .take(2)
                            .join()
                            .toUpperCase();
                        final color = Colors
                            .primaries[s.hashCode % Colors.primaries.length];
                        return GestureDetector(
                          onTap: () => setState(() => _selectedStylist = s),
                          child: Column(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: EdgeInsets.all(isSelected ? 3 : 0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          width: 3,
                                        )
                                      : null,
                                ),
                                child: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: color.shade400,
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  s,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                  style: isSelected
                                      ? TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 18),

            // Booked services list
            Text(
              'Services to book',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Column(
              children: _bookedServices.map((s) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text((s['title'] ?? '').substring(0, 1)),
                  ),
                  title: Text(s['title'] ?? ''),
                  trailing: Text(s['price'] ?? ''),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),
            Text(
              'Suggested services',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('services')
                    .limit(10)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading services'));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No suggestions'));
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data();
                      final id = docs[i].id;
                      final title = (data['title'] ?? 'Service').toString();
                      final price = (data['price'] ?? '').toString();
                      final duration = (data['duration'] ?? '').toString();
                      final svc = {
                        'id': id,
                        'title': title,
                        'price': price,
                        'duration': duration,
                      };
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(price),
                              const SizedBox(height: 6),
                              ElevatedButton(
                                onPressed: () => _addSuggested(svc),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            // Calendar
            Text('Select date', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                onDateChanged: (d) {
                  // When a date is picked, show time slots overlay to pick an hour with real-time availability
                  showTimeSlotsDialog(
                    context,
                    d,
                    stylistName: _selectedStylist,
                    branch: _selectedBranch,
                  ).then((chosen) {
                    setState(() {
                      if (chosen != null) {
                        _selectedDate = chosen;
                      } else {
                        // user dismissed: keep date but default to 9AM
                        _selectedDate = DateTime(d.year, d.month, d.day, 9);
                      }
                    });
                  });
                },
              ),
            ),

            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _confirmBooking,
                icon: const Icon(Icons.check),
                label: const Text('Confirm Booking'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
