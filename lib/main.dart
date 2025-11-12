import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

import 'screens/StartingPages/splash_intro.dart';
import 'screens/StartingPages/loading_screen.dart';
import 'screens/StartingPages/login_screen.dart';
import 'screens/HomePage/home_page.dart';
import 'screens/ServicesPage/services_page.dart';
import 'screens/Products/products_page.dart';
import 'screens/Profile/profile_page.dart';
import 'widgets/custom_bottom_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase (Android + Web configured). Other platforms throw by design.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // If unsupported platform (e.g. Windows without config) just log; app can still run limited features.
    debugPrint('Firebase init skipped/failed: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getBool('splash_seen') ?? false;
  runApp(MyApp(showIntro: !seen));
}

class MyApp extends StatelessWidget {
  final bool showIntro;
  const MyApp({super.key, required this.showIntro});

  @override
  Widget build(BuildContext context) {
    // Dark palette: black background, dark grey surfaces, white text, dark gold accents
    final black = const Color(0xFF000000);
    final darkGrey = const Color(0xFF1E1E1E);
    final darkGold = const Color(0xFFB8860B);

    // Precache the logo once at app start (first build of root widget) to avoid missing frame
    // This is safe; subsequent calls are cached. Helps confirm asset availability early.
    precacheImage(
      const AssetImage('assets/LogoH.png'),
      context,
      onError: (error, stack) {
        debugPrint('LogoH.png failed to precache: $error');
      },
    );

    return MaterialApp(
      title: 'Hair House Salon',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: black,
        canvasColor: darkGrey,
        cardColor: darkGrey,
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          primary: darkGold,
          onPrimary: Colors.white,
          surface: darkGrey,
          onSurface: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: darkGrey,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkGold,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(backgroundColor: darkGrey),
      ),
      home: showIntro ? const SplashIntroPage() : const LoadingScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => CustomBottomNavScaffold(
          pages: const [
            HomePage(),
            ServicesPage(),
            ProductsPage(),
            ProfilePage(),
          ],
        ),
      },
    );
  }
}
