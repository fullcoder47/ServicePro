import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/onboarding/access_page.dart';
import 'package:servicepro/features/tickets/ticket_profile_editor.dart';

// Extension methods cannot be overridden: this test deliberately leaves the
// Supabase client unconfigured and exercises the directory failure state too.
void main() {
  testWidgets('access mode switches preserve distinct form field state', (tester) async {
    final state = AppState.forTesting();
    await tester.pumpWidget(MaterialApp(home: AccessPage(appState: state)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('first_name')), 'Ali');
    await tester.tap(find.text(state.tr('login')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('first_name')), findsNothing);
    await tester.tap(find.text(state.tr('first_access')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('first_name')), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('contact sheet can close and reopen during route transition', (tester) async {
    final state = AppState.forTesting();
    state.currentProfile = Profile.fromMap({
      'id': 'resident', 'role': 'user', 'first_name': 'Ali',
    });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => editTicketProfile(context, state), child: const Text('Open')),
    ))));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Form), findsOneWidget);
      final sheetContext = tester.element(find.byType(Form));
      Navigator.of(sheetContext).pop();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
