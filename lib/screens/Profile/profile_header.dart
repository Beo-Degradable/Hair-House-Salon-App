import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

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
  // Avatar change disabled — keep read-only display only.

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
        final remoteVersion = data != null
            ? (data['avatarVersion'] as int?) ?? 0
            : 0;
        final localVersion = prefs.getInt('avatar_version') ?? 0;
        if (b64 != null && b64.isNotEmpty) {
          if (mounted) setState(() => _avatarB64 = b64);
          // If remote version is newer or we don't have a stable local file, cache the bytes locally
          if (remoteVersion > localVersion || (path == null || path.isEmpty)) {
            try {
              final bytes = base64Decode(b64);
              final cachedPath = await _cacheAvatarBytes(bytes);
              if (cachedPath != null) {
                await prefs.setString('avatar_path', cachedPath);
                if (mounted) setState(() => _avatarPath = cachedPath);
              }
              await prefs.setInt('avatar_version', remoteVersion);
            } catch (_) {
              // ignore cache errors
            }
          }
        }
      } catch (_) {
        // ignore
      }
    }
  }

  Future<String?> _cacheAvatarBytes(Uint8List bytes) async {
    if (kIsWeb) return null; // no file cache path on web here
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/avatar_cached.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // Avatar change UI and handlers removed — avatar is read-only from here.

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
    return CircleAvatar(
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
        ],
      ),
    );
  }
}
