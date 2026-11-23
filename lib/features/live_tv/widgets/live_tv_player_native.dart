import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/live_tv_models.dart';
class LiveTvPlayer extends StatelessWidget {
 const LiveTvPlayer({super.key,required this.channel,this.commands});
 final LiveTvChannel channel;
 final ValueNotifier<String?>? commands;
 @override Widget build(BuildContext context)=>Center(child:FilledButton.icon(icon:const Icon(Icons.play_arrow),label:const Text('Open player'),onPressed:()async{final uri=Uri.tryParse(channel.streamType=='hls'?channel.streamSource:channel.streamType=='youtube_channel'?'https://www.youtube.com/channel/${channel.streamSource}/live':'https://www.youtube.com/watch?v=${channel.streamSource}');if(uri!=null && uri.scheme=='https')await launchUrl(uri); }));
}
