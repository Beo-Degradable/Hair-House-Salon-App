import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hxhmobile/screens/Profile/history_page.dart';

class MyAccountPage extends StatefulWidget {
  const MyAccountPage({super.key});

  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

enum _AccountSection { overview, changePassword, changeEmail, connect }

class _MyAccountPageState extends State<MyAccountPage> {
  // Profile
  String _name = 'Guest';
  String _email = '';
  bool _isLoggedIn = false;
  String? _avatarBase64; // simple persisted avatar image as base64 (PNG/JPEG)

  // Section switching
  _AccountSection _section = _AccountSection.overview;

  // Forms
  final _pwdFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _currentPwdCtr = TextEditingController();
  final _newPwdCtr = TextEditingController();
  final _confirmPwdCtr = TextEditingController();
  final _newEmailCtr = TextEditingController();
  final _emailChangePwdCtr = TextEditingController();

  // Connect states (simulation)
  bool _connectedFacebook = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _currentPwdCtr.dispose();
    _newPwdCtr.dispose();
    _confirmPwdCtr.dispose();
    _newEmailCtr.dispose();
    _emailChangePwdCtr.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    _isLoggedIn = user != null || (prefs.getBool('is_logged_in') ?? false);

    // Local fallback values
    String? localName =
        prefs.getString('display_name') ??
        prefs.getString('full_name') ??
        prefs.getString('name');
    if (localName == null || localName.trim().isEmpty) {
      final first = prefs.getString('first_name');
      final last = prefs.getString('last_name');
      if (first != null && first.isNotEmpty) {
        localName = (last != null && last.isNotEmpty) ? '$first $last' : first;
      }
    }
    if (localName == null || localName.trim().isEmpty) {
      final em = prefs.getString('email');
      if (em != null && em.isNotEmpty) {
        localName = em.split('@')[0];
      }
    }
    String localEmail = prefs.getString('email') ?? '';
    String? localAvatar = prefs.getString('avatar_b64');
    bool localFacebook = prefs.getBool('connected_facebook') ?? false;

    if (user == null) {
      // Not signed in: fallback to local only
      _name = localName?.trim().isNotEmpty == true
          ? localName!.trim()
          : 'Guest';
      _email = localEmail;
      _avatarBase64 = localAvatar;
      _connectedFacebook = localFacebook;
      if (mounted) setState(() {});
      return;
    }

