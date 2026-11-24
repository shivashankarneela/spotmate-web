import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/chat_keyboard_models.dart';
import 'spotmate_rich_keyboard_panel.dart';

Future<void> showChatExpressionSheet(
  BuildContext context, {
  required ValueChanged<String> insertText,
  required Future<void> Function(SpotmateSticker) sendSticker,
  required Future<void> Function(SpotmateGifItem) sendGif,
  required VoidCallback openExistingPack,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(sheet, false),
                icon: const Icon(Icons.collections_outlined),
                label: const Text('Open media pack'),
              ),
              SpotmateRichKeyboardPanel(
                tenorApiKey: const String.fromEnvironment('TENOR_API_KEY'),
                giphyApiKey: const String.fromEnvironment('GIPHY_API_KEY'),
                onInsertText: (text) => Navigator.pop(sheet, text),
                onSendSticker: (sticker) => Navigator.pop(sheet, sticker),
                onSendGif: (gif) => Navigator.pop(sheet, gif),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case String text:
      insertText(text);
    case SpotmateSticker sticker:
      await sendSticker(sticker);
    case SpotmateGifItem gif:
      await sendGif(gif);
    case false:
      openExistingPack();
  }
}

Future<Uint8List> renderMemeSticker(SpotmateSticker sticker) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(5, 5, 350, 170), const Radius.circular(34)),
    Paint()..color = Color(sticker.accentHex),
  );
  final text = TextPainter(
    text: TextSpan(
      text: '${sticker.badgeEmoji}\n${sticker.label}',
      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 4,
    ellipsis: '…',
  )..layout(maxWidth: 318);
  text.paint(canvas, Offset((360 - text.width) / 2, (180 - text.height) / 2));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(360, 180);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Sticker could not be rendered.');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    text.dispose();
    picture.dispose();
  }
}

Future<Uint8List> downloadChatGif(SpotmateGifItem item) async {
  final uri = Uri.parse(item.gifUrl);
  if (uri.scheme != 'https') throw const FormatException('GIF unavailable.');
  final response = await http.get(uri).timeout(const Duration(seconds: 10));
  final bytes = response.bodyBytes;
  if (response.statusCode != 200 || bytes.length < 6 || bytes.length > 1024 * 1024 ||
      String.fromCharCodes(bytes.take(3)) != 'GIF') {
    throw const FormatException('Choose a GIF smaller than 1 MB.');
  }
  return bytes;
}

const chatImageExtensions = {
  'image/gif': 'gif',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/jpeg': 'jpg',
};

void insertChatExpression(TextEditingController controller, String text) {
  final draft = controller.text;
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : draft.length;
  final end = selection.isValid ? selection.end : draft.length;
  final next = draft.replaceRange(start, end, text);
  if (next.length > 500) return;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
