import 'package:flutter/foundation.dart';

/// Local signal for an avatar edit saved on the account tab.
/// Chat lobby screens stay mounted in the tab stack, so navigation alone
/// does not recreate their roster. Keep this signal UI-agnostic.
final ValueNotifier<int> avatarProfileUpdates = ValueNotifier<int>(0);

void notifyAvatarProfileSaved() {
  avatarProfileUpdates.value += 1;
}
