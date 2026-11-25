import 'dart:async';

import 'package:flutter/widgets.dart';

/// Recognizes a deliberate rightward drag while letting vertical lists scroll.
class HorizontalSwipeAction extends StatefulWidget {
  const HorizontalSwipeAction({
    super.key,
    required this.onSwipe,
    required this.child,
  });

  final VoidCallback? onSwipe;
  final Widget child;

  @override
  State<HorizontalSwipeAction> createState() => _HorizontalSwipeActionState();
}

class _HorizontalSwipeActionState extends State<HorizontalSwipeAction> {
  double _distance = 0;
  bool _pointerReleased = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onSwipe == null) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pointerReleased = false,
      onPointerUp: (_) => _pointerReleased = true,
      onPointerCancel: (_) => _pointerReleased = false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _distance = 0),
        onHorizontalDragUpdate: (details) {
          setState(
            () => _distance = (_distance + details.delta.dx)
                .clamp(0.0, 56.0)
                .toDouble(),
          );
        },
        onHorizontalDragCancel: () => setState(() => _distance = 0),
        onHorizontalDragEnd: (_) {
          final passedThreshold = _distance >= 42;
          setState(() => _distance = 0);
          if (!passedThreshold) return;
          // The raw pointer event can arrive after the recognizer ends.
          scheduleMicrotask(() {
            if (mounted && _pointerReleased) widget.onSwipe?.call();
          });
        },
        child: Transform.translate(
          offset: Offset(_distance, 0),
          transformHitTests: false,
          child: widget.child,
        ),
      ),
    );
  }
}
