import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hxhmobile/screens/StartingPages/forgot_password.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/bubble_background.dart';
import '../../services/auth_service.dart';
import 'forgot_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _stayLoggedIn = true;

  String _passwordStrengthLabel = '';
  Color _passwordStrengthColor = Colors.red;

  final _emailAllowed = RegExp(r'^[A-Za-z0-9@.]+$');
  final _nameAllowed = RegExp(r'^[A-Za-z\s]+$');
  final _passwordAllowed = RegExp(r'^[A-Za-z0-9]+$');

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
      _passwordStrengthLabel = '';
    });
  }

  void _onPasswordChanged(String value) {
    final strength = _computePasswordStrength(value);
    setState(() {
      if (value.isEmpty) {
        _passwordStrengthLabel = '';
      } else if (strength >= 3) {
        _passwordStrengthLabel = 'Strong';
        _passwordStrengthColor = Colors.green;
      } else if (strength == 2) {
        _passwordStrengthLabel = 'Medium';
        _passwordStrengthColor = Colors.orange;
      } else {
        _passwordStrengthLabel = 'Weak';
        _passwordStrengthColor = Colors.red;
      }
    });
  }

  int _computePasswordStrength(String s) {
    var score = 0;
    if (s.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(s)) score++;
    if (RegExp(r'[0-9]').hasMatch(s)) score++;
    return score;
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!_nameAllowed.hasMatch(v.trim()))
      return 'Only letters and spaces allowed';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final s = v.trim();
    if (!s.contains('@')) return 'Must contain @';
    if (!_emailAllowed.hasMatch(s)) return 'Invalid characters in email';
    final parts = s.split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty)
      return 'Invalid email format';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    if (!_passwordAllowed.hasMatch(v))
      return 'Only letters and numbers allowed';
    if (_isLogin) {
      if (v.length < 6) return 'Password too short';
    } else {
      if (_computePasswordStrength(v) < 3) return 'Password not strong enough';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (!_isLogin) {
      if (v == null || v.isEmpty) return 'Required';
      if (v != _passwordController.text) return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();

    try {
      if (_isLogin) {
        await AuthService.instance.signIn(email: email, password: password);
      } else {
        await AuthService.instance.register(
          firstName: first,
          lastName: last,
          email: email,
          password: password,
        );
      }

      final profile = await AuthService.instance.fetchProfile();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', _stayLoggedIn);
      await prefs.setBool('stay_logged_in', _stayLoggedIn);
      await prefs.setString('email', email);
      if (profile != null) {
        final name = (profile['name'] as String?)?.trim();
        final firstName = (profile['first_name'] as String?)?.trim();
        final lastName = (profile['last_name'] as String?)?.trim();
        final role = (profile['role'] as String?)?.trim() ?? 'users';
        if (name != null && name.isNotEmpty) {
          await prefs.setString('display_name', name);
        }
        if (firstName != null && firstName.isNotEmpty) {
          await prefs.setString('first_name', firstName);
        }
        if (lastName != null && lastName.isNotEmpty) {
          await prefs.setString('last_name', lastName);
        }
        await prefs.setString('role', role);
      } else {
        await prefs.setString('role', 'users');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isLogin ? 'Logged in' : 'Registered')),
      );
      Navigator.of(context).pushReplacementNamed('/home');
    } on PlatformException catch (e) {
      _showError(e.message ?? 'Platform error');
    } on Exception catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    precacheImage(const AssetImage('assets/LogoH.png'), context);
    // Load stay logged in preference once (lazy init) if controllers are fresh
    // This avoids async in initState rework; inexpensive read each build with guard.
    if (_formKey.currentState == null) {
      SharedPreferences.getInstance().then((prefs) {
        final stay = prefs.getBool('stay_logged_in');
        if (stay != null && stay != _stayLoggedIn && mounted) {
          setState(() => _stayLoggedIn = stay);
        }
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: BubbleBackground(
              bubbleColor: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(0.03),
            ),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  height: height * 0.25,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/LogoH.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, err, stack) {
                            debugPrint(
                              'LoginScreen: failed to load LogoH.png -> $err',
                            );
                            return const Icon(
                              Icons.image_not_supported,
                              size: 48,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isLogin ? 'Welcome Back' : 'Create an account',
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Welcome to Hair House Salon',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Card(
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.12),
                          ),
                        ),
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14.0,
                            horizontal: 16.0,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (!_isLogin) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _firstNameController,
                                          decoration: const InputDecoration(
                                            labelText: 'First name',
                                          ),
                                          validator: _validateName,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[A-Za-z\s]'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _lastNameController,
                                          decoration: const InputDecoration(
                                            labelText: 'Last name',
                                          ),
                                          validator: _validateName,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[A-Za-z\s]'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                  validator: _validateEmail,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9@.]'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                                  onChanged: _onPasswordChanged,
                                  validator: _validatePassword,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9]'),
                                    ),
                                  ],
                                ),
                                if (!_isLogin) ...[
                                  const SizedBox(height: 8),
                                  if (_passwordStrengthLabel.isNotEmpty)
                                    Row(
                                      children: [
                                        Text(
                                          'Strength: ',
                                          style: TextStyle(
                                            color: _passwordStrengthColor,
                                          ),
                                        ),
                                        Text(
                                          _passwordStrengthLabel,
                                          style: TextStyle(
                                            color: _passwordStrengthColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _confirmController,
                                    obscureText: _obscureConfirm,
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirm
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscureConfirm =
                                              !_obscureConfirm,
                                        ),
                                      ),
                                    ),
                                    validator: _validateConfirm,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _stayLoggedIn,
                                        onChanged: (v) => setState(
                                          () => _stayLoggedIn = v ?? true,
                                        ),
                                      ),
                                      const Text('Stay logged in'),
                                    ],
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  // Login mode: stay logged in + forgot password in one row
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _stayLoggedIn,
                                        onChanged: (v) => setState(
                                          () => _stayLoggedIn = v ?? true,
                                        ),
                                      ),
                                      const Text('Stay logged in'),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ForgotPasswordPage(),
                                            ),
                                          );
                                        },
                                        child: const Text('Forgot password?'),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 16),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _onSubmit,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12.0,
                                      ),
                                      child: Text(
                                        _isLogin ? 'Login' : 'Register',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin
                          ? "Don't have an account? "
                          : 'Already have an account? ',
                    ),
                    GestureDetector(
                      onTap: _toggleMode,
                      child: Text(
                        _isLogin ? 'Sign up' : 'Sign in',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
