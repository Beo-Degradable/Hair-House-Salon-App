import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/bubble_background.dart';

class SplashIntroPage extends StatefulWidget {
  const SplashIntroPage({Key? key}) : super(key: key);

  @override
  State<SplashIntroPage> createState() => _SplashIntroPageState();
}

class _SplashIntroPageState extends State<SplashIntroPage> {
  final List<String> images = [
    'https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=1200',
    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=1200',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=1200',
  ];

  late final PageController _pageController;
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _timer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (!mounted) return;
      final next = (_current + 1) % images.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
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
            child: Column(
              children: [
                // Top container that covers slightly more than half of the screen with PageView carousel
                Container(
                  height: height * 0.55,
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surface,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (idx) => setState(() => _current = idx),
                    itemBuilder: (context, index) {
                      final url = images[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (c, e, st) => Container(
                            color: Theme.of(context).colorScheme.surface,
                            child: Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Page indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _current == i ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _current == i
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Below the container: Get Started button and text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const Text(
                        'Welcome to Hair House Salon',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Discover styles and expert stylists. Swipe the images above or wait for them to auto-play.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('splash_seen', true);
                            if (!mounted) return;
                            Navigator.of(
                              context,
                            ).pushReplacementNamed('/login');
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              'Get Started',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
