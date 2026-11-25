import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'visual_viewport_stub.dart'
    if (dart.library.js_interop) 'visual_viewport_web.dart' as viewport;

class ChatKeyboardInsets extends StatefulWidget {
  const ChatKeyboardInsets({super.key, required this.child});
  final Widget child;

  @override
  State<ChatKeyboardInsets> createState() => _ChatKeyboardInsetsState();
}

class _ChatKeyboardInsetsState extends State<ChatKeyboardInsets> {
  VoidCallback? _stopListening;
  double? _visibleBottom;

  @override
  void initState() {
    super.initState();
    _visibleBottom = viewport.keyboardVisibleBottom();
    _stopListening = viewport.listen(() {
      final bottom = viewport.keyboardVisibleBottom();
      if (mounted && bottom != _visibleBottom) {
        setState(() => _visibleBottom = bottom);
      }
    });
  }

  @override
  void dispose() {
    _stopListening?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = _visibleBottom;
    final inset = bottom == null
        ? media.viewInsets.bottom
        : math.max(media.viewInsets.bottom, media.size.height - bottom);
    // Keep the inherited wrapper mounted so keyboard resize retains text focus.
    return MediaQuery(
      data: media.copyWith(viewInsets: media.viewInsets.copyWith(bottom: inset)),
      child: widget.child,
    );
  }
}
