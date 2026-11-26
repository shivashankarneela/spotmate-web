import 'dart:async';

import 'package:flutter/material.dart';

import 'space_shooter_native.dart'
    if (dart.library.js_interop) 'space_shooter_web.dart' as platform;

const spaceShooterArtwork = 'assets/arena/space_shooter.webp';

Future<void> openSpaceShooter(BuildContext context) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(builder: (_) => const SpaceShooterScreen()),
);

class SpaceShooterScreen extends StatelessWidget {
  const SpaceShooterScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Space Shooter')),
    body: SafeArea(top: false, child: platform.buildSpaceShooter()),
  );
}

Future<void> showSpaceShooterLaunch(
  BuildContext context, {
  Future<void> Function(BuildContext) onPlay = openSpaceShooter,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    builder: (dialog) => const _LaunchPoster(),
  );
  final result = navigator.push(route);
  final timeout = Timer(const Duration(seconds: 5), () {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  });
  try {
    if (await result == true && context.mounted) await onPlay(context);
  } finally {
    timeout.cancel();
  }
}

class _LaunchPoster extends StatelessWidget {
  const _LaunchPoster();

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: const Color(0xFF101931),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            AspectRatio(aspectRatio: 2, child: Image.asset(spaceShooterArtwork, fit: BoxFit.cover)),
            Positioned(top: 4, right: 4, child: IconButton.filledTonal(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            )),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('New in Games Arena', style: TextStyle(color: Color(0xFF89D4FF))),
              const Text('Space Shooter', style: TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800,
              )),
              const SizedBox(height: 4),
              const Text('12 missions · Free to play', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play now'),
              )),
            ]),
          ),
        ]),
      ),
    ),
  );
}
