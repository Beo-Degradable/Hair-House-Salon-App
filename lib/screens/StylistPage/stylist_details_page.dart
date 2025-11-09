import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    Widget buildContent(String name, String exp, String specialization) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (exp.isNotEmpty) Text('Experience: $exp'),
            if (specialization.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Specialization: $specialization'),
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
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        body: buildContent(name, exp, specialization),
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

        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: snap.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : buildContent(name, exp, specialization),
        );
      },
    );
  }
}
