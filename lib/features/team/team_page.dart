import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../workflow/workflow_text.dart';
import 'team_section.dart';
import '../work_activity/work_activity_page.dart';
class TeamPage extends StatefulWidget {
  const TeamPage({super.key,required this.appState,this.rankingOnly=false});
  final AppState appState;
  final bool rankingOnly;
  @override State<TeamPage> createState()=>_TeamPageState();
}
class _TeamPageState extends State<TeamPage> {
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)widget.appState.refreshTeamStats();});}
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.appState,builder:(context,_)=>
    RefreshIndicator(onRefresh:()=>widget.appState.refreshTeamStats(),child:ListView(
      physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,16,16,100),children:[
        Text(workflowText(context,widget.rankingOnly?'ratings':'team'),style:Theme.of(context).textTheme.headlineSmall),
        if (widget.rankingOnly) ...[
          const SizedBox(height: 8),
          const Text('Reyting faqat yakunlangan arizalar bo‘yicha aholi bergan haqiqiy baholardan hisoblanadi.'),
        ],
        if (widget.appState.teamStatsError != null) ...[
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Reytingni yangilab bo‘lmadi: ${widget.appState.teamStatsError}'),
            ),
          ),
        ],
        if (!widget.rankingOnly) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Vazifalar va hisobotlar')),
                body: WorkActivityPage(appState: widget.appState),
              ),
            )),
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('Ishchilarga vazifa berish va hisobotlarni ko‘rish'),
          ),
        ],
        const SizedBox(height:12),TeamSection(appState:widget.appState,ranking:widget.rankingOnly),
      ])));
}
