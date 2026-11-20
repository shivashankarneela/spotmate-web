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

class StoreAvatar extends StatelessWidget {
  const StoreAvatar(this.id, {super.key, required this.size, this.portrait = false});
  final String id;
  final double size;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset('assets/store/$id.webp', width: size, height: size,
      alignment: portrait ? Alignment.topCenter : Alignment.bottomCenter,
      fit: portrait ? BoxFit.cover : BoxFit.contain);
    return portrait ? ClipOval(child: image) : image;
  }
}
