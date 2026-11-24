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

  @override
  Widget build(BuildContext context) {
    if (widget.onSwipe == null) return widget.child;
    return GestureDetector(
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
        final shouldSwipe = _distance >= 42;
        setState(() => _distance = 0);
        if (shouldSwipe) widget.onSwipe?.call();
      },
      child: Transform.translate(
        offset: Offset(_distance, 0),
        transformHitTests: false,
        child: widget.child,
      ),
    );
  }
}
