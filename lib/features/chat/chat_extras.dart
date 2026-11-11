import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../core/notifications/notification_service.dart';
import 'chat_strings.dart';

const reactionEmojis = ['👍','❤️','😂','😮','😢','🙏','🔥','👏'];
class ChatExtras extends ChangeNotifier {
  ChatExtras(this.appState,this.roomId);
  final AppState appState;
  final String roomId;
  StreamSubscription<List<Map<String,dynamic>>>? _subscription;
  final _reactions = <String,ValueNotifier<List<Map<String,dynamic>>>>{};
  final _pending = <String>{};
  bool _disposed = false;
  bool ready = false;
  double textScale = 1;
  String wallpaper = 'default';
  DateTime? mutedUntil;
  bool get muted => mutedUntil?.isAfter(DateTime.now()) ?? false;
  ValueNotifier<List<Map<String,dynamic>>> reactions(String messageId) =>
      _reactions.putIfAbsent(messageId, () => ValueNotifier([]));
  Future<void> start() async {
    final uid = appState.currentProfile?.id;
    if (uid == null) return;
    try {
      final row = await appState.client.from('chat_preferences').select().eq('room_id',roomId).eq('profile_id',uid).maybeSingle();
      if (_disposed) return;
      if (row != null) {
        textScale=(row['text_scale'] as num?)?.toDouble() ?? 1;
        wallpaper='${row['wallpaper'] ?? 'default'}';
        mutedUntil=DateTime.tryParse('${row['muted_until']}');
      }
      NotificationService.setRoomMute(roomId,mutedUntil);
      _subscription = appState.client.from('chat_reactions').stream(primaryKey:['message_id','profile_id'])
        .eq('room_id',roomId).listen((rows) {
          if (_disposed) return;
          final grouped=<String,List<Map<String,dynamic>>>{};
          for(final row in rows) { grouped.putIfAbsent('${row['message_id']}',()=>[]).add(row); }
          for(final id in {..._reactions.keys,...grouped.keys}) {
            final next=grouped[id] ?? <Map<String,dynamic>>[];
            final current=reactions(id);
            if (_signature(current.value)!=_signature(next)) current.value=next;
          }
          if(!ready) { ready=true; notifyListeners(); }
        },onError:(_){ if(!_disposed) { ready=false; notifyListeners(); } });
      notifyListeners();
    } catch (_) { if(!_disposed) { ready=false; notifyListeners(); } }
  }
  String _signature(List<Map<String,dynamic>> rows) =>
    (rows.map((r)=>'${r['profile_id']}:${r['emoji']}').toList()..sort()).join('|');
  Future<void> react(String messageId,String emoji) async {
    if(!ready || _pending.contains(messageId)) return;
    final uid=appState.currentProfile?.id;
    if(uid==null) return;
    _pending.add(messageId);
    try {
      final rows=reactions(messageId).value;
      final remove=rows.any((r)=>r['profile_id']==uid && r['emoji']==emoji);
      await appState.client.rpc('servicepro_set_reaction',params:{'p_message_id':messageId,'p_room_id':roomId,'p_emoji':remove?null:emoji});
      if(_disposed) return;
      reactions(messageId).value=[...rows.where((r)=>r['profile_id']!=uid),
        if(!remove) {'message_id':messageId,'profile_id':uid,'room_id':roomId,'emoji':emoji}];
    } finally { _pending.remove(messageId); }
  }
  Future<void> save({required DateTime? mute,required double scale,required String background}) async {
    final uid=appState.currentProfile?.id;
    if(uid==null) return;
    await appState.client.from('chat_preferences').upsert({'room_id':roomId,'profile_id':uid,
      'muted_until':mute?.toUtc().toIso8601String(),'text_scale':scale,'wallpaper':background});
    if(_disposed) return;
    mutedUntil=mute;textScale=scale;wallpaper=background;
    NotificationService.setRoomMute(roomId,mute);
    notifyListeners();
  }
  @override
  void dispose() {
    _disposed=true;_subscription?.cancel();
    for(final value in _reactions.values) { value.dispose(); }
    super.dispose();
  }
}

class MessageReactions extends StatelessWidget {
  const MessageReactions({super.key,required this.extras,required this.messageId});
  final ChatExtras extras;
  final String messageId;
  @override Widget build(BuildContext context) => ValueListenableBuilder<List<Map<String,dynamic>>>(
    valueListenable:extras.reactions(messageId),builder:(context,rows,_) {
      final counts=<String,int>{};
      for(final row in rows) { final emoji='${row['emoji']}';counts[emoji]=(counts[emoji]??0)+1; }
      return Wrap(spacing:6,children:[for(final entry in counts.entries)
        ActionChip(label:Text('${entry.key} ${entry.value}'),
          backgroundColor:rows.any((r)=>r['profile_id']==extras.appState.currentProfile?.id && r['emoji']==entry.key)
            ? Theme.of(context).colorScheme.primaryContainer : null,
          onPressed:() async { try { await extras.react(messageId,entry.key); }
            catch (_) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(chatText(context,'reaction_error')))); } }),
      ]);
    });
}
