import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildSpaceShooter() => const Center(child: _OpenInBrowser());

class _OpenInBrowser extends StatelessWidget {
  const _OpenInBrowser();

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    icon: const Icon(Icons.open_in_browser),
    label: const Text('Play in browser'),
    onPressed: () async {
      bool opened;
      try {
        opened = await launchUrl(
          Uri.parse(const String.fromEnvironment(
            'SPOTMATE_WEB_ORIGIN', defaultValue: 'https://spotmate-web.vercel.app',
          )).resolve('/games/space_shooter/index.html'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Space Shooter in your browser.')),
        );
      }
    },
  );
}
