import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'ticket_text.dart';

/// Preview the picker-owned local file without another copy of the video bytes.
class PickedVideoPreview extends StatefulWidget {
  const PickedVideoPreview({super.key,required this.path});
  final String path;
  @override State<PickedVideoPreview> createState()=>_PickedVideoPreviewState();
}
class _PickedVideoPreviewState extends State<PickedVideoPreview> {
  late final VideoPlayerController _video;
  bool _ready=false,_failed=false;
  @override void initState() {
    super.initState();
    _video=VideoPlayerController.file(File(widget.path));
    _video.initialize().then((_) { if(mounted) setState(()=>_ready=true); })
      .catchError((Object _) { if(mounted) setState(()=>_failed=true); });
  }
  @override void dispose() { _video.dispose();super.dispose(); }
  @override Widget build(BuildContext context) {
    if(_failed) return Padding(padding:const EdgeInsets.all(24),child:Text(ticketText(context,'media_error')));
    if(!_ready) return const Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator.adaptive());
    return Column(mainAxisSize:MainAxisSize.min,children:[
      AspectRatio(aspectRatio:_video.value.aspectRatio>0?_video.value.aspectRatio:16/9,child:VideoPlayer(_video)),
      VideoProgressIndicator(_video,allowScrubbing:true,padding:const EdgeInsets.all(12)),
      ValueListenableBuilder<VideoPlayerValue>(valueListenable:_video,builder:(context,value,_)=>
        IconButton(onPressed:()=>value.isPlaying?_video.pause():_video.play(),
          icon:Icon(value.isPlaying?Icons.pause_circle_filled_rounded:Icons.play_circle_fill_rounded,size:40))),
    ]);
  }
}
