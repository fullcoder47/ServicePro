import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../features/workflow/workflow_text.dart';
import 'notification_service.dart';

Future<void> showNotificationInbox(BuildContext context, AppState state) =>
    showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_)=>_NotificationInbox(state:state));
class _NotificationInbox extends StatelessWidget {
  const _NotificationInbox({required this.state});
  final AppState state;
  @override Widget build(BuildContext context) => SafeArea(child:SizedBox(
    height:MediaQuery.sizeOf(context).height*.78,
    child:AnimatedBuilder(animation:state,builder:(context,_){
      final me=state.currentProfile;
      final groups=<String,ServiceNotification>{};
      final visible=state.notifications.where((n)=>n.profileId==me?.id ||
        (n.profileId==null && n.notificationType=='advertisement')).toList()
        ..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
      for(final item in visible){
        final key=item.notificationType=='advertisement' ? item.adGroupId??item.id : item.id;
        final existing=groups[key];
        if(existing==null || item.profileId==me?.id) groups[key]=item;
      }
      final items=groups.values.toList()..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
      final colors=Theme.of(context).colorScheme;
      return Column(children:[
        if(kIsWeb) Padding(
          padding:const EdgeInsets.fromLTRB(16,0,16,12),
          child:Card(child:ListTile(
            leading:const Icon(Icons.notifications_active_outlined),
            title:const Text('iPhone / Web bildirishnomalari'),
            subtitle:Text(NotificationService.webPushConfigured
              ? 'iPhone’da bosh ekranga o‘rnatilgan ilovada ruxsat bering.'
              : 'Firebase Web Push sozlamalari hali kiritilmagan.'),
            trailing:OutlinedButton(
              onPressed: !NotificationService.webPushConfigured ? null : () async {
                final success=await NotificationService.enableWebPush();
                if(!context.mounted)return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(success
                  ? 'Push bildirishnomalar yoqildi.'
                  : 'Ruxsat berilmadi yoki ro‘yxatdan o‘tish amalga oshmadi. '
                    'iPhone’da Safari orqali Bosh ekranga qo‘shing va qayta urinib ko‘ring.')));
              },
              child:const Text('Yoqish'),
            ),
          )),
        ),
        Padding(padding:const EdgeInsets.fromLTRB(20,0,12,12),child:Row(children:[
          Expanded(child:Text(state.tr('notifications'),style:Theme.of(context).textTheme.titleLarge)),
          IconButton(tooltip:workflowText(context,'all_read'),icon:const Icon(Icons.done_all),onPressed:() async {
            try {
              for(final item in items.where((n)=>n.profileId==me?.id && !n.isRead)) {
                await state.markNotificationRead(item);
              }
            } catch(_) {
              if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(state.tr('error_unknown'))));
            }
          }),
        ])),
        Expanded(child:RefreshIndicator(onRefresh:()=>state.refreshNotifications(),child:ListView.builder(
          physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,0,16,24),
          itemCount:items.isEmpty?1:items.length,itemBuilder:(context,index){
            if(items.isEmpty) return Padding(padding:const EdgeInsets.all(24),child:Text(state.tr('no_notifications')));
            final n=items[index];final unread=n.profileId==me?.id && !n.isRead;
            final kind=n.chatRoomId!=null?'chat':n.ticketId!=null?'tickets':n.notificationType=='advertisement'?'ads':n.notificationType.startsWith('work_')?'work_activity':'notifications';
            final icon=kind=='chat'?Icons.chat_bubble_outline:kind=='tickets'?Icons.assignment_outlined:kind=='ads'?Icons.campaign_outlined:kind=='work_activity'?Icons.fact_check_rounded:Icons.notifications_outlined;
            return Card(color:unread?colors.primaryContainer.withValues(alpha:.5):colors.surfaceContainerLow,
              margin:const EdgeInsets.only(bottom:10),child:InkWell(borderRadius:BorderRadius.circular(16),onTap:() async {
                try { await state.markNotificationRead(n); } catch(_) { /* Opening still works from the cached inbox. */ }
                if(!context.mounted)return;
                Navigator.pop(context);
                NotificationService.openData({'profile_id':n.profileId??'','type':n.notificationType,
                  'ticket_id':n.ticketId??'','chat_room_id':n.chatRoomId??'',
                  'chat_message_id':n.chatMessageId??'','notification_id':n.id,'ad_group_id':n.adGroupId??''});
              },child:Padding(padding:const EdgeInsets.all(14),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                CircleAvatar(backgroundColor:colors.primary.withValues(alpha:.12),child:Icon(icon,color:colors.primary)),
                const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(children:[Expanded(child:Text(state.tr(kind),style:TextStyle(color:colors.primary,fontSize:12))),
                    if(unread) Badge(label:Text(workflowText(context,'new')))]),
                  const SizedBox(height:5),Text(n.title,style:TextStyle(fontWeight:unread?FontWeight.w800:FontWeight.w600)),
                  const SizedBox(height:5),Text(n.body,maxLines:3,overflow:TextOverflow.ellipsis),
                  const SizedBox(height:8),Text(_date(n.createdAt.toLocal()),style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
                ])),const Icon(Icons.chevron_right,size:18),
              ]))),
            );
          },
        ))),
      ]);
    }),
  ));
  String _date(DateTime date){String two(int n)=>n.toString().padLeft(2,'0');return '${two(date.day)}.${two(date.month)}.${date.year} • ${two(date.hour)}:${two(date.minute)}';}
}
