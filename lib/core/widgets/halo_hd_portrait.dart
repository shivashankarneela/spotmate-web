import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'halo_illustrated_avatar.dart';

/// HD face-and-shoulder crops from the approved 1024px transparent full-body
/// artworks. Values are (source x center, source top, square source width)
/// in the original 1024x1024 WebP coordinates. The original full-body files
/// remain unchanged for the lobby and posture animations.
class HaloHdPortrait extends StatelessWidget {
  const HaloHdPortrait({super.key, required this.avatarId, required this.size});
  final String avatarId;
  final double size;

  static const _framing = <String, (double, double, double)>{
    'boy_01': (512, 31, 280),
    'boy_02': (504, 22, 347),
    'boy_03': (524, 34, 239),
    'boy_04': (390, 70, 380),
    'boy_05': (512, 10, 350),
    'boy_06': (500, 26, 380),
    'boy_07': (538, 20, 341),
    'boy_08': (521, 43, 230),
    'boy_09': (514, 33, 280),
    'boy_10': (615, 42, 367),
    'girl_01': (492, 32, 278),
    'girl_02': (526, 51, 380),
    'girl_03': (519, 32, 380),
    'girl_04': (544, 32, 281),
    'girl_05': (540, 36, 380),
    'girl_06': (450, 34, 380),
    'girl_07': (575, 38, 380),
    'girl_08': (454, 17, 330),
    'girl_09': (523, 30, 380),
    'girl_10': (524, 64, 298),
  };

  static final Map<String, Future<ui.Image>> _images = {};

  static Future<ui.Image> _load(String path) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = HaloAvatarCatalog.characters[avatarId] ??
        HaloAvatarCatalog.characters['boy_01']!;
    final path = 'assets/avatars/default/${character.assetPrefix}.webp';
    final crop = _framing[avatarId] ?? _framing['boy_01']!;

    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: const Color(0xFFEAF4F1),
          child: FutureBuilder<ui.Image>(
            future: _images.putIfAbsent(path, () => _load(path)),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return CustomPaint(
                  painter: _HaloHdPortraitPainter(snapshot.data!, crop),
                  child: const SizedBox.expand(),
                );
              }
              if (snapshot.hasError) {
                return Icon(Icons.person_rounded,
                  size: size * .56, color: const Color(0xFF517C6E));
              }
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }
}

class _HaloHdPortraitPainter extends CustomPainter {
  const _HaloHdPortraitPainter(this.image, this.crop);
  final ui.Image image;
  final (double, double, double) crop;

  @override
  void paint(Canvas canvas, Size size) {
    final (center, top, width) = crop;
    final scaleX = image.width / 1024;
    final scaleY = image.height / 1024;
    final source = Rect.fromLTWH(
      (center - width / 2) * scaleX, top * scaleY,
      width * scaleX, width * scaleY,
    );
    canvas.drawImageRect(
      image, source, Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high
             ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _HaloHdPortraitPainter old) =>
      old.image != image || old.crop != crop;
}