    // Signed in: load Firestore user profile (create if missing)
    final users = FirebaseFirestore.instance.collection('users');
    final docRef = users.doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      // Seed document with best-known values
      await docRef.set({
        'name': (localName?.trim().isNotEmpty == true)
            ? localName!.trim()
            : (user.displayName ?? (user.email?.split('@').first ?? 'Guest')),
        'email': user.email ?? localEmail,
        'avatarB64': localAvatar ?? '',
        'connected_facebook': localFacebook,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    final data = (await docRef.get()).data() ?? {};
    _name = (data['name'] ?? localName ?? 'Guest').toString();
    _email = (data['email'] ?? user.email ?? localEmail).toString();
    _avatarBase64 = (data['avatarB64'] ?? localAvatar ?? '').toString();
    _connectedFacebook = (data['connected_facebook'] ?? localFacebook) == true;

    // Optionally update local cache for faster future loads
    await prefs.setString('display_name', _name);
    await prefs.setString('email', _email);
    await prefs.setString('avatar_b64', _avatarBase64 ?? '');
    await prefs.setBool('connected_facebook', _connectedFacebook);

    if (mounted) setState(() {});
  }

  Future<void> _saveAvatarBase64(String? b64) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (b64 == null) {
      await prefs.remove('avatar_b64');
    } else {
      await prefs.setString('avatar_b64', b64);
    }
    setState(() => _avatarBase64 = b64);
    // Persist to Firestore if signed in
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'avatarB64': b64 ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // For this version, allow user to paste a direct image URL or a base64 string.
  // On mobile, integrating camera/gallery requires extra setup; this keeps it simple
  // yet functional.
  Future<void> _changeAvatarDialog() async {
    final urlCtr = TextEditingController();
    final b64Ctr = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change avatar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Paste image URL (jpg/png):'),
              TextField(
                controller: urlCtr,
                decoration: const InputDecoration(hintText: 'https://...'),
              ),
              const SizedBox(height: 8),
              const Text('or paste Base64 data (data:image/...;base64,...)'),
              TextField(controller: b64Ctr, maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Prefer base64 if provided; fall back to fetching URL bytes (skipped for now).
              final s = b64Ctr.text.trim();
              if (s.isNotEmpty) {
                await _saveAvatarBase64(_stripDataPrefix(s));
              } else if (urlCtr.text.trim().isNotEmpty) {
                // Store URL string base64-encoded marker to render via NetworkImage.
                // We prefix with url: so the renderer knows how to load it.
                final encoded = base64Encode(
                  utf8.encode('url:${urlCtr.text.trim()}'),
                );
                await _saveAvatarBase64(encoded);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: () async {
              await _saveAvatarBase64(null);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String _stripDataPrefix(String s) {
    final i = s.indexOf(',');
    return i >= 0 ? s.substring(i + 1) : s;
  }

  ImageProvider? _avatarImageProvider() {
    if (_avatarBase64 == null || _avatarBase64!.isEmpty) return null;
    try {
      // If this is a special url: marker, decode and use NetworkImage
      final decoded = utf8.decode(base64Decode(_avatarBase64!));
      if (decoded.startsWith('url:')) {
        return NetworkImage(decoded.substring(4));
      }
    } catch (_) {
      // not a url marker; treat as raw base64
    }
    try {
      final bytes = base64Decode(_avatarBase64!);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<UserCredential> _reauthenticate(String email, String password) {
    final cred = EmailAuthProvider.credential(email: email, password: password);
    return FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(
      cred,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = _avatarImageProvider();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFB8860B), width: 2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: avatar,
                child: avatar == null
                    ? Text(
                        _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _email.isNotEmpty ? _email : 'No email set',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _changeAvatarDialog,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Change avatar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!_isLoggedIn)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Sign in first to manage your account.'),
                ),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sign-in flow coming soon')),
                    );
                  },
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOverview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(child: Text('Name: $_name')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.email_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Email: ${_email.isNotEmpty ? _email : '—'}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.history),
              const SizedBox(width: 8),
              Expanded(child: const Text('History items')),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                  );
                },
                child: const Text('View'),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isLoggedIn
                    ? () => setState(
                        () => _section = _AccountSection.changePassword,
                      )
                    : null,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Change password'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoggedIn
                    ? () =>
                          setState(() => _section = _AccountSection.changeEmail)
                    : null,
                icon: const Icon(Icons.alternate_email),
                label: const Text('Change email'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _section = _AccountSection.connect),
                icon: const Icon(Icons.link),
                label: const Text('Connect services'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChangePassword(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Form(
        key: _pwdFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change password',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _currentPwdCtr,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPwdCtr,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'At least 6 characters' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPwdCtr,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (v) =>
                  v != _newPwdCtr.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                if (!(_pwdFormKey.currentState?.validate() ?? false)) return;
                final user = FirebaseAuth.instance.currentUser;
                if (user == null || user.email == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not signed in')),
                  );
                  return;
                }
                try {
                  await _reauthenticate(
                    user.email!,
                    _currentPwdCtr.text.trim(),
                  );
                  await user.updatePassword(_newPwdCtr.text.trim());
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                  if (!mounted) return;
                  setState(() {
                    _currentPwdCtr.clear();
                    _newPwdCtr.clear();
                    _confirmPwdCtr.clear();
                    _section = _AccountSection.overview;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated')),
                  );
                } on FirebaseAuthException catch (e) {
                  String msg = 'Failed to update password';
                  if (e.code == 'wrong-password')
                    msg = 'Current password incorrect';
                  if (e.code == 'weak-password') msg = 'Weak password';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error updating password')),
                  );
                }
              },
              child: const Text('Update password'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  setState(() => _section = _AccountSection.overview),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeEmail(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Form(
        key: _emailFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change email',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newEmailCtr,
              decoration: const InputDecoration(labelText: 'New email'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@')) return 'Must contain @';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailChangePwdCtr,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                if (!(_emailFormKey.currentState?.validate() ?? false)) return;
                final user = FirebaseAuth.instance.currentUser;
                if (user == null || user.email == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not signed in')),
                  );
                  return;
                }
                final newEmail = _newEmailCtr.text.trim();
                try {
                  await _reauthenticate(
                    user.email!,
                    _emailChangePwdCtr.text.trim(),
                  );
                  await user.verifyBeforeUpdateEmail(
                    newEmail,
                  ); // ensures email ownership
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                        'emailPending': newEmail,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                  if (!mounted) return;
                  setState(() {
                    _newEmailCtr.clear();
                    _emailChangePwdCtr.clear();
                    _section = _AccountSection.overview;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Verification link sent to new email'),
                    ),
                  );
                } on FirebaseAuthException catch (e) {
                  String msg = 'Failed to change email';
                  if (e.code == 'wrong-password')
                    msg = 'Current password incorrect';
                  if (e.code == 'email-already-in-use')
                    msg = 'Email already in use';
                  if (e.code == 'requires-recent-login')
                    msg = 'Please re-login and try again';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error changing email')),
                  );
                }
              },
              child: const Text('Send verification link'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  setState(() => _section = _AccountSection.overview),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnect(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect services (optional)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _connectedFacebook,
            onChanged: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('connected_facebook', v);
              setState(() => _connectedFacebook = v);
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({
                      'connected_facebook': v,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
              }
            },
            title: const Text('Facebook'),
            subtitle: Text(_connectedFacebook ? 'Connected' : 'Not connected'),
            secondary: const Icon(Icons.facebook),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                setState(() => _section = _AccountSection.overview),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          // Info / Actions container that swaps to selected function
          if (_section == _AccountSection.overview)
            _buildOverview(context)
          else if (_section == _AccountSection.changePassword)
            _buildChangePassword(context)
          else if (_section == _AccountSection.changeEmail)
            _buildChangeEmail(context)
          else
            _buildConnect(context),
        ],
      ),
    );
  }
}
