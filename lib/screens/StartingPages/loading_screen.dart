import 'dart:async';

import 'package:flutter/material.dart';
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
    // Show for 5 seconds then go to login
    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
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
                children: const [
                  FlutterLogo(size: 96),
                  SizedBox(height: 16),
                  Text(
                    'Welcome to Hair House Salon',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
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
