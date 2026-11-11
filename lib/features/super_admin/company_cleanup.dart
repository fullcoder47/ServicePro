import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../workflow/workflow_text.dart';
import '../chat/chat_page.dart';
class CompanyCleanupPanel extends StatefulWidget {
  const CompanyCleanupPanel({super.key,required this.state,required this.company});
  final AppState state;final Company company;
  @override State<CompanyCleanupPanel> createState()=>_CompanyCleanupPanelState();
}
class _CompanyCleanupPanelState extends State<CompanyCleanupPanel> {
  bool _busy=false;
  Future<void> _clear(String scope,{String? roomId}) async {
    final confirmed=await showDialog<bool>(context:context,builder:(_)=>_ConfirmCleanup(state:widget.state,company:widget.company));
    if(confirmed!=true || !mounted)return;
    setState(()=>_busy=true);
    final ok=await widget.state.cleanupCompany(widget.company,scope,roomId:roomId);
    if(!mounted)return;
    setState(()=>_busy=false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?workflowText(context,'cleanup_done'):widget.state.errorMessage??widget.state.tr('error_unknown'))));
  }
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.state,builder:(context,_)=>Card(child:Padding(
    padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(workflowText(context,'cleanup'),style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),Text(workflowText(context,'cleanup_warning')),
      const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[
        for(final scope in [('tickets',Icons.assignment_outlined),('ads',Icons.campaign_outlined),('chats',Icons.chat_outlined)])
          OutlinedButton.icon(onPressed:_busy?null:()=>_clear(scope.$1),icon:Icon(scope.$2),
            label:Text(scope.$1=='chats'?widget.state.tr('chat'):widget.state.tr(scope.$1))),
      ]),
      if(_busy)const LinearProgressIndicator(),
      const SizedBox(height:12),
      for(final room in widget.state.chatRooms.where((r)=>r.companyId==widget.company.id)) ListTile(
        contentPadding:EdgeInsets.zero,leading:const Icon(Icons.forum_outlined),title:Text(room.title),
        onTap:_busy?null:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ChatRoomPage(appState:widget.state,room:room,title:room.title))),
        trailing:IconButton(tooltip:workflowText(context,'clear_chat'),icon:const Icon(Icons.cleaning_services_outlined),
          onPressed:_busy?null:()=>_clear('chats',roomId:room.id)),
      ),
    ]),
  )));
}
class _ConfirmCleanup extends StatefulWidget {
  const _ConfirmCleanup({required this.state,required this.company});final AppState state;final Company company;
  @override State<_ConfirmCleanup> createState()=>_ConfirmCleanupState();
}
class _ConfirmCleanupState extends State<_ConfirmCleanup> {
  final _name=TextEditingController();
  @override void dispose(){_name.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.company.name),
    content:Column(mainAxisSize:MainAxisSize.min,children:[Text(workflowText(context,'cleanup_warning')),
      const SizedBox(height:12),TextField(controller:_name,onChanged:(_)=>setState((){}),decoration:InputDecoration(labelText:workflowText(context,'cleanup_confirm')))]),
    actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(widget.state.tr('cancel'))),
      FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(context).colorScheme.error),
        onPressed:_name.text.trim()!=widget.company.name?null:()=>Navigator.pop(context,true),child:Text(widget.state.tr('delete')))]);
}
