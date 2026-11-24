import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Tactile 3D-shaded tumbling die used across Snakes & Ladders V3 and Ludo V3.
class Dice3DWidget extends StatefulWidget {
  const Dice3DWidget({
    super.key,
    required this.value,
    required this.rolling,
    this.isGoldenSkin = false,
    this.size = 58,
  });

  final int value;
  final bool rolling;
  final bool isGoldenSkin;
  final double size;

  @override
  State<Dice3DWidget> createState() => _Dice3DWidgetState();
}

class _Dice3DWidgetState extends State<Dice3DWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  int _displayFace = 1;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _displayFace = widget.value.clamp(1, 6);
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
      ..addListener(() {
        if (_anim.isAnimating && _anim.value < 0.85) {
          setState(() => _displayFace = 1 + _rng.nextInt(6));
        } else if (_displayFace != widget.value) {
          setState(() => _displayFace = widget.value.clamp(1, 6));
        }
      });
  }

  @override
  void didUpdateWidget(covariant Dice3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.rolling && !oldWidget.rolling) || widget.value != oldWidget.value) {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final t = _anim.value;
        final angle = t * math.pi * 2;
        final bounce = math.sin(t * math.pi) * 10;
        final scale = 1.0 + math.sin(t * math.pi) * 0.14;
        return Transform.translate(
          offset: Offset(0, -bounce),
          child: Transform.rotate(
            angle: _anim.isAnimating ? angle : 0,
            child: Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _Die3DPainter(
                  face: _anim.isAnimating ? _displayFace : widget.value.clamp(1, 6),
                  isGolden: widget.isGoldenSkin,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Die3DPainter extends CustomPainter {
  _Die3DPainter({required this.face, required this.isGolden});

  final int face;
  final bool isGolden;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(size.width * 0.22));

    // Soft drop shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x380F172A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 3D beveled die body gradient
    final bodyGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isGolden
          ? [const Color(0xFFFEF08A), const Color(0xFFF59E0B), const Color(0xFFB45309)]
          : [const Color(0xFFFFFFFF), const Color(0xFFF8F5EC), const Color(0xFFE2DDD0)],
    );
    canvas.drawRRect(rrect, Paint()..shader = bodyGrad.createShader(rect));

    // Rim highlight
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = isGolden ? const Color(0xFF92400E) : const Color(0xFFCBD5E1),
    );

    // Pips
    final pipPaint = Paint()
      ..color = isGolden
          ? const Color(0xFF451A03)
          : (face == 1 || face == 6 ? const Color(0xFFDC2626) : const Color(0xFF0F172A));
    final r = size.width * 0.088;
    const c = 0.5;
    const lo = 0.27;
    const hi = 0.73;

    final Map<int, List<Offset>> pipMap = {
      1: [const Offset(c, c)],
      2: [const Offset(lo, lo), const Offset(hi, hi)],
      3: [const Offset(lo, lo), const Offset(c, c), const Offset(hi, hi)],
      4: [const Offset(lo, lo), const Offset(hi, lo), const Offset(lo, hi), const Offset(hi, hi)],
      5: [const Offset(lo, lo), const Offset(hi, lo), const Offset(c, c), const Offset(lo, hi), const Offset(hi, hi)],
      6: [
        const Offset(lo, lo),
        const Offset(hi, lo),
        const Offset(lo, c),
        const Offset(hi, c),
        const Offset(lo, hi),
        const Offset(hi, hi),
      ],
    };

    for (final pt in pipMap[face] ?? pipMap[1]!) {
      canvas.drawCircle(Offset(pt.dx * size.width, pt.dy * size.height), r, pipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Die3DPainter old) => old.face != face || old.isGolden != isGolden;
}
