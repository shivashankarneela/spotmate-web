import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

/// Illustrated portraits and profile photos fitted to the same circular frame.
class SpotmateAvatar extends StatelessWidget {
  const SpotmateAvatar({
    super.key,this.size=48,this.photoUrl,this.avatarType='photo',
    this.emoticon='boy_01', this.fullPortrait = false, this.posture = 'Relaxed',
  });
  final double size;
  final String? photoUrl;
  final String avatarType;
  final String emoticon;
  final bool fullPortrait;
  final String posture;
  static const poses = {'Relaxed':'relaxed','Signature':'signature','Namaste':'namaste','Wave':'wave','Thumbs up':'thumb','Dance step':'dance','Sit on chair':'chair'};
  static final _sheets = <String, Future<ui.Image>>{};
  static Future<ui.Image> _sheet(String pose) async {
    final bytes = await rootBundle.load('assets/avatars/postures/${poses[pose]}.webp');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    try { return (await codec.getNextFrame()).image; } finally { codec.dispose(); }
  }

  static final List<String> boys=List.generate(
    10,(i)=>'boy_${(i+1).toString().padLeft(2,'0')}');
  static final List<String> girls=List.generate(
    10,(i)=>'girl_${(i+1).toString().padLeft(2,'0')}');
  static bool isCharacter(String id)=>boys.contains(id)||girls.contains(id);
  static String normalized(String value) {
    if(RegExp(r'^(boy|girl)_(0[1-9]|1[0-9]|20)
    const legacy={'smile':'boy_01','cool':'boy_04','star':'boy_06',
      'heart':'girl_03','laugh':'girl_10','wave':'boy_09',
      'spark':'girl_14','flower':'girl_16'};
    return legacy[value]??'boy_01';
  }

  static Future<ui.Image>? _sprite;
  static Future<ui.Image>? _fullSprite;

  static Future<ui.Image> _loadSprite({bool full = false}) async {
    final data = await rootBundle.load(full
        ? 'assets/avatars/spotmate_full_body.webp'
        : 'assets/avatars/spotmate_portraits_hd.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override Widget build(BuildContext context){
    final photo=avatarType=='photo'&&photoUrl!=null&&photoUrl!.isNotEmpty;
    if(photo && fullPortrait) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(
        photoUrl!, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _portrait()));
    }
    if(photo)return ClipOval(child:Image.network(photoUrl!,
      width:size,height:size,fit:BoxFit.cover,
      errorBuilder:(_,__,___)=>_portrait()));
    return _portrait();
  }

  Widget _portrait() {
    final id = normalized(emoticon);
    final number = int.parse(id.split('_').last);
    if (number <= 10) {
      final index = number - 1 + (id.startsWith('girl_') ? 10 : 0);
      final pose = fullPortrait && poses.containsKey(posture) ? posture : 'Relaxed';
      final image = SizedBox.square(dimension: size, child: FutureBuilder<ui.Image>(
        future: _sheets.putIfAbsent(pose, () => _sheet(pose)),
        builder: (_, snapshot) => snapshot.hasData ? CustomPaint(painter: _StudioPainter(snapshot.data!, index, fullPortrait)) : const SizedBox.shrink(),
      ));
      return fullPortrait ? image : ClipOval(child: image);
    }
    final portrait = SizedBox.square(dimension: size,
      child: FutureBuilder<ui.Image>(
        future: fullPortrait ? (_fullSprite ??= _loadSprite(full: true)) : (_sprite ??= _loadSprite()),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return CustomPaint(painter: _IllustratedPortraitPainter(
              snapshot.data!, normalized(emoticon), fullPortrait));
          }
          if (snapshot.hasError) {
            return CustomPaint(painter: _ChibiPainter(normalized(emoticon)));
          }
          return const ColoredBox(color: Color(0xFFE9EDF0));
        },
      ),
    );
    return fullPortrait
        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: portrait)
        : ClipOval(child: portrait);
  }
}

/// Compact choice only. The 40-character gallery opens in a separate drawer
/// so account and onboarding stay uncluttered.
class SpotmateAvatarPicker extends StatelessWidget {
  const SpotmateAvatarPicker({super.key,required this.avatarType,
    required this.emoticon,required this.onChoice,required this.onPickPhoto});
  final String avatarType;
  final String emoticon;
  final void Function(String,String) onChoice;
  final VoidCallback onPickPhoto;

