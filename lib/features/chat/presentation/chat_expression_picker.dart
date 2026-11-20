import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
class ChatExpression {
  const ChatExpression(this.path,this.symbol,this.offset,this.length);
  final String path,symbol;
  final int offset,length;
  String get title => path.split('/').last.split('.').first.replaceAll('-',' ');
  String get ext => path.split('.').last;
  String get mime => ext == 'gif' ? 'image/gif' : 'image/png';
  static final _data = rootBundle.load('assets/media/chat-pack.bin');
  static final _community = rootBundle.load('assets/media/community.bin');
  static final _extra = rootBundle.load('assets/media/extra.bin');
  Future<Uint8List> bytes() async {
    final data = await (path.contains('/more/') ? _extra : path.startsWith('stickers/community/') ? _community : _data);
    return data.buffer.asUint8List(data.offsetInBytes+offset,length);
  }
}
const _items = [
  ChatExpression('gifs/more/partying.gif','',0,53464),
  ChatExpression('stickers/more/partying.png','',53464,8568),
  ChatExpression('gifs/more/star-struck.gif','',62032,57434),
  ChatExpression('stickers/more/star-struck.png','',119466,11390),
  ChatExpression('gifs/more/rolling-laugh.gif','',130856,30746),
  ChatExpression('stickers/more/rolling-laugh.png','',161602,10586),
  ChatExpression('gifs/more/smiling-hearts.gif','',172188,52783),
  ChatExpression('stickers/more/smiling-hearts.png','',224971,10949),
  ChatExpression('gifs/more/mind-blown.gif','',235920,65532),
  ChatExpression('stickers/more/mind-blown.png','',301452,8153),
  ChatExpression('gifs/more/hug.gif','',309605,61101),
  ChatExpression('stickers/more/hug.png','',370706,12458),
  ChatExpression('gifs/more/freezing.gif','',383164,64023),
  ChatExpression('stickers/more/freezing.png','',447187,12388),
  ChatExpression('gifs/more/hot-face.gif','',459575,47626),
  ChatExpression('stickers/more/hot-face.png','',507201,11719),
  ChatExpression('gifs/more/sobbing.gif','',518920,57563),
  ChatExpression('stickers/more/sobbing.png','',576483,11072),
  ChatExpression('gifs/more/unimpressed.gif','',587555,59847),
  ChatExpression('stickers/more/unimpressed.png','',647402,9759),
  ChatExpression('gifs/more/eye-roll.gif','',657161,61680),
  ChatExpression('stickers/more/eye-roll.png','',718841,9285),
  ChatExpression('gifs/more/smirking.gif','',728126,36997),
  ChatExpression('stickers/more/smirking.png','',765123,9749),
  ChatExpression('gifs/more/sleeping.gif','',774872,49150),
  ChatExpression('stickers/more/sleeping.png','',824022,10241),
  ChatExpression('gifs/more/shushing.gif','',834263,47136),
  ChatExpression('stickers/more/shushing.png','',881399,10895),
  ChatExpression('gifs/more/flushed.gif','',892294,49072),
  ChatExpression('stickers/more/flushed.png','',941366,10161),
  ChatExpression('gifs/more/surprised.gif','',951527,45127),
  ChatExpression('stickers/more/surprised.png','',996654,8608),
  ChatExpression('gifs/more/yummy.gif','',1005262,35092),
  ChatExpression('stickers/more/yummy.png','',1040354,9655),
  ChatExpression('gifs/more/wink-tongue.gif','',1050009,33469),
  ChatExpression('stickers/more/wink-tongue.png','',1083478,9845),
  ChatExpression('gifs/more/angel.gif','',1093323,77796),
  ChatExpression('stickers/more/angel.png','',1171119,10928),
  ChatExpression('gifs/more/skull.gif','',1182047,75153),
  ChatExpression('stickers/more/skull.png','',1257200,7919),
  ChatExpression('gifs/more/ghost.gif','',1265119,42360),
  ChatExpression('stickers/more/ghost.png','',1307479,6137),
  ChatExpression('gifs/more/little-devil.gif','',1313616,69901),
  ChatExpression('stickers/more/little-devil.png','',1383517,10387),
  ChatExpression('gifs/more/giggle.gif','',1393904,47533),
  ChatExpression('stickers/more/giggle.png','',1441437,11221),
  ChatExpression('gifs/more/nerd.gif','',1452658,65998),
  ChatExpression('stickers/more/nerd.png','',1518656,12155),
  ChatExpression('gifs/more/pleading.gif','',1530811,91815),
  ChatExpression('stickers/more/pleading.png','',1622626,11054),
  ChatExpression('stickers/community/playful-pup.png','',0,27830),
  ChatExpression('stickers/community/resting-pup.png','',27830,15766),
  ChatExpression('stickers/community/happy-pup.png','',43596,22133),
  ChatExpression('stickers/community/curious-pup.png','',65729,22269),
  ChatExpression('stickers/community/sleepy-pup.png','',87998,37382),
  ChatExpression('stickers/community/stretching-pup.png','',125380,22160),
  ChatExpression('stickers/community/helpful-pup.png','',147540,26760),
  ChatExpression('stickers/community/hungry-pup.png','',174300,33886),
  ChatExpression('stickers/community/space-rocket.png','',208186,46169),
  ChatExpression('stickers/community/floating-astronaut.png','',254355,36264),
  ChatExpression('stickers/community/saturn.png','',290619,54446),
  ChatExpression('stickers/community/flying-saucer.png','',345065,39627),
  ChatExpression('stickers/community/kawaii-cat.png','',384692,42992),
  ChatExpression('stickers/community/kawaii-rainbow.png','',427684,37367),
  ChatExpression('stickers/community/kawaii-bear.png','',465051,39420),
  ChatExpression('stickers/community/kawaii-cone.png','',504471,29306),
  ChatExpression('stickers/community/kawaii-diamond.png','',533777,50208),
  ChatExpression('gifs/face-with-tears-of-joy.gif','😂',0,68936),
  ChatExpression('stickers/face-with-tears-of-joy.png','😂',68936,19084),
  ChatExpression('gifs/smiling-face-with-heart-eyes.gif','😍',88020,48415),
  ChatExpression('stickers/smiling-face-with-heart-eyes.png','😍',136435,18541),
  ChatExpression('gifs/fire.gif','🔥',154976,23838),
  ChatExpression('stickers/fire.png','🔥',178814,11391),
  ChatExpression('gifs/party-popper.gif','🎉',190205,34118),
  ChatExpression('stickers/party-popper.png','🎉',224323,18439),
  ChatExpression('gifs/crying-face.gif','😢',242762,50607),
  ChatExpression('stickers/crying-face.png','😢',293369,18942),
  ChatExpression('gifs/clapping-hands.gif','👏',312311,17990),
  ChatExpression('stickers/clapping-hands.png','👏',330301,14612),
  ChatExpression('gifs/thumbs-up.gif','👍',344913,16575),
  ChatExpression('stickers/thumbs-up.png','👍',361488,12348),
  ChatExpression('gifs/smiling-face-with-sunglasses.gif','😎',373836,55577),
  ChatExpression('stickers/smiling-face-with-sunglasses.png','😎',429413,20348),
  ChatExpression('gifs/face-blowing-a-kiss.gif','😘',449761,49285),
  ChatExpression('stickers/face-blowing-a-kiss.png','😘',499046,19923),
  ChatExpression('gifs/thinking-face.gif','🤔',518969,62101),
  ChatExpression('stickers/thinking-face.png','🤔',581070,19731),
  ChatExpression('gifs/folded-hands.gif','🙏',600801,19852),
  ChatExpression('stickers/folded-hands.png','🙏',620653,9960),
  ChatExpression('gifs/waving-hand.gif','👋',630613,36527),
  ChatExpression('stickers/waving-hand.png','👋',667140,14747),
  ChatExpression('emoji/face-with-tears-of-joy.png','😂',681887,18615),
  ChatExpression('emoji/smiling-face-with-heart-eyes.png','😍',700502,15804),
  ChatExpression('emoji/fire.png','🔥',716306,10944),
  ChatExpression('emoji/party-popper.png','🎉',727250,7217),
  ChatExpression('emoji/crying-face.png','😢',734467,14014),
  ChatExpression('emoji/clapping-hands.png','👏',748481,13215),
  ChatExpression('emoji/thumbs-up.png','👍',761696,10317),
  ChatExpression('emoji/smiling-face-with-sunglasses.png','😎',772013,15143),
  ChatExpression('emoji/face-blowing-a-kiss.png','😘',787156,15695),
  ChatExpression('emoji/thinking-face.png','🤔',802851,18302),
  ChatExpression('emoji/folded-hands.png','🙏',821153,9726),
  ChatExpression('emoji/waving-hand.png','👋',830879,14920),
];
Future<ChatExpression?> chooseChatExpression(BuildContext context) {
  return showModalBottomSheet<ChatExpression>(context:context,showDragHandle:true,
    builder:(sheet)=>DefaultTabController(length:3,child:SafeArea(child: Column(children:[
      const TabBar(tabs:[Tab(text:'Emoji'), Tab(text:'GIFs'), Tab(text:'Stickers')]),
      Expanded(child:TabBarView(children:[
        for(final category in ['emoji','gifs','stickers'])
          GridView.count(crossAxisCount:4,padding:const EdgeInsets.all(8),children:[
            for(final item in _items.where((v)=>v.path.startsWith('$category/')))
              IconButton(tooltip:item.title,onPressed:()=>Navigator.pop(sheet,item),
                icon:FutureBuilder<Uint8List>(future:item.bytes(),builder:(_,snap)=>
                  snap.hasData ? Image.memory(snap.data!,fit:BoxFit.contain) : Text(item.symbol))),
          ]),
      ])),
    ]))));
}
