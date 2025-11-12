import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class BubbleBackground extends StatefulWidget {
  final int maxBubbles;
  final Color bubbleColor;
  const BubbleBackground({
    super.key,
    this.maxBubbles = 20,
    required this.bubbleColor,
  });

  @override
  State<BubbleBackground> createState() => _BubbleBackgroundState();
}

class _BubbleBackgroundState extends State<BubbleBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Bubble> _bubbles = [];
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = 1 / 60; // approx frame sec
    // update bubbles
    for (final b in List<_Bubble>.from(_bubbles)) {
      b.age += dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      // remove when lifetime exceeded
      if (b.age >= b.lifetime) _bubbles.remove(b);
    }

    // spawn new bubbles randomly until max
    if (_bubbles.length < widget.maxBubbles && _rnd.nextDouble() < 0.04) {
      _bubbles.add(_createBubble());
    }

    setState(() {});
  }

  _Bubble _createBubble() {
    final size = 8 + _rnd.nextDouble() * 36; // radius
    final lifetime = 3 + _rnd.nextDouble() * 6; // seconds
    // spawn at random edge
    final spawnEdge = _rnd.nextInt(4);
    double x = 0.5, y = 0.5, vx = 0, vy = 0;
    final speed = 10 + _rnd.nextDouble() * 40;
    switch (spawnEdge) {
      case 0: // left
        x = -0.1;
        y = _rnd.nextDouble();
        vx = 0.02 + _rnd.nextDouble() * 0.2;
        vy = -0.08 + _rnd.nextDouble() * 0.16;
        break;
      case 1: // right
        x = 1.1;
        y = _rnd.nextDouble();
        vx = -0.02 - _rnd.nextDouble() * 0.2;
        vy = -0.08 + _rnd.nextDouble() * 0.16;
        break;
      case 2: // top
        x = _rnd.nextDouble();
        y = -0.1;
        vx = -0.08 + _rnd.nextDouble() * 0.16;
        vy = 0.02 + _rnd.nextDouble() * 0.2;
        break;
      default: // bottom
        x = _rnd.nextDouble();
        y = 1.1;
        vx = -0.08 + _rnd.nextDouble() * 0.16;
        vy = -0.02 - _rnd.nextDouble() * 0.2;
        break;
    }

    // scale velocities by speed
    vx *= speed / 60;
    vy *= speed / 60;

    // color palette: white, dark gold, gold
    final palette = [
      Colors.white,
      const Color(0xFFB8860B), // dark goldenrod
      const Color(0xFFD4AF37), // gold
    ];
    final color = palette[_rnd.nextInt(palette.length)];
    // softer opacity range so bubbles are subtle
    final alpha = 0.04 + _rnd.nextDouble() * 0.08;

    return _Bubble(
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      radius: size,
      lifetime: lifetime,
      age: 0,
      alpha: alpha,
      color: color,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(List<_Bubble>.from(_bubbles), widget.bubbleColor),
      size: Size.infinite,
    );
  }
}

class _Bubble {
  double x; // 0..1 relative
  double y;
  double vx;
  double vy;
  double radius;
  double lifetime;
  double age;
  double alpha;
  Color color;
  _Bubble({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.lifetime,
    required this.age,
    required this.alpha,
    required this.color,
  });
}

class _BubblePainter extends CustomPainter {
  final List<_Bubble> bubbles;
  final Color color;
  _BubblePainter(this.bubbles, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final b in bubbles) {
      final cx = b.x * size.width;
      final cy = b.y * size.height;
      final progress = (b.age / b.lifetime).clamp(0.0, 1.0);
      final alpha = (1.0 - progress) * b.alpha;
      paint.color = b.color.withOpacity(alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(cx, cy), b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) => true;
}
