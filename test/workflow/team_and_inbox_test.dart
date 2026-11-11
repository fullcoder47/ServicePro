import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/team/team_section.dart';
import 'package:servicepro/core/notifications/notification_inbox.dart';
import 'package:servicepro/core/notifications/notification_service.dart';
class InboxState extends AppState {
  InboxState():super.forTesting();
  @override Future<void> markNotificationRead(ServiceNotification item) async {item.isRead=true;notifyListeners();}
}
void main(){
  testWidgets('worker ranking sorts stars and hides other salaries',(tester)async{
    final state=AppState.forTesting();
    state.currentProfile=Profile.fromMap({'id':'me','role':'worker','company_id':'c'});
    state.teamStats.addAll([
      {'id':'me','first_name':'Ali','last_name':'Vali','job_title':'Plumber','star_total':5,'rating_count':1,'monthly_salary':2000,'completed_count':1},
      {'id':'other','first_name':'Bob','last_name':'Top','job_title':'Electrician','star_total':10,'rating_count':2,'monthly_salary':987654,'completed_count':2},
    ]);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:TeamSection(appState:state,ranking:true)))));
    expect(find.text('#1  Bob Top'),findsOneWidget);
    expect(find.textContaining('987654'),findsNothing);
    expect(find.textContaining('2000'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());state.dispose();
  });
  testWidgets('notification shows time and emits exact ticket destination',(tester)async{
    NotificationService.clearAccount(clearPending:true);
    final state=InboxState();state.currentProfile=Profile.fromMap({'id':'me','role':'user'});
    state.notifications.add(ServiceNotification.fromMap({'id':'n','profile_id':'me','ticket_id':'ticket-one',
      'title':'Request done','body':'Fixed','notification_type':'ticket_completed','created_at':'2026-10-13T10:30:00Z','is_read':false}));
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:
      TextButton(onPressed:()=>showNotificationInbox(context,state),child:const Text('Inbox'))))));
    await tester.tap(find.text('Inbox'));await tester.pumpAndSettle();
    expect(find.textContaining('13.10.2026'),findsOneWidget);
    await tester.tap(find.text('Request done'));await tester.pumpAndSettle();
    expect(NotificationService.pendingOpen.value?['ticket_id'],'ticket-one');
    expect(state.notifications.first.isRead,isTrue);
    await tester.pumpWidget(const SizedBox.shrink());state.dispose();NotificationService.clearAccount(clearPending:true);
  });
}
