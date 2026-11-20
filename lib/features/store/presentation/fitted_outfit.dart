import 'package:flutter/material.dart';

const outfitIds = <String>{
  'indigo_denim',
  'coastal_linen',
  'emerald_stage',
  'terracotta_drape',
  'navy_tuxedo',
  'monsoon_rider',
  'solar_circuit',
  'metro_runner',
  'sand_safari',
  'deccan_festive',
  'denim_wrap',
  'saffron_anarkali',
  'teal_scarf',
  'varsity_club',
  'pearl_regent',
  'cocoa_knit',
  'court_club',
  'block_print_maxi',
  'midnight_bloom',
  'violet_dance',
};
const outfitPoses = ['Relaxed','Namaste','Sit on chair','Wave','Walk','Dance step'];

class FittedOutfit extends StatelessWidget {
  const FittedOutfit({super.key,required this.item,required this.character,required this.size,this.pose='Relaxed',this.portrait=false});
  final String item, character, pose;
  final double size;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final index = outfitPoses.indexOf(pose);
    final frame = portrait || index < 0 ? 0 : index;
    final number = int.tryParse(character.split('_').last) ?? 1;
    final head = (number-1)%10 + (character.startsWith('girl_') ? 10 : 0);
    final headTop = frame == 2 ? 24.0 : -3.0;
    final view = SizedBox.square(dimension:256, child:Stack(clipBehavior:Clip.hardEdge,children:[
      Positioned(left:-(frame%3)*256.0,top:-(frame~/3)*256.0,
        child:Image.asset('assets/store/${item}_poses.webp',width:768,height:512,fit:BoxFit.fill)),
      Positioned(left:83,top:headTop,child:SizedBox.square(dimension:90,
        child:Stack(clipBehavior:Clip.hardEdge,children:[Positioned(left:-(head%5)*90.0,top:-(head~/5)*90.0,
          child:Image.asset('assets/store/wardrobe_heads.webp',width:450,height:360,fit:BoxFit.fill))]))),
    ]));
    if (!portrait) return SizedBox.square(dimension:size,child:FittedBox(child:view));
    return ClipOval(child:SizedBox.square(dimension:size,child:FittedBox(child:SizedBox.square(dimension:105,
      child:Stack(children:[Positioned(left:-75.5,top:-5,child:view)])))));
  }
}