  Future<void> _showGallery(BuildContext context) async {
    await showModalBottomSheet<void>(
      context:context,isScrollControlled:true,showDragHandle:true,
      backgroundColor:const Color(0xFFF5F8FA),
      builder:(sheetContext)=>DefaultTabController(length:2,
        child:SafeArea(child:FractionallySizedBox(heightFactor:.85,
          child:Column(children:[
            const Padding(padding:EdgeInsets.fromLTRB(18,4,18,12),
              child:Column(children:[
                Text('Choose your character',style:TextStyle(
                  fontSize:21,fontWeight:FontWeight.w800,
                  color:Color(0xFF162544))),
                SizedBox(height:5),
              ])),
            const TabBar(tabs:[Tab(text:'Boys · 10'),Tab(text:'Girls · 10')]),
            Expanded(child:TabBarView(children:[
              _avatarGrid(sheetContext,SpotmateAvatar.boys),
              _avatarGrid(sheetContext,SpotmateAvatar.girls),
            ])),
          ]),
        ))),
    );
  }
  Widget _avatarGrid(BuildContext sheetContext,List<String> ids){
    return GridView.builder(
      padding:const EdgeInsets.fromLTRB(12,18,12,28),
      itemCount:ids.length,
      gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent:125,mainAxisSpacing:12,crossAxisSpacing:10,
        childAspectRatio:1),
      itemBuilder:(context,index){
        final id=ids[index];
        final selected=avatarType=='emoticon'&&emoticon==id;
        return InkWell(
          borderRadius:BorderRadius.circular(16),
          onTap:(){
            onChoice('emoticon',id);
            Navigator.of(sheetContext).pop();
          },
          child:Container(
            decoration:BoxDecoration(
              color:Colors.white,borderRadius:BorderRadius.circular(16),
              border:Border.all(color:selected?const Color(0xFF18A68D):
                const Color(0xFFE3E8ED),width:selected?2.5:1)),
            padding:const EdgeInsets.all(5),
            child:Column(children:[
              Expanded(child:Center(child:LayoutBuilder(builder:(context,box){
                final size=math.min(box.maxWidth,box.maxHeight) * .9;
                return SpotmateAvatar(size:size,avatarType:'emoticon',emoticon:id);
              }))),

            ]),
          ),
        );
      },
    );
  }

  @override Widget build(BuildContext context){
    final showingEmoticon=avatarType=='emoticon';
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('How would you like to appear?',
        style:TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF162544))),
      const SizedBox(height:9),
      Wrap(spacing:8,runSpacing:8,children:[
        ChoiceChip(label:const Text('My photo'),selected:!showingEmoticon,
          onSelected:(_)=>onChoice('photo',emoticon)),
        ChoiceChip(label:const Text('Illustrated character'),
          selected:showingEmoticon,
          onSelected:(_)=>onChoice('emoticon',
            SpotmateAvatar.normalized(emoticon))),
      ]),
      const SizedBox(height:9),
      if(showingEmoticon)
        OutlinedButton.icon(
          onPressed:()=>_showGallery(context),
          icon:SpotmateAvatar(size:36,avatarType:'emoticon',emoticon:emoticon),
          label:const Text('Browse 40 characters'),
        )
      else
        OutlinedButton.icon(
          onPressed:onPickPhoto,
          icon:const Icon(Icons.add_a_photo_outlined),
          label:const Text('Choose or replace profile photo'),
        ),
    ]);
  }
}

/// Face anchors use the original 2048 × 1143 artwork coordinates.
class _StudioPainter extends CustomPainter {
  _StudioPainter(this.sheet, this.index, this.full);
  final ui.Image sheet;
  final int index;
  final bool full;
  @override
  void paint(Canvas canvas, Size size) {
    final w = sheet.width / 5, h = sheet.height / 4;
    final x = index % 5 * w, y = index ~/ 5 * h;
    final source = full ? Rect.fromLTWH(x,y,w,h) : Rect.fromLTWH(x+w*.29,y,w*.42,w*.42);
    final target = applyBoxFit(BoxFit.contain, source.size,size).destination;
    canvas.drawImageRect(sheet, source, Alignment.center.inscribe(target, Offset.zero & size), Paint()..filterQuality=FilterQuality.high);
  }
  @override
  bool shouldRepaint(_StudioPainter old) => old.sheet != sheet || old.index != index || old.full != full;
}

class _IllustratedPortraitPainter extends CustomPainter {
  _IllustratedPortraitPainter(this.sprite, this.id, this.fullPortrait);

  final ui.Image sprite;
  final String id;
  final bool fullPortrait;

