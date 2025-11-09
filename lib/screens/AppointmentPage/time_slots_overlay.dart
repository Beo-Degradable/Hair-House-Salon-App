import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shows a bottom sheet with hourly time slots between 8:00 and 17:00 (inclusive start at 8)
/// Returns the chosen DateTime (date + hour) or null if dismissed.
/// Shows a bottom sheet with hourly time slots between 8:00 and 17:00 (inclusive start at 8)
/// Returns the chosen DateTime (date + hour) or null if dismissed.
/// If [stylistName] (and optionally [branch]) is provided, the list will reflect
/// real-time availability by disabling booked slots from the `appointments` collection.
Future<DateTime?> showTimeSlotsDialog(
  BuildContext context,
  DateTime forDate, {
  String? stylistName,
  String? branch,
}) {
  final startHour = 8;
  final endHour =
      17; // last start hour is 16 for 8..16 (9 hours). Keep 17 as exclusive end.

  final slots = <DateTime>[];
  for (var h = startHour; h < endHour; h++) {
    slots.add(DateTime(forDate.year, forDate.month, forDate.day, h));
  }

  final dayStart = DateTime(forDate.year, forDate.month, forDate.day, 0, 0);
  final dayEnd = dayStart.add(const Duration(days: 1));

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      // If stylist not provided, we can't compute real availability; just show all slots as enabled.
      final applyRealtime =
          (stylistName != null && stylistName.trim().isNotEmpty);

      final baseQuery = FirebaseFirestore.instance.collection('appointments');
      Query<Map<String, dynamic>> query = baseQuery;
      if (applyRealtime) {
        query = query.where('stylistName', isEqualTo: stylistName);
      }
      if (branch != null && branch.trim().isNotEmpty) {
        query = query.where('branch', isEqualTo: branch);
      }
      // Limit to appointments starting within the selected day for efficiency.
      query = query
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart),
          )
          .where('startTime', isLessThan: Timestamp.fromDate(dayEnd));

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select time',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (applyRealtime)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];

                    bool slotIsBooked(DateTime slotStart) {
                      if (!applyRealtime) return false;
                      for (final d in docs) {
                        final data = d.data();
                        final st = data['startTime'];
                        final et = data['endTime'];
                        DateTime? start;
                        DateTime? end;
                        if (st is Timestamp) start = st.toDate();
                        if (et is Timestamp) end = et.toDate();
                        // backward compatibility if stored differently
                        start ??= st is DateTime
                            ? st
                            : (st is String ? DateTime.tryParse(st) : null);
                        end ??= et is DateTime
                            ? et
                            : (et is String ? DateTime.tryParse(et) : null);
                        if (start == null) continue;
                        end ??= start.add(const Duration(hours: 1));
                        final slotEnd = slotStart.add(const Duration(hours: 1));
                        if (start.isBefore(slotEnd) && end.isAfter(slotStart)) {
                          return true;
                        }
                      }
                      return false;
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load availability',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      );
                    }

                    return Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: slots.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx2, i) {
                          final s = slots[i];
                          final booked = slotIsBooked(s);
                          final label = TimeOfDay.fromDateTime(s).format(ctx2);
                          return ListTile(
                            title: Text(label),
                            subtitle: booked ? const Text('Booked') : null,
                            enabled: !booked,
                            onTap: booked
                                ? null
                                : () => Navigator.of(ctx2).pop(s),
                          );
                        },
                      ),
                    );
                  },
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx2, i) {
                      final s = slots[i];
                      final label = TimeOfDay.fromDateTime(s).format(ctx2);
                      return ListTile(
                        title: Text(label),
                        onTap: () => Navigator.of(ctx2).pop(s),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
