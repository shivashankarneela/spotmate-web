import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget buildSpaceShooter() => HtmlElementView.fromTagName(
  tagName: 'iframe',
  onElementCreated: (element) {
    final frame = element as web.HTMLIFrameElement;
    frame
      ..title = 'SpotMate Space Shooter'
      ..src = 'games/space_shooter/index.html';
    frame.style
      ..width = '100%'
      ..height = '100%'
      ..border = '0';
  },
);