  static const _faceX = [
    [143, 335, 524, 715, 915, 1152, 1338, 1544, 1747, 1943],
    [134, 329, 522, 717, 922, 1141, 1335, 1540, 1747, 1934],
    [131, 328, 522, 716, 925, 1143, 1336, 1537, 1737, 1939],
    [132, 322, 524, 702, 920, 1142, 1338, 1540, 1727, 1946],
  ];
  static const _faceY = [
    [173, 173, 167, 170, 174, 176, 177, 176, 174, 179],
    [441, 438, 435, 442, 435, 446, 445, 445, 438, 451],
    [707, 709, 712, 706, 708, 715, 708, 710, 708, 712],
    [978, 977, 977, 972, 975, 977, 975, 982, 981, 982],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final number = int.parse(id.split('_').last) - 1;
    final row = number ~/ 5;
    final column = number % 5 + (id.startsWith('girl_') ? 5 : 0);
    final source = fullPortrait ? _characterBounds(row, column) : Rect.fromCenter(
      center: Offset(_faceX[row][column].toDouble(), _faceY[row][column].toDouble()),
      width: 164,
      height: 164,
    );
    final diameter = math.min(size.width, size.height);
    final fitted = applyBoxFit(BoxFit.contain, source.size, Size.square(diameter));
    final destination = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: fitted.destination.width,
      height: fitted.destination.height,
    );
    canvas.drawImageRect(sprite, source, destination,
      Paint()..filterQuality = FilterQuality.high);
  }

  Rect _characterBounds(int row, int column) {
    const xs = [24.0, 178.0, 330.0, 482.0, 635.0, 786.0, 934.0,
      1076.0, 1224.0, 1371.0, 1536.0];
    const ys = [0.0, 266.0, 520.0, 774.0, 1024.0];
    return Rect.fromLTRB(xs[column], ys[row], xs[column + 1], ys[row + 1]);
  }

  @override
  bool shouldRepaint(covariant _IllustratedPortraitPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.sprite != sprite ||
      oldDelegate.fullPortrait != fullPortrait;
}

class _ChibiPainter extends CustomPainter{
  _ChibiPainter(this.id);
  final String id;
  static const skin=[
    Color(0xFFFFDCC4),Color(0xFFF8CCAE),
    Color(0xFFDFAE8C),Color(0xFFF0BC9E),
  ];
  static const hair=[
    Color(0xFF725247),Color(0xFFC68659),Color(0xFF433D43),
    Color(0xFF9D684E),Color(0xFFB9A5D8),Color(0xFF3B465C),
    Color(0xFFEDB77E),Color(0xFF8D536E),Color(0xFF6E5244),
    Color(0xFF82B8D8),
  ];
  static const outfit=[
    Color(0xFF5C9DD1),Color(0xFFF3A5A2),Color(0xFFB4A0D9),
    Color(0xFFF5C66E),Color(0xFF95C6A5),Color(0xFF728FB6),
    Color(0xFFF49D73),Color(0xFFCF86A7),
  ];
  static const backdrop=[
    Color(0xFFEAF4FF),Color(0xFFFFF2E5),Color(0xFFF5EFFD),
    Color(0xFFE9F9F2),Color(0xFFFFEAF3),
  ];

