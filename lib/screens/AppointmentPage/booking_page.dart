import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'time_slots_overlay.dart';
import 'package:hxhmobile/screens/Profile/widgets/my_booking_page.dart';
import 'package:hxhmobile/utils/currency.dart';
import 'package:hxhmobile/services/android_notification_service.dart';

class BookingPage extends StatefulWidget {
  // Legacy single-service parameters (optional now)
  final String? serviceId;
  final String? serviceTitle;
  final String? servicePrice;
  final String? serviceDuration; // e.g. '1 hr 30 min' or '30 min'
  // New: allow passing multiple services at once
  // Each map expects keys: id, title, price, duration
  final List<Map<String, String>>? initialServices;
  // Pre-selected stylist name
  final String? stylistName;

  const BookingPage({
    super.key,
    this.serviceId,
    this.serviceTitle,
    this.servicePrice,
    this.serviceDuration,
    this.initialServices,
    this.stylistName,
  });

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  // Utility to format minutes as hours/minutes string
  String _formatDurationHM(int minutes) {
    if (minutes <= 0) return '0 min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) {
      return '${h} hr ${m} min';
    } else if (h > 0) {
      return '${h} hr';
    } else {
      return '${m} min';
    }
  }

  // Utility to format minutes as hours/minutes string
  // Branches used throughout the app
  final List<String> _branches = const ['Vergara', 'Lawas', 'Lipa', 'Tanauan'];

  String _selectedBranch = 'Vergara';
  String? _selectedStylist;
  bool _allowOtherBranchStylist = false;
  DateTime _selectedDate = DateTime.now();
  bool _timeSelected = false; // require explicit time pick from overlay
  // stylist search + controller for avatar scroller
  final TextEditingController _stylistSearchCtr = TextEditingController();
  String _stylistQuery = '';
  // live stylists pulled from users collection
  List<Map<String, dynamic>> _stylists = const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _stylistsSub;

  // booked services starts with the selected service from Home
  final List<Map<String, String>> _bookedServices = [];

  // removed old static _suggested list; suggestions now come live from Firestore

  @override
  void initState() {
    super.initState();
    if (widget.initialServices != null && widget.initialServices!.isNotEmpty) {
      _bookedServices.addAll(widget.initialServices!);
    } else if (widget.serviceId != null && widget.serviceTitle != null) {
      _bookedServices.add({
        'id': widget.serviceId!,
        'title': widget.serviceTitle!,
        'price': widget.servicePrice ?? '',
        'duration': widget.serviceDuration ?? '',
      });
    }
    // Pre-select stylist if provided
    if (widget.stylistName != null && widget.stylistName!.isNotEmpty) {
      _selectedStylist = widget.stylistName;
    }
    // start listening to stylists
    _resubscribeStylists();
    // stylist search listener
    _stylistSearchCtr.addListener(_onStylistSearchChanged);
  }

  void _resubscribeStylists() {
    // Cancel any existing subscription
    _stylistsSub?.cancel();
    // Build base query
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'stylist');
    // If other-branch selection is NOT allowed, filter server-side by branchName for efficiency
    if (!_allowOtherBranchStylist) {
      q = q.where('branchName', isEqualTo: _selectedBranch);
    }
    _stylistsSub = q.snapshots().listen((snap) {
      final list = snap.docs
          .map((d) {
            final data = d.data();
            return {
              'name': (data['name'] ?? '').toString(),
              'branchName': (data['branchName'] ?? '').toString(),
              'branch': (data['branch'] ?? '').toString(),
              'branches': data['branches'] is List
                  ? (data['branches'] as List).map((e) => e.toString()).toList()
                  : const <String>[],
            };
          })
          .where((m) => ((m['name'] ?? '') as String).isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _stylists = list;
        // Do not auto-pick stylist. If current selection no longer valid, clear it.
        final options = _stylistsForSelection;
        if (_selectedStylist != null && !options.contains(_selectedStylist)) {
          _selectedStylist = null;
        }
      });
    });
  }

  void _onStylistSearchChanged() {
    setState(() => _stylistQuery = _stylistSearchCtr.text.trim().toLowerCase());
  }

  String _norm(String v) => v.toLowerCase().trim();

  bool _matchesBranch(Map<String, dynamic> m) {
    if (_allowOtherBranchStylist) return true;
    final sel = _norm(_selectedBranch);
    final bn = (m['branchName'] ?? '').toString();
    if (bn.isNotEmpty && _norm(bn) == sel) return true;
    final b = (m['branch'] ?? '').toString();
    if (b.isNotEmpty && _norm(b) == sel) return true;
    final list = (m['branches'] is List)
        ? (m['branches'] as List).map((e) => _norm(e.toString()))
        : const Iterable<String>.empty();
    return list.contains(sel);
  }

  List<String> get _stylistsForSelection {
    // build from Firestore stylists list, filter by branch (supports 'branch' or 'branches' array)
    final base = _stylists.where(_matchesBranch);
    final names = base
        .map((m) => (m['name'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty);
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

  bool get _canConfirm =>
      _selectedStylist != null && _bookedServices.isNotEmpty && _timeSelected;

  Future<void> _showConfirmDialogAndBook() async {
    if (!_canConfirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a stylist and time.')),
      );
      return;
    }

    final total = _bookedServices.fold<double>(
      0,
      (sum, s) => sum + (PhpCurrency.parse(s['price']) ?? 0),
    );
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${_selectedDate.hour.toString().padLeft(2, '0')}:${_selectedDate.minute.toString().padLeft(2, '0')}';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm appointment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Branch: $_selectedBranch'),
              Text('Stylist: ${_selectedStylist ?? ''}'),
              Text('Date: $dateStr'),
              Text('Time: $timeStr'),
              const SizedBox(height: 8),
              Text('Services:', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ..._bookedServices.map((s) => Text('- ${s['title']}')),
              const SizedBox(height: 8),
              Text('Total: ${PhpCurrency.format(total)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final success = await _confirmBooking();
    if (!success) {
      // Error already shown inside _confirmBooking
      return;
    }

    // After booking, send a local notification (Android-only via existing service)
    final firstService = _bookedServices.first['title'] ?? 'Appointment';
    final stylist = _selectedStylist ?? '';
    final when = '$dateStr $timeStr';
    final title = 'Appointment confirmed';
    final body = stylist.isNotEmpty
        ? 'Thanks for booking $firstService with $stylist on $when'
        : 'Thanks for booking $firstService on $when';
    try {
      await AndroidNotificationService.ensureInitialized();
      // Immediate notification
      await AndroidNotificationService.showNow(
        title: title,
        body: body,
        payload: 'route=/appointments',
      );
      // Optional: schedule a reminder 30 minutes before
      await AndroidNotificationService.scheduleAppointmentReminder(
        appointmentStart: _selectedDate,
        leadMinutes: 30,
        serviceName: firstService,
        stylistName: stylist.isNotEmpty ? stylist : null,
      );
    } catch (_) {
      // Best-effort; ignore notification errors.
    }
  }

  Future<bool> _confirmBooking() async {
    if (!_canConfirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a stylist and time.')),
      );
      return false;
    }
    final stylist = _selectedStylist!;
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

    // Schedule each service sequentially and record their start/end times
    int totalDuration = 0;
    final services = <Map<String, dynamic>>[];
    DateTime serviceStart = _selectedDate;
    for (final s in _bookedServices) {
      final durStr = s['duration'];
      int durMin = 60;
      if (durStr != null && durStr.isNotEmpty) {
        durMin = _parseDurationToMinutes(durStr);
      }
      final serviceEnd = serviceStart.add(Duration(minutes: durMin));
      services.add({
        ...s,
        'startTime': Timestamp.fromDate(serviceStart),
        'endTime': Timestamp.fromDate(serviceEnd),
        'durationMinutes': durMin,
      });
      totalDuration += durMin;
      serviceStart = serviceEnd;
    }
    final appointmentStart = _selectedDate;
    final appointmentEnd = appointmentStart.add(
      Duration(minutes: totalDuration),
    );
    final doc = FirebaseFirestore.instance.collection('appointments').doc();
    try {
      await doc.set({
        'clientName': clientName.isNotEmpty
            ? clientName
            : (clientEmail.split('@').first),
        'clientEmail': clientEmail,
        'services': services, // each service has its own start/end
        'totalDuration': totalDuration, // minutes
        'branch': branch,
        'stylistName': stylist,
        'startTime': Timestamp.fromDate(appointmentStart),
        'endTime': Timestamp.fromDate(appointmentEnd),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (user != null) 'clientUid': user.uid,
      });
      // Add notification to Firestore
      if (user != null) {
        // Confirmation notification
        await FirebaseFirestore.instance.collection('notifications').add({
          'userUid': user.uid,
          'type': 'appointment',
          'title': 'Thank you for booking!',
          'body': 'Your appointment has been confirmed.',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Persistent appointment reminder notification
        final when =
            '${appointmentStart.month}/${appointmentStart.day} ${TimeOfDay.fromDateTime(appointmentStart).format(context)}';
        final serviceNames = services
            .map((s) => s['title'] ?? 'Service')
            .join(', ');
        final reminderBody = stylist.isNotEmpty
            ? '$serviceNames with $stylist at $when'
            : '$serviceNames at $when';
        await FirebaseFirestore.instance.collection('notifications').add({
          'userUid': user.uid,
          'type': 'reminder',
          'title': 'Appointment reminder',
          'body': reminderBody,
          'timestamp': Timestamp.fromDate(appointmentStart),
          'read': false,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save booking: $e')));
      }
      return false;
    }
    if (!mounted) return true;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MyBookingPage()));
    return true;
  }

  int _parseDurationToMinutes(String s) {
    // Accepts formats like '1 hr 30 min', '30 min', '2 hr', '165m', '2h', '2hours', etc.
    final lower = s.toLowerCase().replaceAll(' ', '');
    int total = 0;
    // Match 'Xhr', 'Xh', 'Xhours', etc.
    final hrMatch = RegExp(r'(\d+)\s*(hr|h|hours?)').firstMatch(lower);
    if (hrMatch != null) {
      final h = int.tryParse(hrMatch.group(1) ?? '0') ?? 0;
      total += h * 60;
    }
    // Match 'Xmin', 'Xm', etc.
    final minMatch = RegExp(r'(\d+)\s*(min|m)').firstMatch(lower);
    if (minMatch != null) {
      final m = int.tryParse(minMatch.group(1) ?? '0') ?? 0;
      total += m;
    }
    // If string is just a number (e.g., '90'), treat as minutes
    if (total == 0) {
      final justNum = int.tryParse(lower);
      if (justNum != null && justNum > 0) {
        total = justNum;
      }
    }
    // If still zero, default to 60
    if (total == 0) return 60;
    return total;
  }

  String _shortestName(String full) {
    final cleaned = full.replaceAll(RegExp(r'[\(\)\[\]\.,]'), ' ');
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return full.trim();
    // Pick the shortest token; if tie, keep the first occurrence
    tokens.sort((a, b) => a.length.compareTo(b.length));
    return tokens.first;
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final first = parts.first[0].toUpperCase();
    final second = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return (first + second);
  }

  String _shortDisplayName(String full) {
    final token = _shortestName(full).toLowerCase();
    if (token.length <= 8) return token;
    return '${token.substring(0, 6)}..';
  }

  @override
  void dispose() {
    _stylistsSub?.cancel();
    _stylistSearchCtr.removeListener(_onStylistSearchChanged);
    _stylistSearchCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // stylistsForBranch variable removed (unused); use _stylistsForSelection directly below.

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Service'),
        actions: [
          IconButton(
            tooltip: 'My Bookings',
            icon: const Icon(Icons.event_note),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const MyBookingPage()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stylist selection + allow stylist from other branch
            Row(
              children: [
                Expanded(child: const Text('Choose stylist')),
                Checkbox(
                  value: _allowOtherBranchStylist,
                  onChanged: (v) => setState(() {
                    _allowOtherBranchStylist = v ?? false;
                    // reset search and clear selection; user must pick manually
                    _stylistSearchCtr.clear();
                    _selectedStylist = null;
                    _resubscribeStylists();
                  }),
                ),
                const Text('Select from other branch'),
              ],
            ),
            const SizedBox(height: 8),

            // Branch selection + stylist search aligned horizontally (under 'Choose stylist')
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBranch,
                    items: _branches
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedBranch = v;
                        // Clear selection; user must pick stylist manually for new branch
                        _selectedStylist = null;
                        _stylistSearchCtr.clear();
                        _resubscribeStylists();
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Branch',
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
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
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stylists scroller (profile frame with initials + short name below)
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
                        final short = _shortDisplayName(s);
                        final initials = _initials(s);
                        final color = Colors
                            .primaries[s.hashCode % Colors.primaries.length];
                        return GestureDetector(
                          onTap: () => setState(() => _selectedStylist = s),
                          child: Column(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: EdgeInsets.all(isSelected ? 3 : 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                    width: isSelected ? 2 : 1,
                                  ),
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
                                  short,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : null,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 18),

            // Booked services list with pluralization
            Text(
              _bookedServices.length == 1
                  ? 'Booked Service'
                  : 'Booked Services',
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
                  trailing: Text(PhpCurrency.formatFromString(s['price'])),
                );
              }).toList(),
            ),

            // Total for booked services
            if (_bookedServices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Total: ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    PhpCurrency.format(
                      _bookedServices.fold<double>(
                        0,
                        (sum, s) => sum + (PhpCurrency.parse(s['price']) ?? 0),
                      ),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Total Duration: ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDurationHM(_totalBookedDurationMinutes()),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],

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
                      final title = (data['title'] ?? data['name'] ?? 'Service')
                          .toString();
                      final price = data['price'] != null
                          ? data['price'].toString()
                          : '';
                      final duration =
                          (data['duration'] ?? data['durationMinutes'] ?? '')
                              .toString();
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
                              Text(PhpCurrency.formatFromString(price)),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    requiredDurationMinutes: _totalBookedDurationMinutes(),
                  ).then((chosen) {
                    setState(() {
                      if (chosen != null) {
                        _selectedDate = chosen;
                        _timeSelected = true;
                      } else {
                        // user dismissed: require explicit selection
                        _timeSelected = false;
                      }
                    });
                  });
                },
              ),
            ),

            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _canConfirm ? _showConfirmDialogAndBook : null,
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

  int _totalBookedDurationMinutes() {
    int total = 0;
    for (final s in _bookedServices) {
      final raw = (s['duration'] ?? '').trim();
      int add = 0;
      if (raw.isEmpty) {
        add = 60;
      } else {
        // if it's a plain number in minutes
        final asInt = int.tryParse(raw);
        if (asInt != null) {
          add = asInt;
        } else {
          add = _parseDurationToMinutes(raw);
        }
      }
      if (add <= 0) add = 60;
      total += add;
    }
    // minimum 15, maximum 12 hours safety
    return total.clamp(15, 12 * 60);
  }
}
