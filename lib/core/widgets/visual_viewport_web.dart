import 'dart:js_interop';

@JS('spotmateListenKeyboardViewport')
external JSFunction _listen(JSFunction listener);

@JS('spotmateKeyboardVisibleBottom')
external JSNumber? _visibleBottom();

void Function() listen(void Function() listener) {
  final remove = _listen(listener.toJS);
  return () => remove.callAsFunction();
}

double? keyboardVisibleBottom() => _visibleBottom()?.toDartDouble;
