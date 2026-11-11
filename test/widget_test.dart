import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/onboarding/guest_shell.dart';

void main() {
  test('legacy resident profile still defaults to system theme', () {
    final profile = Profile.fromMap({'id': 'existing', 'role': 'user', 'first_name': 'Ali'});
    expect(profile.themeMode, ThemeMode.system);
    expect(profile.homeAddress, isEmpty);
    expect(profile.role, UserRole.user);
  });
  test('worker role and job title round trip without becoming resident', () {
    final worker = Profile.fromMap({'id': 'worker', 'role': 'worker', 'job_title': 'Elektrik'});
    expect(worker.role, UserRole.worker);
    expect(worker.role.dbValue, 'worker');
    expect(worker.jobTitle, 'Elektrik');
  });
  testWidgets('first install opens navigation without requesting credentials', (tester) async {
    final state = AppState.forTesting();
    await tester.pumpWidget(MaterialApp(home: GuestShell(appState: state)));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('ServicePro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  testWidgets('guest profile exposes organization access and system theme', (tester) async {
    final state = AppState.forTesting();
    await tester.pumpWidget(MaterialApp(home: GuestShell(appState: state)));
    await tester.tap(find.byIcon(Icons.person_outline).last);
    await tester.pumpAndSettle();
    expect(find.text(state.tr('organization_access')), findsOneWidget);
    expect(state.themeMode, ThemeMode.system);
    expect(find.byType(DropdownButtonFormField<ThemeMode>), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  test('session reset clears private data on account switch', () {
    final state = AppState.forTesting();
    state.profiles.add(Profile.fromMap({'id': 'old', 'role': 'user'}));
    state.currentProfile = state.profiles.first;
    state.teamStats.add({'monthly_salary': 100});
    state.clearSessionData();
    expect(state.currentProfile, isNull);
    expect(state.profiles, isEmpty);
    expect(state.teamStats, isEmpty);
    state.dispose();
  });
}
