import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CancellationReasonPage extends StatefulWidget {
  final String appointmentId;
  final DateTime appointmentStart;
  final String serviceName;
  final String currentStatus;
  const CancellationReasonPage({
    super.key,
    required this.appointmentId,
    required this.appointmentStart,
    required this.serviceName,
    required this.currentStatus,
  });

  @override
  State<CancellationReasonPage> createState() => _CancellationReasonPageState();
}

class _CancellationReasonPageState extends State<CancellationReasonPage> {
  final Map<String, bool> _reasons = {
    'Change of plans': false,
    'Found a better time': false,
    'Illness / Not feeling well': false,
    'Travel / Emergency': false,
    'Other': false,
  };

  final TextEditingController _otherCtr = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _otherCtr.dispose();
    super.dispose();
  }

  Future<void> _submitCancellation() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final selected = _reasons.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one reason')),
      );
      setState(() => _submitting = false);
      return;
    }
    String reasonSummary = selected.join(', ');
    if (_reasons['Other'] == true && _otherCtr.text.trim().isNotEmpty) {
      reasonSummary += ' | Other: ${_otherCtr.text.trim()}';
    }

    final hoursUntil = widget.appointmentStart
        .difference(DateTime.now())
        .inHours;
    final isInstant = hoursUntil >= 12; // >=12h cancels immediately, <12h flags
    final newStatus = isInstant ? 'cancelled' : 'pending_cancel';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm cancellation'),
        content: Text(
          isInstant
              ? 'Do you really want to cancel this appointment?'
              : 'This is less than 12 hours before start. A request will be sent to admin for approval. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      setState(() => _submitting = false);
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId);
      final updates = {
        'status': newStatus,
        if (isInstant)
          'cancelledAt': FieldValue.serverTimestamp()
        else
          'cancelRequestAt': FieldValue.serverTimestamp(),
        'cancellationReason': reasonSummary,
        'cancellationBy': uid,
      };
      await apptRef.update(updates);

      // Log to history collection
      await FirebaseFirestore.instance.collection('history').add({
        'appointmentId': widget.appointmentId,
        'action': isInstant ? 'cancelled' : 'requested_cancel',
        'reason': reasonSummary,
        'statusTarget': newStatus,
        'timestamp': FieldValue.serverTimestamp(),
        'userUid': uid,
        'serviceName': widget.serviceName,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isInstant ? 'Appointment cancelled' : 'Cancellation request sent',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCancel =
        widget.currentStatus != 'cancelled' &&
        widget.currentStatus != 'pending_cancel';
    return Scaffold(
      appBar: AppBar(title: const Text('Cancel Appointment')),
      body: canCancel
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select reasons',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ..._reasons.keys.map((r) {
                          final v = _reasons[r]!;
                          return CheckboxListTile(
                            value: v,
                            onChanged: (nv) =>
                                setState(() => _reasons[r] = nv ?? false),
                            title: Text(r),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }),
                        if (_reasons['Other'] == true)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: TextField(
                              controller: _otherCtr,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Describe other reason...',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submitCancellation,
                          icon: const Icon(Icons.check),
                          label: _submitting
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Confirm'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: Text(
                      'Note: Cancellations ≥12 hours before start are immediate. Requests <12 hours are flagged for admin approval.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: Text('Already cancelled or pending approval.')),
    );
  }
}
