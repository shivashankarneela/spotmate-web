import 'package:flutter/material.dart';

/// Custom-painted 3D-shaded Staunton Chess Pieces (King, Queen, Rook, Bishop, Knight, Pawn).
/// Replaces flat Unicode font glyphs with crisp tournament silhouettes and specular highlights.
class StauntonPieceWidget extends StatelessWidget {
  const StauntonPieceWidget({
    super.key,
    required this.pieceCode, // 'wK','wQ','wR','wB','wN','wP','bK','bQ','bR','bB','bN','bP'
    this.skin = 'chess_ivory',
    this.size = 42,
  });

  final String pieceCode;
  final String skin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StauntonPainter(pieceCode: pieceCode, skin: skin),
    );
  }
}

class _StauntonPainter extends CustomPainter {
  _StauntonPainter({required this.pieceCode, required this.skin});

  final String pieceCode;
  final String skin;

  @override
  void paint(Canvas canvas, Size size) {
    if (pieceCode.length < 2) return;
    final isWhite = pieceCode[0] == 'w';
    final kind = pieceCode[1].toUpperCase();
    final w = size.width;
    final h = size.height;

    final List<Color> fillColors;
    final Color strokeColor;
    final Color collarColor;

    if (isWhite) {
      if (skin == 'chess_marble') {
        fillColors = [const Color(0xFFFFFFFF), const Color(0xFFE2E8F0), const Color(0xFF94A3B8)];
        strokeColor = const Color(0xFF334155);
        collarColor = const Color(0xFF64748B);
      } else {
        fillColors = [const Color(0xFFFFFDF7), const Color(0xFFF5E6C8), const Color(0xFFD6BE96)];
        strokeColor = const Color(0xFF451A03);
        collarColor = const Color(0xFFD97706);
      }
    } else {
      if (skin == 'chess_emerald') {
        fillColors = [const Color(0xFF10B981), const Color(0xFF065F46), const Color(0xFF022C22)];
        strokeColor = const Color(0xFFFDE047);
        collarColor = const Color(0xFFF59E0B);
      } else {
        fillColors = [const Color(0xFF475569), const Color(0xFF1E293B), const Color(0xFF090D16)];
        strokeColor = const Color(0xFFCBD5E1);
        collarColor = const Color(0xFFF59E0B);
      }
    }

    final path = _buildSilhouette(kind, w, h);

    // Drop shadow
    canvas.drawPath(
      path.shift(Offset(0, h * 0.04)),
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // 3D sculpted gradient fill
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fillColors,
        ).createShader(Offset.zero & size),
    );

    // Crisp outline
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.042
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor,
    );

    // Gold/metallic collar accent band near base
    canvas.drawLine(
      Offset(w * 0.25, h * 0.78),
      Offset(w * 0.75, h * 0.78),
      Paint()
        ..color = collarColor
        ..strokeWidth = h * 0.045
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _buildSilhouette(String kind, double w, double h) {
    final p = Path();
    // Shared pedestal base (0.80..0.90)
    void addPedestal() {
      p.moveTo(w * 0.18, h * 0.90);
      p.lineTo(w * 0.82, h * 0.90);
      p.lineTo(w * 0.78, h * 0.78);
      p.lineTo(w * 0.22, h * 0.78);
      p.close();
    }

    switch (kind) {
      case 'P': // Pawn
        addPedestal();
        p.moveTo(w * 0.28, h * 0.78);
        p.quadraticBezierTo(w * 0.36, h * 0.56, w * 0.40, h * 0.48);
        p.lineTo(w * 0.60, h * 0.48);
        p.quadraticBezierTo(w * 0.64, h * 0.56, w * 0.72, h * 0.78);
        p.close();
        p.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.34), radius: w * 0.17));
        return p;

      case 'R': // Rook (Crenelated Turret)
        addPedestal();
        p.moveTo(w * 0.27, h * 0.78);
        p.lineTo(w * 0.31, h * 0.36);
        p.lineTo(w * 0.24, h * 0.30);
        p.lineTo(w * 0.24, h * 0.16);
        p.lineTo(w * 0.36, h * 0.16);
        p.lineTo(w * 0.36, h * 0.24);
        p.lineTo(w * 0.44, h * 0.24);
        p.lineTo(w * 0.44, h * 0.16);
        p.lineTo(w * 0.56, h * 0.16);
        p.lineTo(w * 0.56, h * 0.24);
        p.lineTo(w * 0.64, h * 0.24);
        p.lineTo(w * 0.64, h * 0.16);
        p.lineTo(w * 0.76, h * 0.16);
        p.lineTo(w * 0.76, h * 0.30);
        p.lineTo(w * 0.69, h * 0.36);
        p.lineTo(w * 0.73, h * 0.78);
        p.close();
        return p;

      case 'N': // Knight (Sculpted Horse Head & Mane)
        addPedestal();
        p.moveTo(w * 0.28, h * 0.78);
        p.quadraticBezierTo(w * 0.26, h * 0.56, w * 0.36, h * 0.44);
        p.lineTo(w * 0.22, h * 0.46);
        p.lineTo(w * 0.18, h * 0.36);
        p.lineTo(w * 0.36, h * 0.20);
        p.lineTo(w * 0.42, h * 0.12); // Ear
        p.lineTo(w * 0.52, h * 0.18);
        p.quadraticBezierTo(w * 0.78, h * 0.24, w * 0.74, h * 0.78);
        p.close();
        return p;

      case 'B': // Bishop (Miter & Finial)
        addPedestal();
        p.moveTo(w * 0.28, h * 0.78);
        p.quadraticBezierTo(w * 0.30, h * 0.46, w * 0.38, h * 0.36);
        p.quadraticBezierTo(w * 0.32, h * 0.22, w * 0.50, h * 0.14);
        p.quadraticBezierTo(w * 0.68, h * 0.22, w * 0.62, h * 0.36);
        p.quadraticBezierTo(w * 0.70, h * 0.46, w * 0.72, h * 0.78);
        p.close();
        p.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.11), radius: w * 0.06));
        return p;

      case 'Q': // Queen (5-Point Coronet)
        addPedestal();
        p.moveTo(w * 0.26, h * 0.78);
        p.lineTo(w * 0.18, h * 0.26);
        p.lineTo(w * 0.34, h * 0.44);
        p.lineTo(w * 0.38, h * 0.18);
        p.lineTo(w * 0.50, h * 0.40);
        p.lineTo(w * 0.62, h * 0.18);
        p.lineTo(w * 0.66, h * 0.44);
        p.lineTo(w * 0.82, h * 0.26);
        p.lineTo(w * 0.74, h * 0.78);
        p.close();
        p.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.14), radius: w * 0.065));
        return p;

      case 'K': // King (Crown + Cross Finial)
      default:
        addPedestal();
        p.moveTo(w * 0.26, h * 0.78);
        p.lineTo(w * 0.22, h * 0.36);
        p.quadraticBezierTo(w * 0.36, h * 0.24, w * 0.50, h * 0.32);
        p.quadraticBezierTo(w * 0.64, h * 0.24, w * 0.78, h * 0.36);
        p.lineTo(w * 0.74, h * 0.78);
        p.close();
        // Cross finial
        p.addRect(Rect.fromCenter(center: Offset(w * 0.50, h * 0.16), width: w * 0.08, height: h * 0.20));
        p.addRect(Rect.fromCenter(center: Offset(w * 0.50, h * 0.13), width: w * 0.22, height: h * 0.06));
        return p;
    }
  }

  @override
  bool shouldRepaint(covariant _StauntonPainter old) => old.pieceCode != pieceCode || old.skin != skin;
}
