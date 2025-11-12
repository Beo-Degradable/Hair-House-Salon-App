import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/bubble_background.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Precache logo to avoid first-frame missing icon on web/hot reload
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/LogoH.png'), context);
    });
    // Decide destination based on stay_logged_in and is_logged_in, and a valid Firebase user
    Future<String> _decideRoute() async {
      final prefs = await SharedPreferences.getInstance();
      final stay = prefs.getBool('stay_logged_in') ?? false;
      final isLogged = prefs.getBool('is_logged_in') ?? false;
      final user = FirebaseAuth.instance.currentUser;
      if (stay && isLogged && user != null) return '/home';
      return '/login';
    }

    _timer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      final route = await _decideRoute();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: BubbleBackground(
              bubbleColor: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(0.04),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/LogoH.png',
                    width: 128,
                    height: 128,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) {
                      debugPrint(
                        'LoadingScreen: failed to load LogoH.png -> $err',
                      );
                      return const Icon(Icons.image_not_supported, size: 48);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Welcome to Hair House Salon',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '"Where style meets comfort."',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
