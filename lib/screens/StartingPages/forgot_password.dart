import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtr = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  DateTime? _lastSentAt;

  @override
  void dispose() {
    _emailCtr.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!v.contains('@')) return 'Invalid email';
    return null;
  }

  bool get _cooldownActive {
    if (_lastSentAt == null) return false;
    return DateTime.now().difference(_lastSentAt!).inSeconds < 30;
  }

  Future<void> _sendResetEmail() async {
    final email = _emailCtr.text.trim();
    if (_validateEmail(email) != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }
    if (_cooldownActive) {
      if (!mounted) return;
      final remaining = 30 - DateTime.now().difference(_lastSentAt!).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please wait ${remaining}s before resending')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _lastSentAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'Failed to send reset email';
      if (e.code == 'invalid-email') msg = 'Invalid email address';
      if (e.code == 'user-not-found') msg = 'No user found for that email';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Enter your account email'),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _sending ? null : _sendResetEmail,
                  child: Text(_sending ? 'Sending...' : 'Send reset email'),
                ),
                if (_sent) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'We\'ve sent a password reset link to your email. Tap the link to set a new password.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _cooldownActive || _sending
                            ? null
                            : _sendResetEmail,
                        child: Text(
                          _cooldownActive ? 'Resend (wait...)' : 'Resend',
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to login'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