  @override void paint(Canvas canvas,Size size){
    canvas.save();
    canvas.scale(size.width/100,size.height/100);
    final girl=id.startsWith('girl_');
    final raw=int.tryParse(id.split('_').last)??1;
    final i=(raw-1).clamp(0,19);
    final face=skin[(i+(girl?1:0))%skin.length];
    final hairColor=hair[(i*3+(girl?2:0))%hair.length];
    final shirt=outfit[(i*5+(girl?3:0))%outfit.length];
    final bg=backdrop[(i+(girl?2:0))%backdrop.length];
    final stroke=Paint()..color=const Color(0xFF593D40)
      ..style=PaintingStyle.stroke..strokeWidth=1.8..strokeCap=StrokeCap.round;
    final fill=(Color c)=>Paint()..color=c..style=PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(0,0,100,100),const Radius.circular(24)),fill(bg));
    // Decorative pastel stars and confetti.
    for(final off in [Offset(14.0+i%5,19.0),Offset(83.0,15.0+i%6)]){
      canvas.drawCircle(off,2.2,fill(const Color(0xFFE9B86B)));
    }
    // Neck, shoulders, and clothing.
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(45,70,13,15),const Radius.circular(5)),fill(face));
    final torso=Path()..moveTo(22,101)..quadraticBezierTo(24,84,42,81)
      ..quadraticBezierTo(54,76,68,82)..quadraticBezierTo(84,84,86,101)..close();
    canvas.drawPath(torso,fill(shirt));canvas.drawPath(torso,stroke);
    final collar=Path()..moveTo(40,81)..lineTo(50,91)..lineTo(61,81);
    canvas.drawPath(collar,stroke);
    if(i%3==0){
      canvas.drawLine(const Offset(50,91),const Offset(50,100),
        Paint()..color=Colors.white..strokeWidth=3);
    }
    // Back hair and optional side locks.
    canvas.drawOval(Rect.fromCenter(center:const Offset(52,49),
      width:girl?72:68,height:girl?75:67),fill(hairColor));
    if(girl){
      if(i%4==0){
        canvas.drawCircle(const Offset(21,43),15,fill(hairColor));
        canvas.drawCircle(const Offset(84,43),15,fill(hairColor));
      }else if(i%4==1){
        canvas.drawRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(20,42,16,46),const Radius.circular(8)),
          fill(hairColor));
        canvas.drawRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(70,42,16,46),const Radius.circular(8)),
          fill(hairColor));
      }
    }
    // Ears and round soft face.
    canvas.drawOval(const Rect.fromLTWH(20,48,13,17),fill(face));
    canvas.drawOval(const Rect.fromLTWH(73,48,13,17),fill(face));
    canvas.drawOval(const Rect.fromLTWH(28,29,50,53),fill(face));
    canvas.drawOval(const Rect.fromLTWH(28,29,50,53),stroke);
    // Bangs: hand-drawn swoops varied for each character.
    final bang=Path()
      ..moveTo(26,46)..quadraticBezierTo(20,20,42,19)
      ..quadraticBezierTo(64,10,79,28)
      ..quadraticBezierTo(83,38,79,46)
      ..quadraticBezierTo(69,35,63,40)
      ..quadraticBezierTo(56,32,49,43)
      ..quadraticBezierTo(43,34,34,48)
      ..close();
    canvas.drawPath(bang,fill(hairColor));
    if(i%4==1){
      canvas.drawArc(const Rect.fromLTWH(34,22,38,21),0,math.pi,
        false,Paint()..color=const Color(0x77FFFFFF)
        ..strokeWidth=2..style=PaintingStyle.stroke);
    }
    // Eye variations: wink, sleeping, happy, surprised, bright-eyed.
    final expr=i%6;
    if(expr==0||expr==3){
      for(final x in [42.0,65.0]){
        final p=Path()..moveTo(x-5,56)..quadraticBezierTo(x,49,x+5,56);
        canvas.drawPath(p,Paint()..color=const Color(0xFF493640)
          ..style=PaintingStyle.stroke..strokeWidth=2.5
          ..strokeCap=StrokeCap.round);
      }
    }else{
      canvas.drawOval(const Rect.fromLTWH(36,50,9,13),fill(const Color(0xFF493640)));
      canvas.drawOval(const Rect.fromLTWH(60,50,9,13),fill(const Color(0xFF493640)));
      canvas.drawCircle(const Offset(40,54),2.2,fill(Colors.white));
      canvas.drawCircle(const Offset(64,54),2.2,fill(Colors.white));
      if(expr==2){
        canvas.drawLine(const Offset(60,57),const Offset(69,57),
          Paint()..color=face..strokeWidth=8);
        canvas.drawArc(const Rect.fromLTWH(59,52,11,7),0,math.pi,
          false,stroke);
      }
    }
    canvas.drawOval(const Rect.fromLTWH(31,64,13,5),
      fill(const Color(0x99EF8F9D)));
    canvas.drawOval(const Rect.fromLTWH(65,64,13,5),
      fill(const Color(0x99EF8F9D)));
    if(expr==1||expr==5){
      canvas.drawOval(const Rect.fromLTWH(48,66,8,7),
        fill(const Color(0xFFB96A72)));
    }else{
      final smile=Path()..moveTo(48,69)..quadraticBezierTo(53,73,58,69);
      canvas.drawPath(smile,stroke);
    }
    // Eyebrow and varied accessory combinations.
    if(i%5==0||i%5==3){
      canvas.drawLine(const Offset(35,48),const Offset(43,47),
        Paint()..color=hairColor..strokeWidth=1.5);
      canvas.drawLine(const Offset(62,47),const Offset(70,48),
        Paint()..color=hairColor..strokeWidth=1.5);
    }
    if(girl && i%4==0){
      // Bow with two loops and knot.
      final bow=Paint()..color=const Color(0xFFEB83A6);
      canvas.drawOval(const Rect.fromLTWH(70,16,14,12),bow);
      canvas.drawOval(const Rect.fromLTWH(84,16,12,12),bow);
      canvas.drawCircle(const Offset(84,22),4,fill(const Color(0xFFBB5477)));
    }else if(i%5==1){
      // Small coloured hair clip.
      canvas.save();canvas.translate(73,34);canvas.rotate(-.35);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5,-3,13,5),const Radius.circular(2)),
        fill(const Color(0xFFFFC572)));canvas.restore();
    }else if(!girl&&i%5==2){
      // Beanie with curved brim.
      final hat=Path()..moveTo(27,34)..quadraticBezierTo(28,9,52,8)
        ..quadraticBezierTo(77,10,80,34)..close();
      canvas.drawPath(hat,fill(const Color(0xFF678DAA)));
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(25,31,57,9),const Radius.circular(5)),
        fill(const Color(0xFF44718F)));
    }else if(i%7==4){
      // Round glasses.
      final glass=Paint()..color=const Color(0xFF6E607B)
        ..strokeWidth=2..style=PaintingStyle.stroke;
      canvas.drawOval(const Rect.fromLTWH(33,49,17,16),glass);
      canvas.drawOval(const Rect.fromLTWH(56,49,17,16),glass);
      canvas.drawLine(const Offset(50,56),const Offset(56,56),glass);
    }
    canvas.restore();
  }
  @override bool shouldRepaint(covariant _ChibiPainter old)=>old.id!=id;
}
).hasMatch(value)) return value;
    const legacy={'smile':'boy_01','cool':'boy_04','star':'boy_06',
      'heart':'girl_03','laugh':'girl_10','wave':'boy_09',
      'spark':'girl_14','flower':'girl_16'};
    return legacy[value]??'boy_01';
  }

  static Future<ui.Image>? _sprite;
  static Future<ui.Image>? _fullSprite;

  static Future<ui.Image> _loadSprite({bool full = false}) async {
    final data = await rootBundle.load(full
        ? 'assets/avatars/spotmate_full_body.webp'
        : 'assets/avatars/spotmate_portraits_hd.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override Widget build(BuildContext context){
    final photo=avatarType=='photo'&&photoUrl!=null&&photoUrl!.isNotEmpty;
    if(photo && fullPortrait) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(
        photoUrl!, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _portrait()));
    }
    if(photo)return ClipOval(child:Image.network(photoUrl!,
      width:size,height:size,fit:BoxFit.cover,
      errorBuilder:(_,__,___)=>_portrait()));
    return _portrait();
  }

  Widget _portrait() {
    final id = normalized(emoticon);
    final number = int.parse(id.split('_').last);
    if (number <= 10) {
      final index = number - 1 + (id.startsWith('girl_') ? 10 : 0);
      final pose = fullPortrait && poses.containsKey(posture) ? posture : 'Relaxed';
      final image = SizedBox.square(dimension: size, child: FutureBuilder<ui.Image>(
        future: _sheets.putIfAbsent(pose, () => _sheet(pose)),
        builder: (_, snapshot) => snapshot.hasData ? CustomPaint(painter: _StudioPainter(snapshot.data!, index, fullPortrait)) : const SizedBox.shrink(),
      ));
      return fullPortrait ? image : ClipOval(child: image);
    }
    final portrait = SizedBox.square(dimension: size,
      child: FutureBuilder<ui.Image>(
        future: fullPortrait ? (_fullSprite ??= _loadSprite(full: true)) : (_sprite ??= _loadSprite()),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return CustomPaint(painter: _IllustratedPortraitPainter(
              snapshot.data!, normalized(emoticon), fullPortrait));
          }
          if (snapshot.hasError) {
            return CustomPaint(painter: _ChibiPainter(normalized(emoticon)));
          }
          return const ColoredBox(color: Color(0xFFE9EDF0));
        },
      ),
    );
    return fullPortrait
        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: portrait)
        : ClipOval(child: portrait);
  }
}

