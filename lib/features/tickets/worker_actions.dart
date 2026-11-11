import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../workflow/workflow_text.dart';

Future<String?> chooseTicketWorker(BuildContext context, AppState state, Ticket ticket) async {
  if(state.currentProfile?.role==UserRole.worker)return state.currentProfile!.id;
  final workers=state.workersForCompany(ticket.companyId);
  if(workers.isEmpty){
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(workflowText(context,'no_worker'))));return null;
  }
  var chosen=workers.any((p)=>p.id==ticket.acceptedBy)?ticket.acceptedBy!:workers.first.id;
  return showDialog<String>(context:context,builder:(context)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
    title:Text(workflowText(context,'assign')),
    content:DropdownButtonFormField<String>(initialValue:chosen,isExpanded:true,
      items:workers.map((p)=>DropdownMenuItem(value:p.id,child:Text('${p.fullName} • ${p.jobTitle}',overflow:TextOverflow.ellipsis))).toList(),
      onChanged:(value){if(value!=null)update(()=>chosen=value);}),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(state.tr('cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(context,chosen),child:Text(state.tr('save')))],
  )));
}
Future<({int score,String comment})?> showWorkerReview(BuildContext context, AppState state) =>
  showDialog<({int score,String comment})>(context:context,builder:(_)=>_ReviewDialog(state:state));
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.state});final AppState state;
  @override State<_ReviewDialog> createState()=>_ReviewDialogState();
}
class _ReviewDialogState extends State<_ReviewDialog> {
  final _comment=TextEditingController();int _score=5;
  @override void dispose(){_comment.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(workflowText(context,'review')),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
      Wrap(children:[for(var i=1;i<=5;i++)IconButton(tooltip:'$i / 5',onPressed:()=>setState(()=>_score=i),
        icon:Icon(i<=_score?Icons.star_rounded:Icons.star_outline_rounded,color:Colors.amber,size:32))]),
      TextField(controller:_comment,maxLength:2000,maxLines:3,decoration:InputDecoration(labelText:workflowText(context,'comment'))),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(widget.state.tr('cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(context,(score:_score,comment:_comment.text)),child:Text(widget.state.tr('save')))]);
}
