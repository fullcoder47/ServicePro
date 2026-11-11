import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/app.dart';
import 'package:servicepro/core/theme/app_theme.dart';
import 'package:servicepro/core/widgets/app_route.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/super_admin/super_admin_page.dart';

class _TestState extends AppState {
  _TestState() : super.forTesting();

  int creates = 0;
  ({String name, String code})? created;

  @override
  bool get isConfigured => true;

  void useProfile(String id, UserRole role) {
    currentProfile = Profile.fromMap({
      'id': id,
      'role': role.dbValue,
      'first_name': id,
      'last_name': 'Test',
      'phone': '+998901234567',
    });
    selectedIndex = 0;
    notifyListeners();
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    currentProfile = profile;
    notifyListeners();
  }

  @override
  Future<void> refreshChatRooms({bool notify = true}) async {}

  @override
  Future<ChatRoom?> ensureGroupChat() async => null;

  @override
  Future<void> refreshNotifications({bool notify = true}) async {}

  @override
  Future<void> refreshBilling({bool notify = true}) async {}

  @override
  Future<void> ensureAllCompanySubscriptions() async {}

  @override
  Future<void> refreshScheduledNotifications({bool notify = true}) async {}

  @override
  Future<bool> createCompanyBySuperAdmin({
    required String name,
    required String joinPassword,
  }) async {
    creates++;
    created = (name: name, code: joinPassword);
    return true;
  }
}

class _TrackedAnimation extends Animation<double> {
  final _statusListeners = <AnimationStatusListener>{};
  final _listeners = <VoidCallback>{};

  int get statusListeners => _statusListeners.length;
  int get valueListeners => _listeners.length;

  @override
  double get value => 1;
  @override
  AnimationStatus get status => AnimationStatus.completed;
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  @override
  void addStatusListener(AnimationStatusListener listener) =>
      _statusListeners.add(listener);
  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      _statusListeners.remove(listener);
}

Future<void> _companies(WidgetTester tester, _TestState state) async {
  state.useProfile('super', UserRole.superAdmin);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SuperAdminCompaniesPage(appState: state)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openCompany(WidgetTester tester) async {
  await tester.tap(find.text('Yaratish'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

void main() {
  testWidgets('company cancel, back and barrier keep fields alive during pop',
      (tester) async {
    final state = _TestState();
    await _companies(tester, state);
    for (var dismissal = 0; dismissal < 3; dismissal++) {
      await _openCompany(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Test company');
      await tester.enterText(find.byType(TextFormField).last, 'test-code');
      if (dismissal == 0) {
        await tester.tap(find.text(state.tr('cancel')));
      } else if (dismissal == 1) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(8, 8));
      }
      // Inspect the reverse transition too, not only the settled frame.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(state.creates, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('company save validates and submits one copied draft', (tester) async {
    final state = _TestState();
    await _companies(tester, state);
    await _openCompany(tester);
    final save = find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(FilledButton));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(state.creates, 0);
    await tester.enterText(find.byType(TextFormField).first, ' Test company ');
    await tester.enterText(find.byType(TextFormField).last, ' test-code ');
    await tester.tap(save);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(state.creates, 1);
    expect(state.created, (name: 'Test company', code: 'test-code'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('theme and account changes retain one root navigator', (tester) async {
    final state = _TestState()..useProfile('resident', UserRole.user);
    await tester.pumpWidget(ServiceProApp.forTesting(appState: state));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    // This tests the root Navigator's identity across account/theme rebuilds.
    // Change the model directly: viewport placement of the theme dropdown is
    // covered by profile UI tests and should not make this lifecycle test flaky.
    state.setSelectedIndex(3);
    await tester.pumpAndSettle();
    state.currentProfile!.themeMode = ThemeMode.dark;
    await state.updateProfile(state.currentProfile!);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(state.currentProfile!.themeMode, ThemeMode.dark);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark);
    for (final identity in [
      (id: 'other-resident', role: UserRole.user),
      (id: 'manager', role: UserRole.admin),
      (id: 'manager', role: UserRole.director),
    ]) {
      state.useProfile(identity.id, identity.role);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.state<NavigatorState>(find.byType(Navigator)), same(navigator));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('route rebuilds and animation replacement release listeners',
      (tester) async {
    final first = _TrackedAnimation();
    final second = _TrackedAnimation();
    var animation = first;
    late StateSetter rebuild;
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return const SmoothPageTransitionsBuilder().buildTransitions(
          route, context, animation, const AlwaysStoppedAnimation<double>(0),
          const SizedBox());
      },
    )));
    for (var i = 0; i < 30; i++) {
      rebuild(() {});
      await tester.pump();
    }
    expect(first.statusListeners, 1);
    rebuild(() => animation = second);
    await tester.pump();
    expect(first.statusListeners, 0);
    expect(first.valueListeners, 0);
    expect(second.statusListeners, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.statusListeners, 0);
    expect(second.valueListeners, 0);
    expect(tester.takeException(), isNull);
    route.dispose();
  });

  testWidgets('company cancel can overlap a theme and account rebuild',
      (tester) async {
    final state = _TestState()..useProfile('super', UserRole.superAdmin);
    await tester.pumpWidget(ServiceProApp.forTesting(appState: state));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    state.setSelectedIndex(1);
    await tester.pumpAndSettle();
    await _openCompany(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Test company');
    await tester.tap(find.text(state.tr('cancel')));
    state.currentProfile!.themeMode = ThemeMode.dark;
    await state.updateProfile(state.currentProfile!);
    await tester.pump();
    expect(tester.takeException(), isNull);
    state.useProfile('resident', UserRole.user);
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.creates, 0);
    expect(tester.state<NavigatorState>(find.byType(Navigator)), same(navigator));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
