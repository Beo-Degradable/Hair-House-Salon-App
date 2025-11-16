import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'time_slots_overlay.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hxhmobile/screens/Profile/widgets/my_booking_page.dart';
import 'package:hxhmobile/utils/currency.dart';
import 'package:hxhmobile/services/android_notification_service.dart';
import 'package:flutter/services.dart';

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
  // New optional flags for pre-filling points usage when navigated from Points page
  final bool initialUsePoints;
  final int? initialPointsToUse;

  const BookingPage({
    super.key,
    this.serviceId,
    this.serviceTitle,
    this.servicePrice,
    this.serviceDuration,
    this.initialServices,
    this.stylistName,
    this.initialUsePoints = false,
    this.initialPointsToUse,
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

  // Payment UI state
  String? _selectedPaymentMethod; // 'Maya','GCash','PayPal','Card'
  bool _paymentConfirmed = false;
  XFile? _paymentProof;

  // Points
  int _availablePoints = 0;
  bool _usePoints = false;
  final TextEditingController _pointsToUseCtr = TextEditingController();

  // GCash fields
  final TextEditingController _gcashNameCtr = TextEditingController();
  final TextEditingController _gcashNumberCtr = TextEditingController();

  // Maya fields (separate from GCash)
  final TextEditingController _mayaNameCtr = TextEditingController();
  final TextEditingController _mayaNumberCtr = TextEditingController();

  // PayMaya removed (merged behavior into Maya)
  
  // PayPal fields
  final TextEditingController _paypalNameCtr = TextEditingController();
  final TextEditingController _paypalEmailCtr = TextEditingController();

  // Card / Bank transfer fields
  final TextEditingController _acctNameCtr = TextEditingController();
  final TextEditingController _acctNumberCtr = TextEditingController();
  final TextEditingController _bankNameCtr = TextEditingController();
  final TextEditingController _transferAmountCtr = TextEditingController();
  DateTime? _transferDateTime;

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
    // payment field listeners to update UI enablement
    _gcashNameCtr.addListener(() => setState(() {}));
    _gcashNumberCtr.addListener(() => setState(() {}));
    _mayaNameCtr.addListener(() => setState(() {}));
    _mayaNumberCtr.addListener(() => setState(() {}));
    // PayMaya removed
    _paypalNameCtr.addListener(() => setState(() {}));
    _paypalEmailCtr.addListener(() => setState(() {}));
    _acctNameCtr.addListener(() => setState(() {}));
    _acctNumberCtr.addListener(() => setState(() {}));
    _bankNameCtr.addListener(() => setState(() {}));
    _transferAmountCtr.addListener(() => setState(() {}));
    _pointsToUseCtr.addListener(() => setState(() {}));
    _loadAvailablePoints();
    // Apply any initial points flags passed via constructor
    if (widget.initialUsePoints) {
      _usePoints = true;
      if (widget.initialPointsToUse != null) {
        _pointsToUseCtr.text = widget.initialPointsToUse.toString();
      }
    }
  }

  Future<void> _loadAvailablePoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final pts = snap.data()?['points'];
      if (mounted) {
        setState(() {
          _availablePoints = (pts is int) ? pts : (pts is num ? pts.toInt() : 0);
        });
      }
    } catch (_) {}
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
      _selectedStylist != null &&
      _bookedServices.isNotEmpty &&
      _timeSelected &&
      _paymentConfirmed;

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
    final pointsRequested = int.tryParse(_pointsToUseCtr.text.trim()) ?? 0;
    final maxPointsByPrice = (total / 100).floor();
    final pointsToApplyDialog = _usePoints
        ? (pointsRequested > _availablePoints ? _availablePoints : pointsRequested)
        : 0;
    final pointsToApply = pointsToApplyDialog > maxPointsByPrice ? maxPointsByPrice : pointsToApplyDialog;
    final discountedTotal = total - (pointsToApply * 100);
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
                        Text('Reservation fee: ${PhpCurrency.format(300)} — please attach a screenshot of the payment for verification.'),
              const SizedBox(height: 8),
              if (pointsToApply > 0) ...[
                Text('Total: ${PhpCurrency.format(total)}'),
                const SizedBox(height: 4),
                Text('Points applied: $pointsToApply (−${PhpCurrency.format(pointsToApply * 100)})'),
                const SizedBox(height: 4),
                Text('Payable: ${PhpCurrency.format(discountedTotal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ] else ...[
                Text('Total: ${PhpCurrency.format(total)}'),
              ],
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
    String? proofUrl;
    // If user attached a proof image, upload it to Firebase Storage under payments/<docId>/
    if (_paymentProof != null) {
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('payments/${doc.id}/${_paymentProof!.name}');
        // Read full bytes and upload as base64 string to preserve content and follow requirement
        final bytes = await _paymentProof!.readAsBytes();
        final base64Str = base64Encode(bytes);
        // Use PutStringFormat.base64 and set a generic image content type; storage will infer exact type on download
        await ref.putString(
          base64Str,
          format: PutStringFormat.base64,
          metadata: SettableMetadata(contentType: 'image/jpeg'),
        );
        proofUrl = await ref.getDownloadURL();
      } catch (e) {
        // If upload fails, show a message but continue to save appointment without proof URL
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload payment proof: $e')),
          );
        }
      }
    }

    try {
      // Build payment details map explicitly so it's easy to extend and audit
      Map<String, dynamic>? paymentDetails;
      num reservationFee = 300;
      num? amountPaid;
      String storagePath = '';
      if (_selectedPaymentMethod != null) {
        switch (_selectedPaymentMethod) {
          case 'GCash':
            paymentDetails = {
              'name': _gcashNameCtr.text.trim(),
              'number': _gcashNumberCtr.text.trim(),
              'amount': reservationFee,
            };
            amountPaid = reservationFee;
            break;
          case 'Maya':
            paymentDetails = {
              'name': _mayaNameCtr.text.trim(),
              'number': _mayaNumberCtr.text.trim(),
              'amount': reservationFee,
            };
            amountPaid = reservationFee;
            break;
          case 'PayPal':
            paymentDetails = {
              'name': _paypalNameCtr.text.trim(),
              'email': _paypalEmailCtr.text.trim(),
              'amount': reservationFee,
            };
            amountPaid = reservationFee;
            break;
          case 'Card':
            paymentDetails = {
              'accountName': _acctNameCtr.text.trim(),
              'accountNumber': _acctNumberCtr.text.trim(),
              'bankName': _bankNameCtr.text.trim(),
              // Reservation fee is fixed
              'amount': reservationFee,
              'transferDate': _transferDateTime != null ? Timestamp.fromDate(_transferDateTime!) : null,
            };
            // For card, reservation fee is used as the amountPaid for the reservation
            amountPaid = reservationFee;
            break;
          default:
            paymentDetails = null;
            break;
        }
      }

      // If proof uploaded, record storage path
      if (_paymentProof != null) {
        storagePath = 'payments/${doc.id}/${_paymentProof!.name}';
      }

      final paymentMap = {
        'method': _selectedPaymentMethod ?? 'unknown',
        'confirmed': _paymentConfirmed,
        'details': paymentDetails,
        'amountPaid': amountPaid,
        'proofStoragePath': storagePath.isNotEmpty ? storagePath : null,
        'proofUrl': proofUrl,
      };

      // Compute total price of services to determine max usable points
      final totalPrice = services.fold<double>(0, (sum, s) {
        final price = s['price'];
        if (price is num) return sum + price.toDouble();
        if (price is String) return sum + (double.tryParse(price) ?? 0);
        return sum;
      });
      final pointsRequested = int.tryParse(_pointsToUseCtr.text.trim()) ?? 0;
      final maxPointsByPrice = (totalPrice / 100).floor();
      final pointsToUse = pointsRequested < 0
          ? 0
          : (pointsRequested > _availablePoints ? _availablePoints : pointsRequested);
      final pointsToApply = pointsToUse > maxPointsByPrice ? maxPointsByPrice : pointsToUse;
      final pointsDiscount = pointsToApply * 100;

      final appointmentData = {
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
        // Reservation and payment metadata
        'reservationFee': reservationFee,
        'reservationPaid': _paymentConfirmed,
        if (_paymentConfirmed) 'paymentConfirmedAt': FieldValue.serverTimestamp(),
        'payment': paymentMap,
        if (pointsToApply > 0) 'pointsUsed': pointsToApply,
        if (pointsToApply > 0) 'pointsDiscount': pointsDiscount,
      };

      if (user != null && pointsToApply > 0) {
        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final apptRef = doc;
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final uSnap = await tx.get(userRef);
          final current = uSnap.data()?['points'];
          final currentPts = (current is int) ? current : (current is num ? current.toInt() : 0);
          if (currentPts < pointsToApply) {
            throw Exception('Not enough points');
          }
          tx.update(userRef, {'points': FieldValue.increment(-pointsToApply)});
          tx.set(apptRef, appointmentData);
        });
      } else {
        await doc.set(appointmentData);
      }
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
    // Refresh available points after booking (if user exists)
    await _loadAvailablePoints();
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
    // dispose payment controllers
    _gcashNameCtr.dispose();
    _gcashNumberCtr.dispose();
    _mayaNameCtr.dispose();
    _mayaNumberCtr.dispose();
    // PayMaya removed
    _paypalNameCtr.dispose();
    _paypalEmailCtr.dispose();
    _acctNameCtr.dispose();
    _acctNumberCtr.dispose();
    _bankNameCtr.dispose();
    _transferAmountCtr.dispose();
    _pointsToUseCtr.dispose();
    super.dispose();
  }

  // Image picker for payment proof
  Future<void> _pickPaymentProof() async {
    try {
      final picker = ImagePicker();
      // Pick the image at maximum available resolution (do not pass maxWidth/maxHeight)
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _paymentProof = picked;
          _paymentConfirmed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _pickTransferDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() {
      _transferDateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  void _confirmPaymentMethod() {
    // Basic validation already guarded by button enabling; mark as confirmed
    setState(() {
      _paymentConfirmed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment method confirmed')));
  }

  // Validation helpers
  bool _isValidName(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    final re = RegExp(r"^[A-Za-z\s'\-]+$");
    return re.hasMatch(v);
  }

  bool _isValidNumber(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    final re = RegExp(r'^\d+$');
    return re.hasMatch(v);
  }

  bool _isValidEmail(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v);
  }


  @override
  Widget build(BuildContext context) {
    // stylistsForBranch variable removed (unused); use _stylistsForSelection directly below.
    // Compute totals and points application for live UI
    final double _liveTotalPrice = _bookedServices.fold<double>(
      0,
      (sum, s) => sum + (PhpCurrency.parse(s['price']) ?? 0),
    );
    final int _pointsRequested = int.tryParse(_pointsToUseCtr.text.trim()) ?? 0;
    final int _maxPointsByPrice = (_liveTotalPrice / 100).floor();
    final int _pointsRequestedLimited = _usePoints
        ? (_pointsRequested > _availablePoints ? _availablePoints : _pointsRequested)
        : 0;
    final int _pointsToApply = _pointsRequestedLimited > _maxPointsByPrice ? _maxPointsByPrice : _pointsRequestedLimited;
    final double _discountedTotal = _liveTotalPrice - (_pointsToApply * 100);

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

            // Payment method label (outside the decorated container)
            Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // Payment method container
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: ['Maya', 'GCash', 'PayPal', 'Card']
                        .map((m) => ChoiceChip(
                              label: Text(m),
                              selected: _selectedPaymentMethod == m,
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedPaymentMethod = m;
                                  } else {
                                    _selectedPaymentMethod = null;
                                  }
                                  _paymentConfirmed = false;
                                  _paymentProof = null;
                                  _gcashNameCtr.clear();
                                  _gcashNumberCtr.clear();
                                  _mayaNameCtr.clear();
                                  _mayaNumberCtr.clear();
                                  // PayMaya removed
                                  _paypalNameCtr.clear();
                                  _paypalEmailCtr.clear();
                                  _acctNameCtr.clear();
                                  _acctNumberCtr.clear();
                                  _bankNameCtr.clear();
                                  _transferAmountCtr.clear();
                                  _transferDateTime = null;
                                });
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedPaymentMethod != null) ...[
                    const SizedBox(height: 8),
                    if (_selectedPaymentMethod == 'GCash') ...[
                      TextField(
                        controller: _gcashNameCtr,
                        decoration: const InputDecoration(labelText: 'Name'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s'\-]")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _gcashNumberCtr,
                        decoration: const InputDecoration(labelText: 'Number'),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 8),
                      Text('Reservation fee: ${PhpCurrency.format(300)} — please attach a screenshot of the payment for verification.'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickPaymentProof,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach proof'),
                          ),
                          const SizedBox(width: 12),
                          if (_paymentProof != null) ...[
                            SizedBox(
                              width: 80,
                              height: 60,
                              child: Image.file(File(_paymentProof!.path), fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Note: Once the reservation is done there is no refund.'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: (_paymentProof != null && _isValidName(_gcashNameCtr.text) && _isValidNumber(_gcashNumberCtr.text))
                            ? _confirmPaymentMethod
                            : null,
                        child: Text(_paymentConfirmed ? 'Payment Confirmed' : 'Confirm Payment Method'),
                      ),
                    ] else if (_selectedPaymentMethod == 'Maya') ...[
                      TextField(
                        controller: _mayaNameCtr,
                        decoration: const InputDecoration(labelText: 'Name'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s'\-]")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mayaNumberCtr,
                        decoration: const InputDecoration(labelText: 'Number'),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 8),
                      Text('Reservation fee: ${PhpCurrency.format(300)} — please attach a screenshot of the payment for verification.'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickPaymentProof,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach proof'),
                          ),
                          const SizedBox(width: 12),
                          if (_paymentProof != null) ...[
                            SizedBox(
                              width: 80,
                              height: 60,
                              child: Image.file(File(_paymentProof!.path), fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Note: Once the reservation is done there is no refund.'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: (_paymentProof != null && _isValidName(_mayaNameCtr.text) && _isValidNumber(_mayaNumberCtr.text))
                            ? _confirmPaymentMethod
                            : null,
                        child: Text(_paymentConfirmed ? 'Payment Confirmed' : 'Confirm Payment Method'),
                      ),
                    ] else if (_selectedPaymentMethod == 'PayPal') ...[
                      TextField(
                        controller: _paypalNameCtr,
                        decoration: const InputDecoration(labelText: 'Name'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s'\-]")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _paypalEmailCtr,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9@._\-+]") ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Reservation fee: ${PhpCurrency.format(300)} — please attach a screenshot of the payment for verification.'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickPaymentProof,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach proof'),
                          ),
                          const SizedBox(width: 12),
                          if (_paymentProof != null) ...[
                            SizedBox(
                              width: 80,
                              height: 60,
                              child: Image.file(File(_paymentProof!.path), fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: (_paymentProof != null && _isValidName(_paypalNameCtr.text) && _isValidEmail(_paypalEmailCtr.text))
                            ? _confirmPaymentMethod
                            : null,
                        child: Text(_paymentConfirmed ? 'Payment Confirmed' : 'Confirm Payment Method'),
                      ),
                    ] else if (_selectedPaymentMethod == 'Card') ...[
                      TextField(
                        controller: _acctNameCtr,
                        decoration: const InputDecoration(labelText: 'Account name (or name on account)'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s'\-]")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _acctNumberCtr,
                        decoration: const InputDecoration(labelText: 'Account number'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bankNameCtr,
                        decoration: const InputDecoration(labelText: 'Bank name'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s'\-]")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Reservation fee: ${PhpCurrency.format(300)} — please attach a screenshot of the payment for verification.'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(_transferDateTime == null ? 'No transfer date/time' : '${_transferDateTime!.toLocal()}'),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _pickTransferDateTime,
                            child: const Text('Pick date/time'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickPaymentProof,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach proof'),
                          ),
                          const SizedBox(width: 12),
                          if (_paymentProof != null) ...[
                            SizedBox(
                              width: 80,
                              height: 60,
                              child: Image.file(File(_paymentProof!.path), fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Note: Once the reservation is done there is no refund.'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: (_paymentProof != null && _isValidName(_acctNameCtr.text) && _isValidNumber(_acctNumberCtr.text) && _isValidName(_bankNameCtr.text) && _transferDateTime != null)
                            ? _confirmPaymentMethod
                            : null,
                        child: Text(_paymentConfirmed ? 'Payment Confirmed' : 'Confirm Payment Method'),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text('Fill required fields for the selected payment method, then attach proof and confirm.'),
                    ]
                  ],
                ],
              ),
            ),

            // Points usage section (placed below payment method)
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(value: _usePoints, onChanged: (v) {
                  setState(() {
                    _usePoints = v ?? false;
                    if (!_usePoints) _pointsToUseCtr.clear();
                  });
                }),
                const SizedBox(width: 6),
                Expanded(child: Text('Use points (1 point = ₱100). Available: $_availablePoints')),
              ],
            ),
            if (_usePoints) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _pointsToUseCtr,
                decoration: InputDecoration(
                  labelText: 'Points to use',
                  hintText: 'Max ${_availablePoints}',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 8),
            ],

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

            // Itemized total and calculation preview (shown under calendar)
            if (_bookedServices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Itemized services
                    ..._bookedServices.map<Widget>((s) {
                      final title = (s['title'] ?? '').toString();
                      final price = s['price'] != null ? s['price'].toString() : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(title)),
                            Text(PhpCurrency.formatFromString(price)),
                          ],
                        ),
                      );
                    }).toList(),
                    const Divider(),
                    // Subtotal / total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: Theme.of(context).textTheme.bodyMedium),
                        Text(PhpCurrency.format(_liveTotalPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Points applied and payable calculation
                    if (_pointsToApply > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Points ($_pointsToApply)', style: Theme.of(context).textTheme.bodyMedium),
                          Text('- ${PhpCurrency.format(_pointsToApply * 100)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Payable', style: Theme.of(context).textTheme.bodyMedium),
                          Text(PhpCurrency.format(_discountedTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Calculation: ${PhpCurrency.format(_liveTotalPrice)} - (${_pointsToApply} × ₱100) = ${PhpCurrency.format(_discountedTotal)}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Duration:', style: Theme.of(context).textTheme.bodyMedium),
                          Text(_formatDurationHM(_totalBookedDurationMinutes()), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

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
