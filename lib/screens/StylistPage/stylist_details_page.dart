import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../AppointmentPage/booking_page.dart';

class StylistDetailsPage extends StatelessWidget {
  final Map<String, String>?
  stylist; // legacy/local map (kept for layout stability)
  final String? userId; // optional Firestore user id (stylist profile)
  const StylistDetailsPage({Key? key, this.stylist, this.userId})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Firestore stream if userId provided; else null
    final stream = (userId != null && userId!.isNotEmpty)
        ? FirebaseFirestore.instance.collection('users').doc(userId).snapshots()
        : null;

    Widget buildContent(
      String name,
      String exp,
      String specialization,
      String email,
      String branch,
    ) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile frame
            const CircleAvatar(radius: 60, child: Icon(Icons.person, size: 60)),
            const SizedBox(height: 16),
            // Name
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            // Email
            if (email.isNotEmpty)
              Text(email, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            // Experience
            if (exp.isNotEmpty)
              Text(
                'Experience: $exp years',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 8),
            // Branch
            if (branch.isNotEmpty)
              Text(
                'Branch: $branch',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            // Divider
            const Divider(),
            const SizedBox(height: 16),
            // Specialization
            if (specialization.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Specialized Services:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    specialization,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            const Spacer(),
            // Book Now button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BookingPage(stylistName: name),
                    ),
                  );
                },
                child: const Text('Book Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (stream == null) {
      // Fallback to provided stylist map only
      final name = stylist != null
          ? (stylist!['name'] ?? 'Stylist')
          : 'Stylist';
      final exp = stylist != null ? (stylist!['exp'] ?? '') : '';
      final specialization = stylist != null
          ? (stylist!['specialization'] ?? '')
          : '';
      final email = stylist != null ? (stylist!['email'] ?? '') : '';
      final branch = stylist != null ? (stylist!['branch'] ?? '') : '';
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        body: buildContent(name, exp, specialization, email, branch),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        // Use Firestore data with graceful fallback to legacy stylist map
        final data = snap.data?.data() ?? const <String, dynamic>{};
        // Expecting optional fields: name, stylist_exp, stylist_specialization
        final name = (data['name'] ?? stylist?['name'] ?? 'Stylist').toString();
        final exp = (data['stylist_exp'] ?? stylist?['exp'] ?? '').toString();
        final specialization =
            (data['stylist_specialization'] ?? stylist?['specialization'] ?? '')
                .toString();
        final email = (data['email'] ?? stylist?['email'] ?? '').toString();
        final branch = (data['branch'] ?? stylist?['branch'] ?? '').toString();

        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: snap.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : buildContent(name, exp, specialization, email, branch),
        );
      },
    );
  }
}
