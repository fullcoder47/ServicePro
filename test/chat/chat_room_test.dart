import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepro/data/app_state.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/chat/chat_page.dart';

class ChatStateFake extends AppState {
  ChatStateFake() : super.forTesting() {
    currentProfile = Profile(id: 'me', role: UserRole.user,
      firstName: 'Ali', lastName: 'Valiyev', phone: '', email: '', companyId: 'company');
  }
  int readCalls = 0;
  int sendCalls = 0;
  Completer<bool>? pendingSend;
  @override
  Future<void> watchChatRoom(ChatRoom room) async { activeChatRoomId = room.id; notifyListeners(); }
  @override
  Future<void> stopWatchingChatRoom(String roomId) async {}
  @override
  Future<void> setChatTyping(String roomId, bool isTyping) async {}
  @override
  Future<void> markChatRoomAsRead(String roomId) async { readCalls++; notifyListeners(); }
  @override
  Future<bool> sendChatMessage({required String roomId, required String text,
      required List<PickedAttachment> attachments, String? replyToMessageId}) async {
    sendCalls++;
    return pendingSend == null ? false : await pendingSend!.future;
  }
  void receive(ChatMessage message) {
    activeChatMessages.add(message);
    chatRevision++;
    notifyListeners();
  }
}

final room = ChatRoom(id: 'room', companyId: 'company', type: ChatRoomType.group,
  title: 'BIG SCAN AS PLYUS', createdAt: DateTime(2026));
ChatMessage message(int index, {String roomId = 'room'}) => ChatMessage(
  id: 'message_$index', roomId: roomId, senderId: 'other', text: 'Message $index',
  createdAt: DateTime(2026, 10, 10, 10).add(Duration(minutes: index)),
);
Future<void> open(WidgetTester tester, ChatStateFake state) async {
  await tester.pumpWidget(MaterialApp(home: ChatRoomPage(appState: state, room: room, title: room.title)));
  await tester.pumpAndSettle();
}
Future<void> close(WidgetTester tester, ChatStateFake state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  state.dispose();
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('long history opens at newest message and read updates settle', (tester) async {
    final state = ChatStateFake();
    state.activeChatMessages.addAll(List.generate(200, message));
    await open(tester, state);
    expect(find.text('Message 199'), findsOneWidget);
    expect(find.text('Message 0'), findsNothing);
    expect(state.readCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(state.readCalls, 1);
    state.receive(message(200));
    await tester.pumpAndSettle();
    expect(find.text('Message 200'), findsOneWidget);
    expect(state.readCalls, 2);
    await close(tester, state);
  });
  testWidgets('history reader can return to latest with the floating button', (tester) async {
    final state = ChatStateFake();
    state.activeChatMessages.addAll(List.generate(100, message));
    await open(tester, state);
    await tester.drag(find.byType(ListView).first, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Oxirgi xabarga o‘tish'), findsOneWidget);
    state.receive(message(100));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Oxirgi xabarga o‘tish'), findsOneWidget);
    await tester.tap(find.byTooltip('Oxirgi xabarga o‘tish'));
    await tester.pumpAndSettle();
    expect(find.text('Message 100'), findsOneWidget);
    await close(tester, state);
  });
  testWidgets('messages from another room never appear', (tester) async {
    final state = ChatStateFake();
    state.activeChatMessages.add(message(1, roomId: 'other-room'));
    await open(tester, state);
    expect(find.text('Message 1'), findsNothing);
    await close(tester, state);
  });
  testWidgets('failed send preserves draft and blocks duplicate submission', (tester) async {
    final state = ChatStateFake()..pendingSend = Completer<bool>();
    await open(tester, state);
    await tester.enterText(find.byType(TextField), 'Please fix the light');
    await tester.pump();
    await tester.tap(find.byTooltip('Yuborish'));
    await tester.pump();
    await tester.tap(find.byTooltip('Yuborish'));
    expect(state.sendCalls, 1);
    state.pendingSend!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Please fix the light'), findsOneWidget);
    await close(tester, state);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_draft_me_room'), 'Please fix the light');
  });
  testWidgets('search finds old messages and closing search returns to latest', (tester) async {
    final state = ChatStateFake();
    state.activeChatMessages.addAll(List.generate(200, message));
    await open(tester, state);
    await tester.tap(find.byTooltip('Xabarlardan qidirish'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Message 12');
    await tester.pumpAndSettle();
    expect(find.text('Message 199'), findsNothing);
    expect(find.textContaining('Message 12'), findsWidgets);
    await tester.tap(find.byTooltip('Xabarlardan qidirish'));
    await tester.pumpAndSettle();
    expect(find.text('Message 199'), findsOneWidget);
    await close(tester, state);
  });
}
