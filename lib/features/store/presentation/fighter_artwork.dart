import 'package:flutter/material.dart';

const _styles = <String, List<String>>{
  'naruto_uzumaki': ['Clone Feint', 'Fox Guard', 'Orb Charge', 'Chakra Leap', 'Sage Landing'],
  'sasuke_uchiha': ['Lightning Palm', 'Flame Silhouette', 'Spectral Guard', 'Sword Draw', 'Aura Lunge'],
  'kakashi_hatake': ['Lightning Dash', 'Shadow Decoy', 'Teleport', 'Hound Summon', 'Masked Guard'],
  'eren_yeager': ['Harness Swing', 'Blade Cross', 'Rooftop Leap', 'Braced Landing', 'Titan Aura'],
  'levi_ackerman': ['Reverse Guard', 'Cable Swing', 'Spinning Slash', 'Inverted Flight', 'Kneeling Recovery'],
  'denji': ['Starter Pull', 'Saw Guard', 'Twisting Leap', 'Twin Sweep', 'Recovery Crouch'],
  'aki_hayakawa': ['Fox Summon', 'Sword Draw', 'Coat Sweep', 'Forewarning', 'Guarded Landing'],
  'tanjiro_kamado': ['Water Guard', 'Wave Arc', 'Rising Spiral', 'Sun Flame', 'Low Recovery'],
  'satoru_gojo': ['Infinity Palm', 'Blue Pull', 'Red Repel', 'Purple Convergence', 'Domain Sign'],
  'ichigo_kurosaki': ['Sword Guard', 'Rising Arc', 'Crescent Release', 'Black Aura', 'Spirit Stance'],
  'sakura_haruno': ['Chakra Charge', 'Guarded Crouch', 'Ground Impact', 'Airborne Strike', 'Healing Aura'],
  'hinata_hyuga': ['Open Palm', 'Circular Step', 'Twin Lions', 'Palm Burst', 'Low Guard'],
  'mikasa_ackerman': ['Twin Blade Guard', 'Cable Swing', 'Aerial Cross', 'Turning Slash', 'Three-point Landing'],
  'sasha_blouse': ['Scout Crouch', 'Bow Raise', 'Full Draw', 'Lateral Dodge', 'Recovery Stance'],
  'power': ['Hammer Ready', 'Crimson Summon', 'Spinning Leap', 'Crimson Shockwave', 'Hammer Guard'],
  'makima': ['Composed Command', 'Point Shockwave', 'Ominous Halo', 'Spectral Chains', 'Command Stance'],
  'shinobu_kocho': ['Butterfly Guard', 'Flutter Leap', 'Blade Thrust', 'Violet Spiral', 'Soft Landing'],
  'mitsuri_kanroji': ['Ribbon Guard', 'Looping Arc', 'Side Leap', 'Ribbon Halo', 'Low Flourish'],
  'nobara_kugisaki': ['Hammer Ready', 'Floating Nails', 'Nail Strike', 'Resonance', 'Follow-through'],
  'rukia_kuchiki': ['Ice Guard', 'Snow Circle', 'Frost Pillar', 'Sweeping Snowfall', 'Ice Aura'],
};

String _characterId(String id) => id.substring(0, id.lastIndexOf('_') < 0 ? id.length : id.lastIndexOf('_'));

List<String> fighterPoses(String id) => _styles[_characterId(id)] ?? const [];

int? fighterPoseIndex(String id, Object? value) {
  const prefix = 'fighter:';
  if (value is! String || !value.startsWith(prefix)) return null;
  final index = int.tryParse(value.substring(prefix.length));
  return index != null && index >= 0 && index < fighterPoses(id).length
      ? index : null;
}

class FighterArtwork extends StatelessWidget {
  const FighterArtwork(this.id, {super.key, this.pose});

  final String id;
  final int? pose;

  // Each image contains either ten outfit pairs or five rows of combat poses.
  static const _combatBounds = [
    ([0, 261, 504, 750, 995, 1247], [85, 309, 541, 764, 988, 1261]),
    ([0, 250, 498, 747, 996, 1246], [87, 325, 550, 774, 1000, 1262]),
    ([0, 246, 483, 721, 952, 1199], [88, 329, 570, 804, 1037, 1312]),
    ([0, 257, 505, 758, 1014, 1263], [43, 288, 506, 733, 964, 1246]),
  ];

  @override
  Widget build(BuildContext context) {
    final index = _styles.keys.toList().indexOf(_characterId(id));
    if (index < 0) return const SizedBox.shrink();
    final group = index ~/ 5;
    final column = index % 5;
    final position = pose;
    if (position != null) {
      final (x, y) = _combatBounds[group];
      return _crop('fighter_combat_$group', x.last, y.last,
        x[column] + 2, y[position] + 2, x[column + 1] - 2, y[position + 1] - 2);
    }

    final collection = group ~/ 2;
    final x = collection == 0 ? const [0, 351, 705, 1058, 1409, 1774]
        : const [0, 344, 693, 1047, 1401, 1774];
    final center = (x[column] + x[column + 1]) ~/ 2;
    final luxury = id.endsWith('_luxury');
    final secondRow = group.isOdd;
    return _crop('fighter_catalog_$collection', 1774, 887,
      luxury ? center : x[column] + 3, secondRow ? 451 : 3,
      luxury ? x[column + 1] - 3 : center, secondRow ? 844 : 394);
  }

  Widget _crop(String asset, int width, int height, int left, int top, int right, int bottom) {
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: (right - left).toDouble(),
        height: (bottom - top).toDouble(),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: -left.toDouble(), top: -top.toDouble(),
            width: width.toDouble(), height: height.toDouble(),
            child: Image.asset('assets/store/$asset.webp', fit: BoxFit.fill,
              filterQuality: FilterQuality.high),
          ),
        ]),
      ),
    );
  }
}
