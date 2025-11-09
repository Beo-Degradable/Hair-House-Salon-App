import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileHeader extends StatefulWidget {
  final String name;
  final String email;

  const ProfileHeader({super.key, required this.name, required this.email});

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  static const Color _darkGold = Color(0xFFB8860B);
  String? _avatarPath; // Local file path
  String? _avatarB64; // Firestore-backed base64 image
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('avatar_path');
    if (mounted) setState(() => _avatarPath = path);

    // Try to load from Firestore if signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = snap.data();
        final b64 = data != null ? (data['avatarB64'] as String?) : null;
        if (b64 != null && b64.isNotEmpty) {
          if (mounted) setState(() => _avatarB64 = b64);
        }
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> _changeAvatar() async {
    setState(() => _loading = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        imageQuality: 85,
      );
      if (picked != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('avatar_path', picked.path);
        // Read bytes and store base64 to Firestore if signed in
        final bytes = await picked.readAsBytes();
        final b64 = base64Encode(bytes);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'avatarB64': b64,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          } catch (_) {}
        }
        if (!mounted) return;
        setState(() {
          _avatarPath = picked.path;
          _avatarB64 = b64;
        });
        Navigator.of(context).pop(); // Close dialog after picking
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAvatarDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current Avatar', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                _buildAvatar(radius: 60),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Change Avatar'),
                    onPressed: _loading ? null : _changeAvatar,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar({double radius = 28}) {
    final cs = Theme.of(context).colorScheme;
    ImageProvider? imageProvider;
    if (_avatarB64 != null && _avatarB64!.isNotEmpty) {
      try {
        final bytes = base64Decode(_avatarB64!);
        imageProvider = MemoryImage(bytes);
      } catch (_) {
        imageProvider = null;
      }
    } else if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      if (kIsWeb) {
        // On web, FileImage isn't supported directly; would need bytes. Skip for now.
        imageProvider = null; // Fallback to initials
      } else {
        final file = File(_avatarPath!);
        if (file.existsSync()) {
          imageProvider = FileImage(file);
        }
      }
    }
    return InkWell(
      onTap: _showAvatarDialog,
      borderRadius: BorderRadius.circular(radius),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: cs.surface,
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _darkGold, width: 2),
      ),
      child: Row(
        children: [
          _buildAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.email.isNotEmpty ? widget.email : 'No email set',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Change avatar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _showAvatarDialog,
          ),
        ],
      ),
    );
  }
}