/// Compact choice only. The 40-character gallery opens in a separate drawer
/// so account and onboarding stay uncluttered.
class SpotmateAvatarPicker extends StatelessWidget {
  const SpotmateAvatarPicker({super.key,required this.avatarType,
    required this.emoticon,required this.onChoice,required this.onPickPhoto});
  final String avatarType;
  final String emoticon;
  final void Function(String,String) onChoice;
  final VoidCallback onPickPhoto;

  Future<void> _showGallery(BuildContext context) async {
    await showModalBottomSheet<void>(
      context:context,isScrollControlled:true,showDragHandle:true,
      backgroundColor:const Color(0xFFF5F8FA),
      builder:(sheetContext)=>DefaultTabController(length:2,
        child:SafeArea(child:FractionallySizedBox(heightFactor:.85,
          child:Column(children:[
            const Padding(padding:EdgeInsets.fromLTRB(18,4,18,12),
              child:Column(children:[
                Text('Choose your character',style:TextStyle(
                  fontSize:21,fontWeight:FontWeight.w800,
                  color:Color(0xFF162544))),
                SizedBox(height:5),
              ])),
            const TabBar(tabs:[Tab(text:'Boys · 20'),Tab(text:'Girls · 20')]),
            Expanded(child:TabBarView(children:[
              _avatarGrid(sheetContext,SpotmateAvatar.boys),
              _avatarGrid(sheetContext,SpotmateAvatar.girls),
            ])),
          ]),
        ))),
    );
  }
  Widget _avatarGrid(BuildContext sheetContext,List<String> ids){
    return GridView.builder(
      padding:const EdgeInsets.fromLTRB(12,18,12,28),
      itemCount:ids.length,
      gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent:125,mainAxisSpacing:12,crossAxisSpacing:10,
        childAspectRatio:1),
      itemBuilder:(context,index){
        final id=ids[index];
        final selected=avatarType=='emoticon'&&emoticon==id;
        return InkWell(
          borderRadius:BorderRadius.circular(16),
          onTap:(){
            onChoice('emoticon',id);
            Navigator.of(sheetContext).pop();
          },
          child:Container(
            decoration:BoxDecoration(
              color:Colors.white,borderRadius:BorderRadius.circular(16),
              border:Border.all(color:selected?const Color(0xFF18A68D):
                const Color(0xFFE3E8ED),width:selected?2.5:1)),
            padding:const EdgeInsets.all(5),
            child:Column(children:[
              Expanded(child:Center(child:LayoutBuilder(builder:(context,box){
                final size=math.min(box.maxWidth,box.maxHeight) * .9;
                return SpotmateAvatar(size:size,avatarType:'emoticon',emoticon:id);
              }))),

            ]),
          ),
        );
      },
    );
  }

  @override Widget build(BuildContext context){
    final showingEmoticon=avatarType=='emoticon';
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('How would you like to appear?',
        style:TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF162544))),
      const SizedBox(height:9),
      Wrap(spacing:8,runSpacing:8,children:[
        ChoiceChip(label:const Text('My photo'),selected:!showingEmoticon,
          onSelected:(_)=>onChoice('photo',emoticon)),
        ChoiceChip(label:const Text('Illustrated character'),
          selected:showingEmoticon,
          onSelected:(_)=>onChoice('emoticon',
            SpotmateAvatar.normalized(emoticon))),
      ]),
      const SizedBox(height:9),
      if(showingEmoticon)
        OutlinedButton.icon(
          onPressed:()=>_showGallery(context),
          icon:SpotmateAvatar(size:36,avatarType:'emoticon',emoticon:emoticon),
          label:const Text('Browse 40 characters'),
        )
      else
        OutlinedButton.icon(
          onPressed:onPickPhoto,
          icon:const Icon(Icons.add_a_photo_outlined),
          label:const Text('Choose or replace profile photo'),
        ),
    ]);
  }
}

