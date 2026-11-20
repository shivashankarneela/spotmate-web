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
  Future<Uint8List> bytes() async {
    final data = await _data;
    return data.buffer.asUint8List(data.offsetInBytes+offset,length);
  }
}
const _items = [
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
