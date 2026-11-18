import 'package:flutter/material.dart';

/// Spotmate's conversation mark: two overlapping speech bubbles and a spark.
/// Kept as a widget so the mark scales crisply on web, Android and iOS.
class HeartPinLogo extends StatelessWidget {
  final double size;
  const HeartPinLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SpotmateMarkPainter()),
    );
  }
}

class _SpotmateMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    // Ink-blue backing bubble with a lower-left conversation tail.
    final back = Path()
      ..moveTo(16, 21)
      ..quadraticBezierTo(16, 10, 28, 10)
      ..lineTo(63, 10)
      ..quadraticBezierTo(76, 10, 76, 23)
      ..lineTo(76, 53)
      ..quadraticBezierTo(76, 66, 63, 66)
      ..lineTo(36, 66)
      ..lineTo(20, 80)
      ..lineTo(23, 64)
      ..quadraticBezierTo(16, 61, 16, 51)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF162544));

    // Mint foreground bubble builds the distinct S-like conversation silhouette.
    final front = Path()
      ..moveTo(40, 38)
      ..quadraticBezierTo(40, 28, 51, 28)
      ..lineTo(78, 28)
      ..quadraticBezierTo(89, 28, 89, 40)
      ..lineTo(89, 66)
      ..quadraticBezierTo(89, 77, 77, 77)
      ..lineTo(70, 77)
      ..lineTo(79, 90)
      ..lineTo(57, 77)
      ..lineTo(51, 77)
      ..quadraticBezierTo(40, 77, 40, 66)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF35D6B4));

    // A minimal three-point conversation indicator.
    final dots = Paint()..color = const Color(0xFF162544);
    for (final x in [54.0, 65.0, 76.0]) {
      canvas.drawCircle(Offset(x, 54), 2.8, dots);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
