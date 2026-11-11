import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/billing/billing_page.dart';

class _FakeBillingState extends AppState {
  _FakeBillingState() : super.forTesting();

  void setRoleAndStatus(UserRole role, SubscriptionStatus status) {
    currentProfile = Profile.fromMap({
      'id': '11111111-1111-1111-1111-111111111111',
      'company_id': '22222222-2222-2222-2222-222222222222',
      'role': role.dbValue,
      'first_name': 'Test',
      'last_name': 'User',
    });
    subscriptions
      ..clear()
      ..add(CompanySubscription.fromMap({
        'id': '33333333-3333-3333-3333-333333333333',
        'company_id': currentProfile!.companyId,
        'status': status.dbValue,
        'created_at': '2026-10-16T10:00:00Z',
        'updated_at': '2026-10-16T10:00:00Z',
      }));
    notifyListeners();
  }
}

void main() {
  test('only blocked directors/admins/workers are gated', () {
    final state = _FakeBillingState();
    for (final role in [UserRole.director, UserRole.admin, UserRole.worker]) {
      state.setRoleAndStatus(role, SubscriptionStatus.blocked);
      expect(state.isBillingBlocked, true);
      state.setRoleAndStatus(role, SubscriptionStatus.active);
      expect(state.isBillingBlocked, false);
    }
    for (final role in [UserRole.superAdmin, UserRole.user]) {
      state.setRoleAndStatus(role, SubscriptionStatus.blocked);
      expect(state.isBillingBlocked, false);
    }
    state.dispose();
  });

  testWidgets('blocking blurs and disables the underlying screen', (tester) async {
    final state = _FakeBillingState()
      ..setRoleAndStatus(UserRole.director, SubscriptionStatus.blocked);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: BillingAccessGate(
        appState: state,
        child: Scaffold(
          body: Center(child: FilledButton(
            onPressed: () => taps++,
            child: const Text('Behind lock'),
          )),
        ),
      ),
    ));
    expect(find.text('Tashkilot vaqtincha bloklangan'), findsOneWidget);
    await tester.tap(find.text('Behind lock'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('after an unblock the existing UI remains interactive', (tester) async {
    final state = _FakeBillingState()
      ..setRoleAndStatus(UserRole.director, SubscriptionStatus.blocked);
    var taps = 0;
    Widget widget() => MaterialApp(
      home: BillingAccessGate(
        appState: state,
        child: Scaffold(
          body: Center(child: FilledButton(
            onPressed: () => taps++,
            child: const Text('Dashboard'),
          )),
        ),
      ),
    );
    await tester.pumpWidget(widget());
    expect(find.text('Tashkilot vaqtincha bloklangan'), findsOneWidget);
    state.setRoleAndStatus(UserRole.director, SubscriptionStatus.active);
    await tester.pumpWidget(widget());
    expect(find.text('Tashkilot vaqtincha bloklangan'), findsNothing);
    await tester.tap(find.text('Dashboard'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
