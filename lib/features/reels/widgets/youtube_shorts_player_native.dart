import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class YouTubeShortsPlayer extends StatelessWidget {
 const YouTubeShortsPlayer({super.key,required this.youtubeVideoId,required this.thumbnailUrl,required this.isActive,required this.isMuted});
 final String youtubeVideoId;
 final String thumbnailUrl;
 final bool isActive;
 final bool isMuted;
 @override Widget build(BuildContext context)=>Center(child:FilledButton.icon(icon:const Icon(Icons.play_arrow),label:const Text('Open player'),onPressed:()async{final uri=Uri.tryParse('https://www.youtube.com/shorts/$youtubeVideoId');if(uri!=null && uri.scheme=='https')await launchUrl(uri); }));
}
