import 'dart:typed_data';
import 'dart:ui' as ui;

/// Upload only MIME types accepted by SpotMate Storage. GIF, BMP and other
/// images that Flutter's platform codec can read are converted to still PNG.
/// HEIC/AVIF depend on browser/OS decoding support.
class SpotmatePreparedImage {
  const SpotmatePreparedImage(this.bytes, this.extension, this.mimeType);
  final Uint8List bytes;
  final String extension;
  final String mimeType;
}

String mimeTypeForSpotmateExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpeg':
    case 'jpg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/png';
  }
}

Future<SpotmatePreparedImage> prepareSpotmateImage(
  Uint8List bytes, {required int maxBytes}) async {
  if (bytes.isEmpty) throw const FormatException('Image is empty.');
  String? ext;
  if (bytes.length >= 3 && bytes[0] == 0xff &&
      bytes[1] == 0xd8 && bytes[2] == 0xff) {
    ext = 'jpeg';
  } else if (bytes.length >= 8 && bytes[0] == 0x89 &&
      bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) {
    ext = 'png';
  } else if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    ext = 'webp';
  }

  Uint8List result = bytes;
  if (ext == null) {
    // Other decodable formats (GIF/BMP/HEIC on supported devices) become PNG.
    ui.Codec? codec;
    ui.Image? frameImage;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
      final frame = await codec.getNextFrame();
      frameImage = frame.image;
      final data = await frameImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('Image conversion failed.');
      result = data.buffer.asUint8List();
      ext = 'png';
    } catch (_) {
      throw const FormatException(
        'This image cannot be decoded by this device. Try JPG, PNG, WebP, GIF or BMP.');
    } finally {
      frameImage?.dispose();
      codec?.dispose();
    }
  }

  if (result.length > maxBytes) {
    throw FormatException('Image exceeds the ${(maxBytes / 1048576).round()} MB upload limit.');
  }
  return SpotmatePreparedImage(result, ext,
      mimeTypeForSpotmateExtension(ext));
}
