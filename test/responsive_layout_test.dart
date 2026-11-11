import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/onboarding/guest_shell.dart';
import 'package:servicepro/features/shell/home_shell.dart';
import 'package:servicepro/features/auth/splash_page.dart';

class _OfflineUiState extends AppState {
  _OfflineUiState() : super.forTesting();

  void signInAsResident() {
    currentProfile = Profile.fromMap({
      'id': 'test-resident',
      'role': 'user',
      'first_name': 'Test',
      'last_name': 'Resident',
    });
    notifyListeners();
  }

  @override
  Future<void> refreshChatRooms({bool notify = true}) async {}

  @override
  Future<ChatRoom?> ensureGroupChat() async => null;
}

void main() {
  Future<void> setWindow(WidgetTester tester, double width, double height) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    await tester.pump();
  }

  testWidgets('guest keeps accessible navigation on a phone', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setWindow(tester, 390, 844);
    final state = _OfflineUiState();
    await tester.pumpWidget(MaterialApp(home: GuestShell(appState: state)));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('splash renders after its short entrance animation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    // The indeterminate progress indicator animates until splash is removed.
    // Pump a fixed interval instead of pumpAndSettle here.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('ServicePro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resident ticket button stays clear of bottom navigation',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setWindow(tester, 390, 844);
    final state = _OfflineUiState()..signInAsResident();
    state.setSelectedIndex(1);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: HomeShell(appState: state),
    ));
    await tester.pump();
    final button = find.byType(FloatingActionButton);
    expect(button, findsOneWidget);
    expect(tester.getBottomRight(button).dy, lessThan(844 - 64));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('horizontal swipe selects next phone navigation item',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setWindow(tester, 390, 844);
    final state = _OfflineUiState()..signInAsResident();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: HomeShell(appState: state),
    ));
    await tester.pump();
    await tester.fling(find.byType(IndexedStack), const Offset(-280, 0), 1200);
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.selectedIndex, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('guest keeps the sidebar on a laptop', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setWindow(tester, 1366, 768);
    final state = _OfflineUiState();
    await tester.pumpWidget(MaterialApp(home: GuestShell(appState: state)));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('ServicePro'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('resident gets transparent navigation on Android phone',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await setWindow(tester, 390, 844);
    final state = _OfflineUiState()..signInAsResident();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: HomeShell(appState: state),
    ));
    await tester.pump();
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody, isTrue);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('desktop and tablet keep opaque navigation surfaces',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _OfflineUiState()..signInAsResident();
    await setWindow(tester, 800, 1100);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: HomeShell(appState: state),
    ));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody, isFalse);
    expect(tester.takeException(), isNull);

    await setWindow(tester, 1366, 768);
    await tester.pump();
    expect(find.text('ServicePro • Desktop'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
