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

  @override
  void initState() {
    super.initState();
    _stopListening = viewport.listen(() {
      if (mounted) setState(() {});
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
    final visibleBottom = viewport.keyboardVisibleBottom();
    if (visibleBottom == null) return widget.child;
    final inset = math.max(media.viewInsets.bottom, media.size.height - visibleBottom);
    if (inset <= media.viewInsets.bottom) return widget.child;
    return MediaQuery(
      data: media.copyWith(viewInsets: media.viewInsets.copyWith(bottom: inset)),
      child: widget.child,
    );
  }
}
