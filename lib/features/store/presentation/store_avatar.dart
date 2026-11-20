import 'package:flutter/material.dart';

const storeAvatarIds = <String>{
  'naruto_uzumaki_normal',
  'naruto_uzumaki_luxury',
  'sasuke_uchiha_normal',
  'sasuke_uchiha_luxury',
  'kakashi_hatake_normal',
  'kakashi_hatake_luxury',
  'eren_yeager_normal',
  'eren_yeager_luxury',
  'levi_ackerman_normal',
  'levi_ackerman_luxury',
  'denji_normal',
  'denji_luxury',
  'aki_hayakawa_normal',
  'aki_hayakawa_luxury',
  'tanjiro_kamado_normal',
  'tanjiro_kamado_luxury',
  'satoru_gojo_normal',
  'satoru_gojo_luxury',
  'ichigo_kurosaki_normal',
  'ichigo_kurosaki_luxury',
  'sakura_haruno_normal',
  'sakura_haruno_luxury',
  'hinata_hyuga_normal',
  'hinata_hyuga_luxury',
  'mikasa_ackerman_normal',
  'mikasa_ackerman_luxury',
  'sasha_blouse_normal',
  'sasha_blouse_luxury',
  'power_normal',
  'power_luxury',
  'makima_normal',
  'makima_luxury',
  'shinobu_kocho_normal',
  'shinobu_kocho_luxury',
  'mitsuri_kanroji_normal',
  'mitsuri_kanroji_luxury',
  'nobara_kugisaki_normal',
  'nobara_kugisaki_luxury',
  'rukia_kuchiki_normal',
  'rukia_kuchiki_luxury',
};

const _signatureNames = <String, String>{
  'naruto_uzumaki': 'Rasengan',
  'sasuke_uchiha': 'Chidori',
  'kakashi_hatake': 'Lightning Blade',
  'eren_yeager': 'Titan Guard',
  'levi_ackerman': 'Spinning Blade',
  'denji': 'Rev Up',
  'aki_hayakawa': 'Fox Sign',
  'tanjiro_kamado': 'Water Wheel',
  'satoru_gojo': 'Limitless',
  'ichigo_kurosaki': 'Moon Fang',
  'sakura_haruno': 'Chakra Fist',
  'hinata_hyuga': 'Gentle Fist',
  'mikasa_ackerman': 'Twin Blades',
  'sasha_blouse': 'Hunter’s Draw',
  'power': 'Crimson Hammer',
  'makima': 'Command',
  'shinobu_kocho': 'Butterfly Thrust',
  'mitsuri_kanroji': 'Ribbon Arc',
  'nobara_kugisaki': 'Resonance',
  'rukia_kuchiki': 'Frost Salute',
};

String storeSignatureName(String id) => _signatureNames[id.substring(0, id.lastIndexOf('_'))]!;

class StoreAvatar extends StatelessWidget {
  const StoreAvatar(this.id, {super.key, required this.size, this.portrait = false, this.signature = false});
  final String id;
  final double size;
  final bool portrait;
  final bool signature;

  @override
  Widget build(BuildContext context) {
    final asset = signature && !portrait ? '${id}_signature' : id;
    final image = Image.asset('assets/store/$asset.webp', width: size, height: size,
      alignment: portrait ? Alignment.topCenter : Alignment.bottomCenter,
      fit: portrait ? BoxFit.cover : BoxFit.contain);
    return portrait ? ClipOval(child: image) : image;
  }
}
