// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as web;
import 'package:flutter/material.dart';

Widget musicVideo(String id,int seconds,bool playing) =>
    _Video(key:ValueKey(id),id:id,seconds:seconds,playing:playing);

class _Video extends StatefulWidget {
  const _Video({super.key,required this.id,required this.seconds,required this.playing});
  final String id;
  final int seconds;
  final bool playing;
  @override
  State<_Video> createState()=>_VideoState();
}
class _VideoState extends State<_Video> {
  static const view='city-music-youtube';
  static bool registered=false;
  html.IFrameElement? frame;
  @override
  void initState(){
    super.initState();
    if(!registered){
      web.platformViewRegistry.registerViewFactory(view,(int id)=>html.IFrameElement()..style.border='0'..style.width='100%'..style.height='100%'..setAttribute('allow','autoplay; encrypted-media; fullscreen')..setAttribute('referrerpolicy','strict-origin-when-cross-origin'));
      registered=true;
    }
  }
  void sync(){
    frame?.src=Uri.https('www.youtube.com','/embed/${widget.id}',{'autoplay':widget.playing?'1':'0','start':widget.seconds.toString(),'playsinline':'1'}).toString();
  }
  @override
  void didUpdateWidget(_Video old){super.didUpdateWidget(old);if(old.playing!=widget.playing||old.id!=widget.id)sync();}
  @override
  Widget build(BuildContext context)=>HtmlElementView(viewType:view,onPlatformViewCreated:(id){frame=web.platformViewRegistry.getViewById(id) as html.IFrameElement;sync();});
}
