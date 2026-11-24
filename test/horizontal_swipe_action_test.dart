import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotmate/core/widgets/horizontal_swipe_action.dart';

void main() {
  testWidgets('only a deliberate rightward drag selects a reply', (
    tester,
  ) async {
    var replies = 0;
    const message = ValueKey('message');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HorizontalSwipeAction(
            onSwipe: () => replies++,
            child: const SizedBox(key: message, width: 200, height: 100),
          ),
        ),
      ),
    );

    await tester.drag(find.byKey(message), const Offset(0, -80));
    await tester.drag(find.byKey(message), const Offset(-100, 0));
    await tester.drag(find.byKey(message), const Offset(25, 0));
    expect(replies, 0);

    await tester.drag(find.byKey(message), const Offset(100, 0));
    expect(replies, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(message)),
    );
    await gesture.moveBy(const Offset(100, 0));
    await gesture.cancel();
    expect(replies, 1);
  });
}