/// Face anchors use the original 2048 × 1143 artwork coordinates.
class _StudioPainter extends CustomPainter {
  _StudioPainter(this.sheet, this.index, this.full);
  final ui.Image sheet;
  final int index;
  final bool full;
  @override
  void paint(Canvas canvas, Size size) {
    final w = sheet.width / 5, h = sheet.height / 4;
    final x = index % 5 * w, y = index ~/ 5 * h;
    final source = full ? Rect.fromLTWH(x,y,w,h) : Rect.fromLTWH(x+w*.29,y,w*.42,w*.42);
    final target = applyBoxFit(BoxFit.contain, source.size,size).destination;
    canvas.drawImageRect(sheet, source, Alignment.center.inscribe(target, Offset.zero & size), Paint()..filterQuality=FilterQuality.high);
  }
  @override
  bool shouldRepaint(_StudioPainter old) => old.sheet != sheet || old.index != index || old.full != full;
}

class _IllustratedPortraitPainter extends CustomPainter {
  _IllustratedPortraitPainter(this.sprite, this.id, this.fullPortrait);

  final ui.Image sprite;
  final String id;
  final bool fullPortrait;

  static const _faceX = [
    [143, 335, 524, 715, 915, 1152, 1338, 1544, 1747, 1943],
    [134, 329, 522, 717, 922, 1141, 1335, 1540, 1747, 1934],
    [131, 328, 522, 716, 925, 1143, 1336, 1537, 1737, 1939],
    [132, 322, 524, 702, 920, 1142, 1338, 1540, 1727, 1946],
  ];
  static const _faceY = [
    [173, 173, 167, 170, 174, 176, 177, 176, 174, 179],
    [441, 438, 435, 442, 435, 446, 445, 445, 438, 451],
    [707, 709, 712, 706, 708, 715, 708, 710, 708, 712],
    [978, 977, 977, 972, 975, 977, 975, 982, 981, 982],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final number = int.parse(id.split('_').last) - 1;
    final row = number ~/ 5;
    final column = number % 5 + (id.startsWith('girl_') ? 5 : 0);
    final source = fullPortrait ? _characterBounds(row, column) : Rect.fromCenter(
      center: Offset(_faceX[row][column].toDouble(), _faceY[row][column].toDouble()),
      width: 164,
      height: 164,
    );
    final diameter = math.min(size.width, size.height);
    final fitted = applyBoxFit(BoxFit.contain, source.size, Size.square(diameter));
    final destination = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: fitted.destination.width,
      height: fitted.destination.height,
    );
    canvas.drawImageRect(sprite, source, destination,
      Paint()..filterQuality = FilterQuality.high);
  }

  Rect _characterBounds(int row, int column) {
    const xs = [24.0, 178.0, 330.0, 482.0, 635.0, 786.0, 934.0,
      1076.0, 1224.0, 1371.0, 1536.0];
    const ys = [0.0, 266.0, 520.0, 774.0, 1024.0];
    return Rect.fromLTRB(xs[column], ys[row], xs[column + 1], ys[row + 1]);
  }

  @override
  bool shouldRepaint(covariant _IllustratedPortraitPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.sprite != sprite ||
      oldDelegate.fullPortrait != fullPortrait;
}

