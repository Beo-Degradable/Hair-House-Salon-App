import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

String _hourLabel(DateTime dt) {
  final h = dt.hour;
  final suffix = h >= 12 ? 'PM' : 'AM';
  int hour12 = h % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12 $suffix';
}

/// Shows a bottom sheet with hourly time slots between 8:00 AM and 5:00 PM (inclusive starts at 8 and 17)
/// Returns the chosen DateTime (date + hour) or null if dismissed.
/// Shows a bottom sheet with hourly time slots between 8:00 AM and 5:00 PM (inclusive starts at 8 and 17)
/// Returns the chosen DateTime (date + hour) or null if dismissed.
/// If [stylistName] (and optionally [branch]) is provided, the list will reflect
/// real-time availability by disabling booked slots from the `appointments` collection.
Future<DateTime?> showTimeSlotsDialog(
  BuildContext context,
  DateTime forDate, {
  String? stylistName,
  String? branch,
  int? requiredDurationMinutes,
}) {
  final startHour = 8;
  // We want start times from 8 through 17 (5 PM) inclusive, so set exclusive end to 18
  final endHour = 18; // produces slots for 8..17

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
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: query.get(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];
                    debugPrint(
                      'Time slots returned ${docs.length} appointment docs',
                    );
                    for (final d in docs) {
                      try {
                        final data = d.data();
                        debugPrint(
                          'appt doc ${d.id} start=${data['startTime']} end=${data['endTime']} totalDuration=${data['totalDuration'] ?? data['duration'] ?? data['durationMinutes']}',
                        );
                      } catch (_) {}
                    }

                    bool slotIsBooked(DateTime slotStart) {
                      if (!applyRealtime) return false;
                      for (final d in docs) {
                        final data = d.data();
                        DateTime? start;
                        DateTime? end;
                        final st = data['startTime'];
                        final et = data['endTime'];
                        if (st is Timestamp) start = st.toDate();
                        if (et is Timestamp) end = et.toDate();
                        start ??= st is DateTime
                            ? st
                            : (st is String ? DateTime.tryParse(st) : null);
                        end ??= et is DateTime
                            ? et
                            : (et is String ? DateTime.tryParse(et) : null);
                        if (start == null || end == null) continue;
                        final slotEnd = slotStart.add(const Duration(hours: 1));
                        // If any part of the slot overlaps with the appointment, mark as booked
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
                      // Show detailed error to help diagnose why the query failed.
                      final err = snapshot.error;
                      debugPrint('Time slots query error: $err');
                      return Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Availability unavailable. Showing raw slots.\nError: ${err ?? 'unknown'}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: slots.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (ctx2, i) {
                                  final s = slots[i];
                                  final label = _hourLabel(s);
                                  return ListTile(
                                    title: Text(label),
                                    // Can't confirm booking status; allow selection
                                    onTap: () => Navigator.of(ctx2).pop(s),
                                  );
                                },
                              ),
                            ),
                          ],
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
                          final int requiredMin =
                              (requiredDurationMinutes ?? 60).clamp(
                                15,
                                12 * 60,
                              );
                          bool booked = slotIsBooked(s);
                          if (!booked && requiredMin != 60) {
                            // Check if the entire required duration fits without overlapping
                            final sEnd = s.add(Duration(minutes: requiredMin));
                            for (final d in docs) {
                              final data = d.data();
                              final st = data['startTime'];
                              final et = data['endTime'];
                              DateTime? start;
                              DateTime? end;
                              if (st is Timestamp) start = st.toDate();
                              if (et is Timestamp) end = et.toDate();
                              start ??= st is DateTime
                                  ? st
                                  : (st is String
                                        ? DateTime.tryParse(st)
                                        : null);
                              end ??= et is DateTime
                                  ? et
                                  : (et is String
                                        ? DateTime.tryParse(et)
                                        : null);
                              if (start == null) continue;
                              if (end == null) {
                                final dynDur = data['duration'];
                                final dynDurMin = data['durationMinutes'];
                                int minutes = 60;
                                if (dynDur is int) {
                                  minutes = dynDur;
                                } else if (dynDurMin is int) {
                                  minutes = dynDurMin;
                                } else if (dynDur is num) {
                                  minutes = dynDur.toInt();
                                } else if (dynDurMin is num) {
                                  minutes = dynDurMin.toInt();
                                }
                                end = start.add(Duration(minutes: minutes));
                              }
                              if (start.isBefore(sEnd) && end.isAfter(s)) {
                                booked = true;
                                break;
                              }
                            }
                          }
                          final label = _hourLabel(s);
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
                      final label = _hourLabel(s);
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
