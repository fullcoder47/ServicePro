import '../workflow/workflow_text.dart';
import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../core/widgets/profile_avatar.dart';

class TeamSection extends StatelessWidget {
  const TeamSection({super.key, required this.appState, this.ranking=false});
  final bool ranking;
  final AppState appState;
  @override
  Widget build(BuildContext context) {
    final me = appState.currentProfile!;
    final colors = Theme.of(context).colorScheme;
    final items=List<Map<String,dynamic>>.of(appState.teamStats);
    if(ranking) items.sort((a,b) {
      final ratingA = (a['rating'] as num?)?.toDouble() ?? 0;
      final ratingB = (b['rating'] as num?)?.toDouble() ?? 0;
      final byAverage = ratingB.compareTo(ratingA);
      if (byAverage != 0) return byAverage;
      final countA = (a['rating_count'] as num?)?.toInt() ?? 0;
      final countB = (b['rating_count'] as num?)?.toInt() ?? 0;
      final byCount = countB.compareTo(countA);
      if (byCount != 0) return byCount;
      return '${a['first_name']} ${a['last_name']}'.compareTo('${b['first_name']} ${b['last_name']}');
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(appState.tr('our_team'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (appState.teamStats.isEmpty) Text(appState.tr('no_workers')),
      for (final item in items)
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProfileAvatar(profile: Profile.fromMap({...item, 'role': 'worker'}), radius: 26),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ranking ? '#${items.indexOf(item)+1}  ' : ''}${item['first_name']} ${item['last_name']}${me.id==item['id']?' ★':''}', style: Theme.of(context).textTheme.titleMedium),
              Text('${me.role == UserRole.superAdmin ? '${appState.companyById(item['company_id']?.toString())?.name ?? 'Tashkilot noma’lum'} • ' : ''}${item['job_title'] ?? ''}\n${item['phone']??''}', style: TextStyle(color: colors.onSurfaceVariant)),
            ])),
            if (!ranking && (me.role == UserRole.superAdmin || me.role == UserRole.director || me.role == UserRole.admin))
              IconButton(tooltip: appState.tr('worker_settings'), onPressed: () => _edit(context, item), icon: const Icon(Icons.edit_outlined)),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            Chip(avatar: Icon(item['busy'] == true ? Icons.pending_actions : Icons.check_circle_outline, size: 18), label: Text(appState.tr(item['busy'] == true ? 'worker_busy' : 'worker_available'))),
            Chip(avatar: const Icon(Icons.task_alt, size: 18), label: Text('${appState.tr('worker_jobs')}: ${item['completed_count']}')),
            Chip(avatar: const Icon(Icons.star_outline, size: 18), label: Text(item['rating'] == null ? appState.tr('no_rating') : '${item['rating']} / 5')),
          ]),
          Text('${workflowText(context,'stars')}: ${item['star_total']??0} • ${workflowText(context,'reviews')}: ${item['rating_count']??0}'),
          if (me.role == UserRole.superAdmin && (item['rating_count'] as num? ?? 0) > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showReviews(context, '${item['id']}', '${item['first_name']} ${item['last_name']}'),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Haqiqiy baholar va izohlar'),
              ),
            ),
          if (me.role != UserRole.user && (me.role != UserRole.worker || me.id == item['id']))
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('${appState.tr('worker_salary')}: ${item['monthly_salary'] ?? appState.tr('not_set')}')),
        ]))),
    ]);
  }
  Future<void> _edit(BuildContext context, Map<String, dynamic> item) =>
    showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>_WorkerEditor(state:appState,item:item));

  Future<void> _showReviews(BuildContext context, String workerId, String name) async {
    try {
      final rows = await appState.client
          .from('worker_ratings')
          .select('score, comment, created_at')
          .eq('worker_id', workerId)
          .order('created_at', ascending: false)
          .limit(50);
      if (!context.mounted) return;
      final reviews = (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$name — baholar'),
          content: SizedBox(
            width: 450,
            height: 380,
            child: reviews.isEmpty
                ? const Center(child: Text('Hozircha baho yo‘q.'))
                : ListView.separated(
                    itemCount: reviews.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      final score = (review['score'] as num?)?.toInt() ?? 0;
                      final date = DateTime.tryParse('${review['created_at'] ?? ''}')?.toLocal();
                      return ListTile(
                        dense: true,
                        title: Text('$score / 5 ⭐'),
                        subtitle: Text('${review['comment'] ?? ''}${date == null ? '' : '\n${date.day}.${date.month}.${date.year}'}'),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Yopish'))],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Baholarni yuklab bo‘lmadi: ${appState.friendlyError('$error')}'),
      ));
    }
  }
}
class _WorkerEditor extends StatefulWidget {
  const _WorkerEditor({required this.state,required this.item});
  final AppState state;final Map<String,dynamic> item;
  @override State<_WorkerEditor> createState()=>_WorkerEditorState();
}
class _WorkerEditorState extends State<_WorkerEditor> {
  late final TextEditingController _job,_salary;bool _saving=false;
  @override void initState(){super.initState();_job=TextEditingController(text:'${widget.item['job_title']??''}');_salary=TextEditingController(text:widget.item['monthly_salary']?.toString()??'');}
  @override void dispose(){_job.dispose();_salary.dispose();super.dispose();}
  Future<void> _save() async {
    if(_saving)return;
    final raw=_salary.text.trim();final amount=raw.isEmpty?null:double.tryParse(raw.replaceAll(',','.'));
    if(_job.text.trim().isEmpty || (raw.isNotEmpty && (amount==null || !amount.isFinite || amount<0))){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.state.tr('fill_required'))));return;
    }
    setState(()=>_saving=true);
    final ok=await widget.state.setWorkerDetails('${widget.item['id']}',_job.text,amount);
    if(!mounted)return;
    setState(()=>_saving=false);
    if(ok){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}
    else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.state.errorMessage??widget.state.tr('error_unknown'))));
    }
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!_saving,child:AlertDialog(
    title:Text(widget.state.tr('worker_settings')),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:_job,enabled:!_saving,decoration:InputDecoration(labelText:widget.state.tr('job_title'))),
      const SizedBox(height:14),TextField(controller:_salary,enabled:!_saving,keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:'${widget.state.tr('worker_salary')} (UZS)')),
    ]),actions:[TextButton(onPressed:_saving?null:()=>Navigator.pop(context),child:Text(widget.state.tr('cancel'))),
      FilledButton(onPressed:_saving?null:_save,child:Text(widget.state.tr('save')))]));
}
