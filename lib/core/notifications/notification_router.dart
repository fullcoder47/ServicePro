import '../../data/models.dart';
import '../../features/team/team_page.dart';
import '../../features/work_activity/work_activity_page.dart';
import '../../features/workflow/workflow_text.dart';
import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../features/chat/chat_page.dart';
import '../../features/tickets/tickets_page.dart';
import '../widgets/media_viewer.dart';
import 'notification_service.dart';

class NotificationRouter extends StatefulWidget {
  const NotificationRouter({super.key,required this.appState,required this.child});
  final AppState appState;
  final Widget child;
  @override State<NotificationRouter> createState()=>_NotificationRouterState();
}
class _NotificationRouterState extends State<NotificationRouter> {
  bool _opening=false;
  @override void initState() {
    super.initState();NotificationService.pendingOpen.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_)=>_changed());
  }
  @override void dispose() { NotificationService.pendingOpen.removeListener(_changed);super.dispose(); }
  void _changed() { if(mounted && !_opening) _open(); }
  Future<void> _open() async {
    final data=NotificationService.pendingOpen.value;
    final me=widget.appState.currentProfile;
    if(data==null || me==null) return;
    NotificationService.pendingOpen.value=null;
    if((data['profile_id']??'').isNotEmpty && data['profile_id']!=me.id) return;
    _opening=true;
    try {
      Navigator.of(context).popUntil((route)=>route.isFirst);
      final roomId=data['chat_room_id'];
      final ticketId=data['ticket_id'];
      if(roomId!=null && roomId.isNotEmpty) {
        await widget.appState.refreshChatRooms();
        final matches=widget.appState.chatRooms.where((room)=>room.id==roomId);
        if(mounted && matches.isEmpty) _unavailable();
        if(mounted && matches.isNotEmpty) {
          final room=matches.first;
          await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ChatRoomPage(appState:widget.appState,room:room,title:room.title)));
        }
      } else if(ticketId!=null && ticketId.isNotEmpty) {
        await widget.appState.refreshTickets();
        final matches=widget.appState.tickets.where((ticket)=>ticket.id==ticketId);
        if(mounted && matches.isEmpty) _unavailable();
        if(mounted && matches.isNotEmpty) await showTicketDetails(context,widget.appState,matches.first);
      } else if(data['type']=='worker_updated' && mounted) {
        await widget.appState.refreshTeamStats();
        if(mounted)await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>TeamPage(appState:widget.appState,rankingOnly:widget.appState.currentProfile?.role.dbValue=='worker')));
      } else if((data['type'] ?? '').startsWith('work_') && mounted) {
        if(widget.appState.currentProfile?.role == UserRole.worker ||
            widget.appState.currentProfile?.role == UserRole.director ||
            widget.appState.currentProfile?.role == UserRole.admin) {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
            Scaffold(appBar: AppBar(title: const Text('Vazifalar va hisobotlar')),
              body: WorkActivityPage(appState: widget.appState))));
        }
      } else if(mounted) {
        await widget.appState.refreshNotifications();
        final matches=widget.appState.notifications.where((item)=>item.id==data['notification_id'] ||
          ((data['ad_group_id']??'').isNotEmpty && item.adGroupId==data['ad_group_id']));
        if(mounted && matches.isEmpty) _unavailable();
        if(mounted && matches.isNotEmpty) {
          final item=matches.first;
          await showDialog<void>(context:context,builder:(_)=>MediaViewerDialog(title:item.title,body:item.body,
            mediaUrls:item.mediaUrls,mediaTypes:item.mediaTypes,
            actionUrl:item.actionUrl,actionLabel:item.actionLabel));
        }
      }
    } catch(_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.appState.tr('error_unknown'))));
    } finally { _opening=false;if(mounted && NotificationService.pendingOpen.value!=null) _changed(); }
  }
  void _unavailable(){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(workflowText(context,'notification_missing'))));}
  @override Widget build(BuildContext context)=>widget.child;
}
