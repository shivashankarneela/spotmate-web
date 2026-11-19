import 'package:flutter/material.dart';

/// Per-device visual preference, stored separately for every conversation.
class SpotmateChatTheme {
  const SpotmateChatTheme({
    required this.key, required this.name, required this.subtitle,
    required this.background, required this.header,
    required this.outgoing, required this.incoming,
    required this.text, required this.outgoingText,
    required this.secondaryText, required this.composer,
    required this.accent,
  });
  final String key, name, subtitle;
  final Color background, header, outgoing, incoming, text,
      outgoingText, secondaryText, composer, accent;

  static const defaultTheme = SpotmateChatTheme(
    key: 'nordic_slate', name: 'Classic', subtitle: 'Warm white with muted teal',
    background: Color(0xFFFAF8F3), header: Colors.white,
    outgoing: Color(0xFF147D72), incoming: Colors.white,
    text: Color(0xFF202B30), outgoingText: Colors.white,
    secondaryText: Color(0xFF4C6075), composer: Colors.white,
    accent: Color(0xFF147D72),
  );

  static const choices = <SpotmateChatTheme>[
    defaultTheme,
    SpotmateChatTheme(
      key: 'warm_sepia', name: 'Ivory', subtitle: 'Warm white and walnut',
      background: Color(0xFFF5F1E9), header: Color(0xFFFFFCF6),
      outgoing: Color(0xFF684B38), incoming: Color(0xFFFFFCF6),
      text: Color(0xFF352A24), outgoingText: Colors.white,
      secondaryText: Color(0xFF67584C), composer: Color(0xFFFFFCF6),
      accent: Color(0xFF69513C),
    ),
    SpotmateChatTheme(
      key: 'soft_sage', name: 'Sage', subtitle: 'Muted green and soft white',
      background: Color(0xFFEDF2EE), header: Color(0xFFFAFCFA),
      outgoing: Color(0xFF335748), incoming: Color(0xFFFAFCFA),
      text: Color(0xFF20372C), outgoingText: Colors.white,
      secondaryText: Color(0xFF495E53), composer: Color(0xFFFAFCFA),
      accent: Color(0xFF335748),
    ),
    SpotmateChatTheme(
      key: 'solarized_dusk', name: 'Ink', subtitle: 'Deep navy with cool blue',
      background: Color(0xFF111C2B), header: Color(0xFF192739),
      outgoing: Color(0xFF34577D), incoming: Color(0xFF233246),
      text: Color(0xFFEAF1F8), outgoingText: Colors.white,
      secondaryText: Color(0xFFB8C9DD), composer: Color(0xFF192739),
      accent: Color(0xFFA9C8EC),
    ),
    SpotmateChatTheme(
      key: 'obsidian_mist', name: 'Graphite', subtitle: 'Neutral charcoal and silver',
      background: Color(0xFF171A1E), header: Color(0xFF20242A),
      outgoing: Color(0xFF454E5B), incoming: Color(0xFF2B3037),
      text: Color(0xFFF2F4F7), outgoingText: Colors.white,
      secondaryText: Color(0xFFC0C7D0), composer: Color(0xFF20242A),
      accent: Color(0xFFBFCADB),
    ),
  ];

  static SpotmateChatTheme forKey(String? key) {
    final preferred = switch (key) {
      'forest_moss' => 'soft_sage',
      'muted_terracotta' || 'midnight_espresso' => 'warm_sepia',
      'twilight_indigo' => 'solarized_dusk',
      'cappuccino_mocha' => 'obsidian_mist',
      _ => key,
    };
    return choices.firstWhere((theme) => theme.key == preferred,
        orElse: () => defaultTheme);
  }
}
