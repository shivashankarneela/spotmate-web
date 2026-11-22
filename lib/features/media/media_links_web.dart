// Flutter web opens the player from the user's click.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

bool get mediaLinksAvailable => true;

void openMediaLink(String path) {
  html.window.open(path, '_blank', 'noopener,noreferrer');
}