class _ChibiPainter extends CustomPainter{
  _ChibiPainter(this.id);
  final String id;
  static const skin=[
    Color(0xFFFFDCC4),Color(0xFFF8CCAE),
    Color(0xFFDFAE8C),Color(0xFFF0BC9E),
  ];
  static const hair=[
    Color(0xFF725247),Color(0xFFC68659),Color(0xFF433D43),
    Color(0xFF9D684E),Color(0xFFB9A5D8),Color(0xFF3B465C),
    Color(0xFFEDB77E),Color(0xFF8D536E),Color(0xFF6E5244),
    Color(0xFF82B8D8),
  ];
  static const outfit=[
    Color(0xFF5C9DD1),Color(0xFFF3A5A2),Color(0xFFB4A0D9),
    Color(0xFFF5C66E),Color(0xFF95C6A5),Color(0xFF728FB6),
    Color(0xFFF49D73),Color(0xFFCF86A7),
  ];
  static const backdrop=[
    Color(0xFFEAF4FF),Color(0xFFFFF2E5),Color(0xFFF5EFFD),
    Color(0xFFE9F9F2),Color(0xFFFFEAF3),
  ];

  @override void paint(Canvas canvas,Size size){
    canvas.save();
    canvas.scale(size.width/100,size.height/100);
    final girl=id.startsWith('girl_');
    final raw=int.tryParse(id.split('_').last)??1;
    final i=(raw-1).clamp(0,19);
    final face=skin[(i+(girl?1:0))%skin.length];
    final hairColor=hair[(i*3+(girl?2:0))%hair.length];
    final shirt=outfit[(i*5+(girl?3:0))%outfit.length];
    final bg=backdrop[(i+(girl?2:0))%backdrop.length];
    final stroke=Paint()..color=const Color(0xFF593D40)
      ..style=PaintingStyle.stroke..strokeWidth=1.8..strokeCap=StrokeCap.round;
    final fill=(Color c)=>Paint()..color=c..style=PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(0,0,100,100),const Radius.circular(24)),fill(bg));
    // Decorative pastel stars and confetti.
    for(final off in [Offset(14.0+i%5,19.0),Offset(83.0,15.0+i%6)]){
      canvas.drawCircle(off,2.2,fill(const Color(0xFFE9B86B)));
    }
    // Neck, shoulders, and clothing.
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(45,70,13,15),const Radius.circular(5)),fill(face));
    final torso=Path()..moveTo(22,101)..quadraticBezierTo(24,84,42,81)
      ..quadraticBezierTo(54,76,68,82)..quadraticBezierTo(84,84,86,101)..close();
    canvas.drawPath(torso,fill(shirt));canvas.drawPath(torso,stroke);
    final collar=Path()..moveTo(40,81)..lineTo(50,91)..lineTo(61,81);
    canvas.drawPath(collar,stroke);
    if(i%3==0){
      canvas.drawLine(const Offset(50,91),const Offset(50,100),
        Paint()..color=Colors.white..strokeWidth=3);
    }
    // Back hair and optional side locks.
    canvas.drawOval(Rect.fromCenter(center:const Offset(52,49),
      width:girl?72:68,height:girl?75:67),fill(hairColor));
    if(girl){
      if(i%4==0){
        canvas.drawCircle(const Offset(21,43),15,fill(hairColor));
        canvas.drawCircle(const Offset(84,43),15,fill(hairColor));
      }else if(i%4==1){
        canvas.drawRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(20,42,16,46),const Radius.circular(8)),
          fill(hairColor));
        canvas.drawRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(70,42,16,46),const Radius.circular(8)),
          fill(hairColor));
      }
    }
    // Ears and round soft face.
    canvas.drawOval(const Rect.fromLTWH(20,48,13,17),fill(face));
    canvas.drawOval(const Rect.fromLTWH(73,48,13,17),fill(face));
    canvas.drawOval(const Rect.fromLTWH(28,29,50,53),fill(face));
    canvas.drawOval(const Rect.fromLTWH(28,29,50,53),stroke);
    // Bangs: hand-drawn swoops varied for each character.
    final bang=Path()
      ..moveTo(26,46)..quadraticBezierTo(20,20,42,19)
      ..quadraticBezierTo(64,10,79,28)
      ..quadraticBezierTo(83,38,79,46)
      ..quadraticBezierTo(69,35,63,40)
      ..quadraticBezierTo(56,32,49,43)
      ..quadraticBezierTo(43,34,34,48)
      ..close();
    canvas.drawPath(bang,fill(hairColor));
    if(i%4==1){
      canvas.drawArc(const Rect.fromLTWH(34,22,38,21),0,math.pi,
        false,Paint()..color=const Color(0x77FFFFFF)
        ..strokeWidth=2..style=PaintingStyle.stroke);
    }
    // Eye variations: wink, sleeping, happy, surprised, bright-eyed.
    final expr=i%6;
    if(expr==0||expr==3){
      for(final x in [42.0,65.0]){
        final p=Path()..moveTo(x-5,56)..quadraticBezierTo(x,49,x+5,56);
        canvas.drawPath(p,Paint()..color=const Color(0xFF493640)
          ..style=PaintingStyle.stroke..strokeWidth=2.5
          ..strokeCap=StrokeCap.round);
      }
    }else{
      canvas.drawOval(const Rect.fromLTWH(36,50,9,13),fill(const Color(0xFF493640)));
      canvas.drawOval(const Rect.fromLTWH(60,50,9,13),fill(const Color(0xFF493640)));
      canvas.drawCircle(const Offset(40,54),2.2,fill(Colors.white));
      canvas.drawCircle(const Offset(64,54),2.2,fill(Colors.white));
      if(expr==2){
        canvas.drawLine(const Offset(60,57),const Offset(69,57),
          Paint()..color=face..strokeWidth=8);
        canvas.drawArc(const Rect.fromLTWH(59,52,11,7),0,math.pi,
          false,stroke);
      }
    }
    canvas.drawOval(const Rect.fromLTWH(31,64,13,5),
      fill(const Color(0x99EF8F9D)));
    canvas.drawOval(const Rect.fromLTWH(65,64,13,5),
      fill(const Color(0x99EF8F9D)));
    if(expr==1||expr==5){
      canvas.drawOval(const Rect.fromLTWH(48,66,8,7),
        fill(const Color(0xFFB96A72)));
    }else{
      final smile=Path()..moveTo(48,69)..quadraticBezierTo(53,73,58,69);
      canvas.drawPath(smile,stroke);
    }
    // Eyebrow and varied accessory combinations.
    if(i%5==0||i%5==3){
      canvas.drawLine(const Offset(35,48),const Offset(43,47),
        Paint()..color=hairColor..strokeWidth=1.5);
      canvas.drawLine(const Offset(62,47),const Offset(70,48),
        Paint()..color=hairColor..strokeWidth=1.5);
    }
    if(girl && i%4==0){
      // Bow with two loops and knot.
      final bow=Paint()..color=const Color(0xFFEB83A6);
      canvas.drawOval(const Rect.fromLTWH(70,16,14,12),bow);
      canvas.drawOval(const Rect.fromLTWH(84,16,12,12),bow);
      canvas.drawCircle(const Offset(84,22),4,fill(const Color(0xFFBB5477)));
    }else if(i%5==1){
      // Small coloured hair clip.
      canvas.save();canvas.translate(73,34);canvas.rotate(-.35);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5,-3,13,5),const Radius.circular(2)),
        fill(const Color(0xFFFFC572)));canvas.restore();
    }else if(!girl&&i%5==2){
      // Beanie with curved brim.
      final hat=Path()..moveTo(27,34)..quadraticBezierTo(28,9,52,8)
        ..quadraticBezierTo(77,10,80,34)..close();
      canvas.drawPath(hat,fill(const Color(0xFF678DAA)));
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(25,31,57,9),const Radius.circular(5)),
        fill(const Color(0xFF44718F)));
    }else if(i%7==4){
      // Round glasses.
      final glass=Paint()..color=const Color(0xFF6E607B)
        ..strokeWidth=2..style=PaintingStyle.stroke;
      canvas.drawOval(const Rect.fromLTWH(33,49,17,16),glass);
      canvas.drawOval(const Rect.fromLTWH(56,49,17,16),glass);
      canvas.drawLine(const Offset(50,56),const Offset(56,56),glass);
    }
    canvas.restore();
  }
  @override bool shouldRepaint(covariant _ChibiPainter old)=>old.id!=id;
}
