import '../workflow/workflow_text.dart';
import 'chat_extras.dart';
import '../../core/notifications/notification_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_strings.dart';
import '../../core/widgets/localized_text.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets/app_route.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'ai_chat_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final searchController = TextEditingController();
  int _filter = 0;
  bool _roomIsOpen = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_refreshView);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await widget.appState.refreshChatRooms();
        if (mounted && widget.appState.currentProfile?.role != UserRole.superAdmin) {
          await widget.appState.ensureGroupChat();
        }
      } catch (_) {
        if (mounted) _message(chatText(context, 'retry'));
      }
    });
  }

  void _refreshView() { if (mounted && !_roomIsOpen) setState(() {}); }

  @override
  void dispose() {
    widget.appState.removeListener(_refreshView);
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.appState.currentProfile;
    if (me == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    // HomeShell extends the body behind its glass phone navigation bar.
    // Flutter exposes that bar's height as bottom MediaQuery padding. Using
    // the actual inset also handles different phone safe areas and text sizes.
    final bottomNavigationInset = MediaQuery.paddingOf(context).bottom;
    final query = searchController.text.trim().toLowerCase();
    final companyTitle = widget.appState.companyById(me.companyId)?.name ?? widget.appState.tr('company_chat');
    final rooms = List<ChatRoom>.of(widget.appState.chatRooms)
      ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
    final groups = rooms.where((r) => r.type == ChatRoomType.group &&
        (query.isEmpty || r.title.toLowerCase().contains(query) ||
            (me.role != UserRole.superAdmin && companyTitle.toLowerCase().contains(query)))).toList();
    final direct = rooms.where((r) => r.type == ChatRoomType.direct &&
        (query.isEmpty || _roomTitle(r).toLowerCase().contains(query) ||
            (r.lastMessage ?? '').toLowerCase().contains(query))).toList();
    final people = widget.appState.visibleProfiles().where((p) => p.id != me.id &&
        (me.role == UserRole.superAdmin || p.companyId == me.companyId) &&
        (query.isEmpty || p.fullName.toLowerCase().contains(query) ||
            p.phone.contains(query) || p.jobTitle.toLowerCase().contains(query))).toList();
    return Stack(children: [
      RefreshIndicator(
        onRefresh: () async {
          await widget.appState.refreshChatRooms();
          if (me.role != UserRole.superAdmin) await widget.appState.ensureGroupChat();
        },
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 92 + bottomNavigationInset),
          children: [
            // Text(widget.appState.tr('chat'), style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            //   fontWeight: FontWeight.w800, letterSpacing: -.8)),
            const SizedBox(height: 14),
            TextField(controller: searchController, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  hintText: widget.appState.tr('search_chat'), prefixIcon: const Icon(Icons.search_rounded),
                  filled: true, fillColor: colors.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  suffixIcon: query.isEmpty ? null : IconButton(
                      onPressed: () { searchController.clear(); setState(() {}); },
                      icon: const Icon(Icons.close_rounded))),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final item in [(0, 'all'), (1, 'groups'), (2, 'direct'), (3, 'workers')])
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                    label: Text(chatText(context, item.$2)), selected: _filter == item.$1,
                    showCheckmark: false, onSelected: (_) => setState(() => _filter = item.$1))),
            ])),
            if (_filter == 0 || _filter == 1) ...[
              _sectionTitle(chatText(context, 'groups')),
              if (groups.isEmpty && query.isEmpty && me.role != UserRole.superAdmin)
                _RoomTile(room: null, title: companyTitle, subtitle: chatText(context, 'group_subtitle'),
                    icon: Icons.groups_rounded, onTap: () async {
                      final room = await widget.appState.ensureGroupChat();
                      if (!mounted || !context.mounted) return;
                      if (room == null) { _message(widget.appState.errorMessage ?? chatText(context, 'retry')); return; }
                      _openRoom(room, companyTitle);
                    }),
              for (final room in groups)
                _RoomTile(room: room, title: me.role == UserRole.superAdmin ? room.title : companyTitle,
                    subtitle: room.lastMessage?.isNotEmpty == true ? room.lastMessage! : chatText(context, 'group_subtitle'),
                    icon: Icons.groups_rounded, unread:widget.appState.unreadForRoom(room.id),
                    onTap: () => _openRoom(room, me.role == UserRole.superAdmin ? room.title : companyTitle)),
            ],
            if (_filter == 0 || _filter == 3) ...[
              _sectionTitle(widget.appState.tr('chat_workers')),
              if (!people.any((p) => p.role == UserRole.worker))
                Padding(padding: const EdgeInsets.all(12), child: Text(widget.appState.tr('no_workers'))),
              for (final person in people.where((p) => p.role == UserRole.worker)) _personTile(person),
            ],
            if (_filter == 0 || _filter == 2) ...[
              _sectionTitle(widget.appState.tr('private_chats')),
              if (direct.isEmpty)
                Padding(padding: const EdgeInsets.all(12), child: Text(widget.appState.tr('no_direct_chats'))),
              for (final room in direct)
                _RoomTile(room: room, title: _roomTitle(room),
                    subtitle: room.lastMessage ?? chatText(context, 'direct'), icon: Icons.person_rounded, unread:widget.appState.unreadForRoom(room.id),
                    onTap: () => _openRoom(room, _roomTitle(room)),
                    onLongPress: () => _confirmDeleteRoom(room)),
              _sectionTitle(widget.appState.tr('start_direct_chat')),
              for (final person in people.where((p) => p.role != UserRole.worker)) _personTile(person),
            ],
          ],
        ),
      ),
      if (me.role != UserRole.superAdmin)
        Positioned(
          right: 16,
          bottom: 16 + bottomNavigationInset,
          child: _AiCornerButton(appState: widget.appState),
        ),
    ]);
  }

  Widget _sectionTitle(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)));

  Widget _personTile(Profile person) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20), clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ProfileAvatar(profile: person, radius: 24),
        title: Text(person.fullName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(person.jobTitle.isEmpty ? widget.appState.tr(person.role.dbValue) : person.jobTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(Icons.chat_bubble_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
        onTap: () async {
          final room = await widget.appState.getOrCreateDirectChat(person);
          if (!mounted) return;
          if (room != null) { _openRoom(room, person.fullName); }
          else { _message(widget.appState.errorMessage ?? chatText(context, 'retry')); }
        },
      ),
    ),
  );

  String _roomTitle(ChatRoom room) {
    final me = widget.appState.currentProfile;
    var title = room.title.trim();

    if (me != null && room.type == ChatRoomType.direct) {
      title = title
          .replaceAll(me.fullName, '')
          .replaceAll('↔', '')
          .replaceAll('  ', ' ')
          .trim();
    }

    return title.isEmpty ? room.type.label : title;
  }

  Future<void> _openRoom(ChatRoom room, String title) async {
    if (_roomIsOpen || !mounted) return;
    _roomIsOpen = true;
    try {
      await Navigator.of(context).push(
        smoothRoute<void>(
          ChatRoomPage(
            appState: widget.appState,
            room: room,
            title: title,
          ),
        ),
      );
    } finally { _roomIsOpen = false; if (mounted) setState(() {}); }
  }

  Future<void> _confirmDeleteRoom(ChatRoom room) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.appState.tr('delete_chat')),
        content: Text(widget.appState.tr('delete_chat_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.appState.tr('cancel'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded),
            label: Text(widget.appState.tr('delete')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.appState.deleteChatRoomHard(room);
    if (!mounted) return;
    _message(widget.appState.errorMessage ?? widget.appState.tr('delete_chat'));
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}


class _AiCornerButton extends StatelessWidget {
  const _AiCornerButton({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: appState.tr('open_ai_assistant'),
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.of(context).push(smoothRoute<void>(const AiChatPage())),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, colors.tertiary],
              ),
              boxShadow: [
                BoxShadow(color: colors.primary.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 8)),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.unread=0,
  });

  final ChatRoom? room;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: unread>0?Theme.of(context).colorScheme.primaryContainer.withValues(alpha:.45):Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: room == null ? CircleAvatar(child: Icon(icon)) : _RoomAvatar(room: room!, radius: 25),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:TextStyle(fontWeight:unread>0?FontWeight.w800:FontWeight.normal,
              color:unread>0?Theme.of(context).colorScheme.primary:null),
        ),
        trailing: unread>0?Badge(label:Text(unread>99?'99+':'$unread')): room?.lastMessageAt == null
            ? const Icon(Icons.chevron_right_rounded, size: 20)
            : Text(MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(room!.lastMessageAt!.toLocal())),
            style: Theme.of(context).textTheme.labelSmall),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.appState,
    required this.room,
    required this.title,
  });

  final AppState appState;
  final ChatRoom room;
  final String title;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> with WidgetsBindingObserver {
  late final ChatExtras _extras;
  final _selectedMessages=<String>{};
  int _cachedRevision = -1;
  List<ChatMessage> _cachedMessages = [];
  Map<String,ChatMessage> _messagesById = {};
  final picker = ImagePicker();
  final controller = TextEditingController();
  final scrollController = ScrollController(keepScrollOffset: false);
  final attachments = <PickedAttachment>[];
  bool _pickingMedia=false;

  ChatMessage? replyTo;
  bool _isTyping = false;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  final _messageSearch = TextEditingController();
  final _composerFocus = FocusNode();
  Timer? _draftTimer;
  Timer? _typingTimer;
  bool _foreground = true;
  bool _initialSync = true;
  bool _openFailed = false;
  bool _sending = false;
  bool _searching = false;
  final Set<String> _acknowledgedIds = {};
  bool _markingRead = false;
  bool _didInitialScroll = false;
  bool _userNearBottom = true;
  int _lastRenderedMessageCount = 0;
  String? _lastRenderedMessageId;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onComposerChanged);
    scrollController.addListener(_onScrollChanged);

    _extras = ChatExtras(widget.appState, widget.room.id)..addListener(_settingsChanged);
    _extras.start();
    NotificationService.activeChatRoomId = widget.room.id;
    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
  }

  @override
  void dispose() {
    if (NotificationService.activeChatRoomId == widget.room.id) NotificationService.activeChatRoomId = null;
    _extras.removeListener(_settingsChanged);
    _extras.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _typingTimer?.cancel();
    unawaited(_saveDraft(controller.text));
    _messageSearch.dispose();
    _composerFocus.dispose();
    controller.removeListener(_onComposerChanged);
    scrollController.removeListener(_onScrollChanged);
    widget.appState.setChatTyping(widget.room.id, false);
    controller.dispose();
    scrollController.dispose();
    widget.appState.stopWatchingChatRoom(widget.room.id);
    super.dispose();
  }

  void _settingsChanged() { if (mounted) setState(() {}); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _typingTimer?.cancel();
      _isTyping = false;
      widget.appState.setChatTyping(widget.room.id, false);
      unawaited(_saveDraft(controller.text));
    }
    if (mounted) setState(() {});
  }

  String get _draftKey => 'chat_draft_${widget.appState.currentProfile?.id}_${widget.room.id}';

  Future<void> _loadDraft() async {
    final key = _draftKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || controller.text.isNotEmpty) return;
      final draft = prefs.getString(key) ?? '';
      controller.removeListener(_onComposerChanged);
      controller.text = draft;
      controller.addListener(_onComposerChanged);
    } catch (_) { /* A storage failure must not block the chat. */ }
  }

  Future<void> _saveDraft(String text) async {
    final key = _draftKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (text.isEmpty) { await prefs.remove(key); }
      else { await prefs.setString(key, text); }
    } catch (_) { /* Keep the in-memory composer usable. */ }
  }

  Future<void> _openChat() async {
    if (!mounted) return;
    setState(() { _initialSync = true; _openFailed = false; });
    try {
      await widget.appState.watchChatRoom(widget.room);
      if (!mounted) return;
      setState(() => _initialSync = false);
    } catch (_) {
      if (mounted) setState(() { _initialSync = false; _openFailed = true; });
    }
  }

  void _reply(ChatMessage message) {
    if (message.isDeleted || _sending) return;
    HapticFeedback.selectionClick();
    setState(() => replyTo = message);
    _composerFocus.requestFocus();
  }

  void _acknowledge(List<ChatMessage> messages) {
    if (!_foreground || _markingRead || !_userNearBottom || _searching || _initialSync ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final pending = messages.where((m) => !m.isDeleted &&
        m.senderId != widget.appState.currentProfile?.id &&
        !_acknowledgedIds.contains(m.id)).map((m) => m.id).toSet();
    if (pending.isEmpty) return;
    // Record before the request: AppState notifies listeners after each read update.
    _acknowledgedIds.addAll(pending);
    _markingRead = true;
    widget.appState.markChatRoomAsRead(widget.room.id).whenComplete(() {
      _markingRead = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final me = widget.appState.currentProfile;
        if (me == null) return const Scaffold(body: SizedBox.shrink());
        final colors = Theme.of(context).colorScheme;
        final currentRoom = _currentRoom;
        final canSeeDeletedContent = [UserRole.director, UserRole.admin, UserRole.superAdmin].contains(me.role);
        if (_cachedRevision != widget.appState.chatRevision) {
          _cachedRevision = widget.appState.chatRevision;
          _cachedMessages = widget.appState.activeChatMessages.where((m) => m.roomId == widget.room.id).toList()
            ..sort((a,b) { final result=a.createdAt.compareTo(b.createdAt); return result!=0?result:a.id.compareTo(b.id); });
          _messagesById = {for(final message in _cachedMessages) message.id:message};
        }
        final allMessages = _cachedMessages;
        final query = _messageSearch.text.trim().toLowerCase();
        final messages = allMessages.where((m) =>
        (canSeeDeletedContent || !m.isDeleted) &&
            (query.isEmpty || (!m.isDeleted && m.text.toLowerCase().contains(query)))).toList();
        final typingProfiles = widget.appState.typingProfiles.where((p) => p.id != me.id).toList();
        final pinnedMessage = _pinnedMessage(allMessages, currentRoom);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_searching) _maybeAutoScroll(messages);
          _acknowledge(messages);
        });
        return Scaffold(
          backgroundColor: _extras.wallpaper=='blue' ? colors.primaryContainer.withValues(alpha: .28) : _extras.wallpaper=='warm' ? colors.tertiaryContainer.withValues(alpha: .28) : colors.surfaceContainerLow,
          appBar: AppBar(
            backgroundColor: colors.surface,
            surfaceTintColor: Colors.transparent,
            leading: BackButton(color: colors.primary),
            leadingWidth: 42,
            titleSpacing: 0,
            title: Row(children: [
              _RoomAvatar(room: currentRoom, radius: 19),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(currentRoom.type == ChatRoomType.direct ? widget.title :
                (currentRoom.title.isEmpty ? widget.title : currentRoom.title),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(_typingText(context), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              ])),
            ]),
            actions: [
              if(_selectedMessages.isNotEmpty)...[
                Text('${_selectedMessages.length}'),
                IconButton(onPressed:_deleteSelection,icon:const Icon(Icons.delete_outline)),
                IconButton(onPressed:()=>setState(()=>_selectedMessages.clear()),icon:const Icon(Icons.close)),
              ],
              IconButton(tooltip: chatText(context, 'media'),
                  onPressed: _showMedia, icon: const Icon(Icons.photo_library_outlined)),
              IconButton(tooltip: chatText(context, 'search'),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    _messageSearch.clear();
                    if (!_searching) _scrollBottomSoon(force: true);
                  }), icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded)),
              IconButton(tooltip: chatText(context, 'settings'),
                  onPressed: _showSettings, icon: const Icon(Icons.more_horiz_rounded)),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(children: [
                if (_searching)
                  Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 6), child: TextField(
                    controller: _messageSearch, autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: chatText(context, 'search'),
                        prefixIcon: const Icon(Icons.search_rounded), filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
                  )),
                if (pinnedMessage != null && !pinnedMessage.isDeleted && !_searching)
                  _PinnedMessageBar(message: pinnedMessage,
                      onClose: _canManageCurrentRoom ? () => widget.appState.unpinChatMessage(currentRoom) : null),
                Expanded(child: Stack(children: [
                  Positioned.fill(child: _openFailed && messages.isEmpty
                      ? Center(child: TextButton.icon(onPressed: _openChat,
                      icon: const Icon(Icons.refresh_rounded), label: Text(chatText(context, 'retry'))))
                      : messages.isEmpty
                      ? _initialSync
                      ? const _ChatLoadingSkeleton()
                      : Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                      chatText(context, query.isEmpty ? 'empty' : 'no_results'), textAlign: TextAlign.center)))
                      : ListView.builder(
                    key: ValueKey('timeline_${widget.room.id}_$_searching'),
                    controller: scrollController,
                    reverse: true,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final chronologicalIndex = messages.length - 1 - index;
                      final message = messages[chronologicalIndex];
                      final sender = widget.appState.profileById(message.senderId);
                      final previous = chronologicalIndex > 0 ? messages[chronologicalIndex - 1] : null;
                      final date = message.createdAt.toLocal();
                      final earlierDate = previous?.createdAt.toLocal();
                      final showDate = earlierDate == null || date.year != earlierDate.year ||
                          date.month != earlierDate.month || date.day != earlierDate.day;
                      final readBy = widget.appState.messageReadBy[message.id] ?? <String>{};
                      return Column(key: ValueKey(message.id), children: [
                        if (showDate) Padding(padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(MaterialLocalizations.of(context).formatMediumDate(date),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))),
                        Dismissible(
                          key: ValueKey('reply_${message.id}'),
                          direction: message.isDeleted || _sending ? DismissDirection.none : DismissDirection.startToEnd,
                          dismissThresholds: const {DismissDirection.startToEnd: .25},
                          confirmDismiss: (_) async { _reply(message); return false; },
                          background: Align(alignment: Alignment.centerLeft, child: Padding(
                              padding: const EdgeInsets.only(left: 20), child: Icon(Icons.reply_rounded, color: colors.primary))),
                          child: RepaintBoundary(child: _MessageBubble(
                            message: message, reply: _messagesById[message.replyToMessageId], sender: sender,
                            textScale: _extras.textScale,
                            onReact: !message.isDeleted && _extras.ready ? (emoji) => _react(message.id,emoji) : null,
                            isMine: message.senderId == me.id,
                            isReadByOther: readBy.any((id) => id != me.id),
                            selected:_selectedMessages.contains(message.id),
                            selectionMode:_selectedMessages.isNotEmpty,
                            onSelect:me.role==UserRole.superAdmin && currentRoom.companyId!=null?()=>setState((){
                              if(!_selectedMessages.remove(message.id))_selectedMessages.add(message.id);
                            }):null,
                            onReaders:()=>_showReaders(message),
                            canSeeDeletedContent: canSeeDeletedContent,
                            onReply: () => _reply(message),
                            onPin: _canManageCurrentRoom && !message.isDeleted ? () => widget.appState.pinChatMessage(room: currentRoom, message: message) : null,
                            onEdit: message.senderId == me.id && !message.isDeleted ? () => _editMessage(message) : null,
                            onDelete: message.senderId == me.id && !message.isDeleted ? () => _deleteMessage(message) : null,
                            onSenderTap: sender == null ? null : () => _showSenderInfo(sender),
                          )),
                        ),
                        if(!message.isDeleted) Align(
                            alignment: message.senderId==me.id ? Alignment.centerRight : Alignment.centerLeft,
                            child: MessageReactions(extras:_extras,messageId:message.id)),
                      ]);
                    },
                  )),
                  if (!_userNearBottom && !_searching && !_initialSync)
                    Positioned(right: 14, bottom: 12, child: FloatingActionButton.small(
                        heroTag: 'chat_latest_${widget.room.id}',
                        tooltip: chatText(context, 'latest'),
                        onPressed: () => _scrollBottomSoon(force: true),
                        child: const Icon(Icons.keyboard_double_arrow_down_rounded))),
                ])),
                if (typingProfiles.isNotEmpty) _TypingIndicator(profiles: typingProfiles),
                _Composer(
                  controller: controller, focusNode: _composerFocus,
                  attachments: attachments, replyTo: replyTo,
                  sending: _sending || _openFailed,
                  onCancelReply: () => setState(() => replyTo = null),
                  onRemoveAttachment: (i) => setState(() => attachments.removeAt(i)),
                  onPickImage: _pickImage, onPickVideo: _pickVideo,
                  onPickCamera: () => _pickImage(source: ImageSource.camera),
                  onSend: _send,
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _react(String id,String emoji) async {
    try { await _extras.react(id,emoji); }
    catch (_) { if(mounted) _message(chatText(context,'reaction_error')); }
  }

  Future<void> _showSettings() async {
    var scale=_extras.textScale;
    var background=_extras.wallpaper;
    DateTime? mute=_extras.mutedUntil;
    var saving=false;
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,
        builder:(sheet)=>StatefulBuilder(builder:(sheet,update)=>SafeArea(child:SingleChildScrollView(
          padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(chatText(sheet,'settings'),style:Theme.of(sheet).textTheme.titleLarge),
          ListTile(leading:const Icon(Icons.info_outline),title:Text(widget.title),
              subtitle:Text(chatText(sheet,_currentRoom.type==ChatRoomType.group?'group':'direct'))),
          SwitchListTile(title:Text(chatText(sheet,'mute')),value:mute?.isAfter(DateTime.now())??false,
              onChanged:saving?null:(value)=>update(()=>mute=value?DateTime.now().add(const Duration(days:3650)):null)),
          Wrap(spacing:8,children:[for(final hours in [1,8,24]) ActionChip(label:Text('$hours h'),
              onPressed:saving?null:()=>update(()=>mute=DateTime.now().add(Duration(hours:hours))))]),
          ListTile(title:Text(chatText(sheet,'text_size')),trailing:Text('${(scale*100).round()}%')),
          Slider(value:scale,min:.9,max:1.4,divisions:5,onChanged:saving?null:(value)=>update(()=>scale=value)),
          DropdownButtonFormField<String>(initialValue:background,
              decoration:InputDecoration(labelText:chatText(sheet,'wallpaper')),
              items:[for(final key in ['default','blue','warm']) DropdownMenuItem(value:key,child:Text(chatText(sheet,key)))],
              onChanged:saving?null:(value)=>update(()=>background=value??'default')),
          ListTile(leading:const Icon(Icons.people_outline),title:Text(chatText(sheet,'members')),
              onTap:(){Navigator.pop(sheet);_showMembers();}),
          ListTile(leading:const Icon(Icons.photo_library_outlined),title:Text(chatText(sheet,'media')),
              onTap:(){Navigator.pop(sheet);_showMedia();}),
          if(_canManageCurrentRoom) ListTile(leading:const Icon(Icons.edit_outlined),
              title:LocalizedText('Chat profilini tahrirlash'),onTap:(){Navigator.pop(sheet);_editGroupProfile();}),
          const SizedBox(height:12),
          FilledButton(onPressed:saving?null:() async {
            update(()=>saving=true);
            try { await _extras.save(mute:mute,scale:scale,background:background); if(sheet.mounted) Navigator.pop(sheet); }
            catch (_) {
              if (sheet.mounted && mounted) {
                update(() => saving = false);
                _message(chatText(sheet, 'settings_error'));
              }
            }
          },child:Text(widget.appState.tr('save'))),
        ]),
        ))));
  }

  Future<void> _showMembers() async {
    try {
      final rows=await widget.appState.client.from('chat_room_members').select('profile_id').eq('room_id',widget.room.id);
      final ids=rows.map((r)=>'${r['profile_id']}').toSet();
      final members=widget.appState.profiles.where((p)=>ids.contains(p.id) ||
          (_currentRoom.type==ChatRoomType.group && p.companyId==_currentRoom.companyId)).toList();
      if(!mounted) return;
      await showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(
          child:ListView(shrinkWrap:true,children:[
            Padding(padding:const EdgeInsets.all(16),child:Text(chatText(sheet,'members'),style:Theme.of(sheet).textTheme.titleLarge)),
            for(final member in members) ListTile(leading:ProfileAvatar(profile:member,radius:22),
                title:Text(member.fullName),subtitle:Text(widget.appState.tr(member.role.dbValue)),
                onTap:(){Navigator.pop(sheet);_showSenderInfo(member);}),
          ])));
    } catch (_) { if(mounted) _message(chatText(context,'settings_error')); }
  }

  void _showMedia() {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .7,
        child: AnimatedBuilder(animation: widget.appState, builder: (context, _) {
          final messages = widget.appState.activeChatMessages.where((m) =>
          m.roomId == widget.room.id && !m.isDeleted && m.attachments.isNotEmpty).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Text(chatText(context, 'media'),
                style: Theme.of(context).textTheme.titleLarge)),
            Expanded(child: messages.isEmpty
                ? Center(child: Text(chatText(context, 'no_media')))
                : ListView.separated(padding: const EdgeInsets.all(16), itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _AttachmentPreview(
                  urls: messages[index].attachments,
                  onReply: () { Navigator.pop(sheetContext); _reply(messages[index]); },
                ))),
          ]);
        }),
      )),
    );
  }

  String _typingText(BuildContext context) {
    final names = widget.appState.typingProfiles
        .where((p) => p.id != widget.appState.currentProfile?.id)
        .map((p) => p.fullName).where((name) => name.isNotEmpty).take(2).toList();
    if (names.isNotEmpty) return '${names.join(', ')} ${chatText(context, 'typing')}';
    return chatText(context, _currentRoom.type == ChatRoomType.group ? 'group' : 'direct');
  }

  ChatRoom get _currentRoom {
    for (final room in widget.appState.chatRooms) {
      if (room.id == widget.room.id) return room;
    }
    return widget.room;
  }

  Future<void> _showReaders(ChatMessage message) async {
    await widget.appState.refreshChatReads(widget.room.id);
    if(!mounted)return;
    final ids=widget.appState.messageReadBy[message.id]??<String>{};
    final readers=widget.appState.profiles.where((p)=>ids.contains(p.id) && p.id!=message.senderId).toList();
    await showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(context)=>SafeArea(child:
    SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(workflowText(context,'read_by'),style:Theme.of(context).textTheme.titleLarge),
      if(readers.isEmpty)Padding(padding:const EdgeInsets.all(24),child:Text(workflowText(context,'no_readers'))),
      for(final p in readers)ListTile(leading:ProfileAvatar(profile:p,radius:20),title:Text(p.fullName),subtitle:Text(p.jobTitle)),
    ]))));
  }
  Future<void> _deleteSelection() async {
    final ids=List<String>.of(_selectedMessages);
    if(ids.isEmpty)return;
    final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:Text('${workflowText(context,'selected')}: ${ids.length}'),content:Text(workflowText(context,'cleanup_warning')),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(widget.appState.tr('cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(widget.appState.tr('delete')))]));
    if(ok!=true || !mounted)return;
    final saved=await widget.appState.removeSelectedMessages(_currentRoom,ids);
    if(!mounted)return;
    if (saved) {
      setState(() => _selectedMessages.clear());
    } else {
      _message(widget.appState.errorMessage ?? widget.appState.tr('error_unknown'));
    }
  }

  bool get _canManageCurrentRoom {
    final me = widget.appState.currentProfile;
    return _currentRoom.type == ChatRoomType.group &&
        (me?.role == UserRole.director || me?.role == UserRole.admin || me?.role == UserRole.superAdmin);
  }

  ChatMessage? _pinnedMessage(List<ChatMessage> messages, ChatRoom room) {
    final pinnedId = room.pinnedMessageId;
    if (pinnedId == null || pinnedId.isEmpty) return null;
    for (final message in messages) {
      if (message.id == pinnedId) return message;
    }
    return null;
  }

  Future<void> _editGroupProfile() async {
    final room = _currentRoom;
    final titleController = TextEditingController(text: room.title.isEmpty ? 'Umumiy chat' : room.title);
    PickedAttachment? avatar;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 8,
                  bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Umumiy chat profili',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Column(
                          children: [
                            _RoomAvatar(room: room, radius: 42, pickedAvatar: avatar),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final file = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 80,
                                  maxWidth: 1400,
                                  maxHeight: 1400,
                                );
                                if (file == null) return;
                                final picked = PickedAttachment(
                                  name: file.name,
                                  bytes: await file.readAsBytes(),
                                  isVideo: false,
                                );
                                if (picked.sizeInMb > 8) {
                                  _message('Chat rasmi maksimal 8 MB bo‘lsin.');
                                  return;
                                }
                                setSheetState(() => avatar = picked);
                              },
                              icon: const Icon(Icons.photo_camera_rounded),
                              label: const LocalizedText('Rasm tanlash'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        textInputAction: TextInputAction.done,
                        decoration:  InputDecoration(
                          labelText: LocalizedText.translate(context, 'Chat nomi'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.save_rounded),
                          label: const LocalizedText('Saqlash'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      final ok = await widget.appState.updateGroupChatRoom(
        room: room,
        title: titleController.text,
        avatar: avatar,
      );
      if (!mounted) return;
      _message(ok ? 'Chat profili saqlandi.' : (widget.appState.errorMessage ?? 'Chat profili saqlanmadi.'));
      setState(() {});
    }
    titleController.dispose();
  }

  void _onComposerChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () => _saveDraft(controller.text));
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _isTyping = false;
      widget.appState.setChatTyping(widget.room.id, false);
    });
    final hasText = controller.text.trim().isNotEmpty;
    final now = DateTime.now();

    if (hasText && (!_isTyping || now.difference(_lastTypingSent).inSeconds >= 2)) {
      _isTyping = true;
      _lastTypingSent = now;
      widget.appState.setChatTyping(widget.room.id, true);
    }

    if (!hasText && _isTyping) {
      _isTyping = false;
      widget.appState.setChatTyping(widget.room.id, false);
    }
  }

  void _showSenderInfo(Profile sender) {
    final me = widget.appState.currentProfile!;
    final canSeeFull = me.role == UserRole.director ||
        me.role == UserRole.admin ||
        me.role == UserRole.superAdmin;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 8,
              bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfileAvatar(profile: sender, radius: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          sender.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _UserInfoRow(
                    icon: Icons.badge_rounded,
                    label: 'Role',
                    value: widget.appState.tr(sender.role.dbValue),
                  ),
                  if (canSeeFull) ...[
                    _UserInfoRow(
                      icon: Icons.phone_rounded,
                      label: widget.appState.tr('phone'),
                      value: sender.phone.isEmpty ? 'Kiritilmagan' : sender.phone,
                    ),
                    _UserInfoRow(
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: sender.email.isEmpty ? '-' : sender.email,
                    ),
                    _UserInfoRow(
                      icon: Icons.business_rounded,
                      label: 'Tashkilot',
                      value: widget.appState.companyById(sender.companyId)?.name ?? '-',
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'To‘liq ma’lumot faqat direktor va adminlarga ko‘rinadi.',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage({ImageSource source=ImageSource.gallery})=>_pickMedia(false,source);
  Future<void> _pickVideo()=>_pickMedia(true,ImageSource.gallery);
  Future<void> _pickMedia(bool video,ImageSource source) async {
    if(_sending || _pickingMedia)return;
    if(attachments.length>=6)return _message(widget.appState.tr('media_limit'));
    setState(()=>_pickingMedia=true);
    try {
      final file=video?await picker.pickVideo(source:source,maxDuration:const Duration(seconds:60)):
      await picker.pickImage(source:source,imageQuality:78,maxWidth:1800,maxHeight:1800);
      if(file==null || !mounted)return;
      final length=await file.length();
      if(length<=0 || length>(video?60:8)*1024*1024 || attachments.fold<double>(0,(sum,f)=>sum+f.sizeInMb)+length/(1024*1024)>120){
        if(mounted)_message(widget.appState.tr('media_limit'));return;
      }
      final bytes=video && !kIsWeb?Uint8List(0):await file.readAsBytes();
      if(mounted)setState(()=>attachments.add(PickedAttachment(name:file.name,bytes:bytes,isVideo:video,localPath:kIsWeb ? null : file.path,byteLength:length)));
    } catch(_){if(mounted)_message(chatText(context,'media_error'));}
    finally{if(mounted)setState(()=>_pickingMedia=false);}
  }

  Future<void> _send() async {
    if (_sending || _pickingMedia || _openFailed) return;
    final text = controller.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    setState(() => _sending = true);
    try {
      final ok = await widget.appState.sendChatMessage(
        roomId: widget.room.id, text: text,
        attachments: List.of(attachments), replyToMessageId: replyTo?.id,
      );
      if (!mounted) return;
      if (ok) {
        controller.clear();
        _draftTimer?.cancel();
        await _saveDraft('');
        if (!mounted) return;
        _isTyping = false;
        widget.appState.setChatTyping(widget.room.id, false);
        setState(() { attachments.clear(); replyTo = null; });
        _scrollBottomSoon(force: true);
      } else {
        _message(widget.appState.errorMessage ?? chatText(context, 'send_error'));
      }
    } catch (_) {
      if (mounted) _message(chatText(context, 'send_error'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final edit = TextEditingController(text: message.text);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const LocalizedText('Xabarni tahrirlash'),
          content: TextField(
            controller: edit,
            minLines: 2,
            maxLines: 5,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedText('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, edit.text),
              child: const LocalizedText('Saqlash'),
            ),
          ],
        );
      },
    );

    edit.dispose();

    if (result == null || !mounted) return;
    if (result.trim().isEmpty) { _message(chatText(context, 'empty_edit')); return; }
    try {
      await widget.appState.editChatMessage(message: message, newText: result);
      if (mounted && widget.appState.errorMessage != null) _message(widget.appState.errorMessage!);
    } catch (_) {
      if (mounted) _message(chatText(context, 'send_error'));
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const LocalizedText('Xabar o‘chirilsinmi?'),
          content: const LocalizedText('Bu xabar chatda “o‘chirildi” ko‘rinishida qoladi.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('Yo‘q'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('Ha'),
            ),
          ],
        );
      },
    );

    if (yes == true) {
      await widget.appState.deleteChatMessage(message);
    }
  }

  void _onScrollChanged() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    final nearBottom = position.pixels - position.minScrollExtent <= 100;
    if (nearBottom != _userNearBottom && mounted) {
      setState(() => _userNearBottom = nearBottom);
    }
  }

  void _maybeAutoScroll(List<ChatMessage> messages) {
    if (!mounted || !scrollController.hasClients) return;

    final lastMessageId = messages.isEmpty ? null : messages.last.id;
    final hasListChanged = messages.length != _lastRenderedMessageCount ||
        lastMessageId != _lastRenderedMessageId;

    if (!_didInitialScroll) {
      _didInitialScroll = true;
      _lastRenderedMessageCount = messages.length;
      _lastRenderedMessageId = lastMessageId;
      _scrollBottomSoon(jump: true);
      return;
    }

    if (!hasListChanged) return;

    final me = widget.appState.currentProfile;
    final lastMessageIsMine = messages.isNotEmpty && messages.last.senderId == me?.id;

    _lastRenderedMessageCount = messages.length;
    _lastRenderedMessageId = lastMessageId;

    if (_userNearBottom || lastMessageIsMine) {
      _scrollBottomSoon(force: true);
    }
  }

  void _scrollBottomSoon({bool jump = false, bool force = false}) {
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (!scrollController.hasClients) return;
      if (!force && !_userNearBottom && !jump) return;

      final max = scrollController.position.minScrollExtent;

      if (jump) {
        scrollController.jumpTo(max);
        return;
      }

      scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}


// Lightweight message placeholders: the composer stays usable while the
// first network response arrives, with no blocking progress spinner.
class _ChatLoadingSkeleton extends StatelessWidget {
  const _ChatLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bubble(double width, bool mine) => Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: width, height: 35,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(18)),
      ),
    );
    return IgnorePointer(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        bubble(180, false), bubble(130, true), bubble(220, false),
      ]),
    ));
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({required this.room, required this.radius, this.pickedAvatar});

  final ChatRoom room;
  final double radius;
  final PickedAttachment? pickedAvatar;

  @override
  Widget build(BuildContext context) {
    if (pickedAvatar != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(pickedAvatar!.bytes),
      );
    }

    final avatarUrl = room.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: Icon(room.type == ChatRoomType.group ? Icons.groups_rounded : Icons.person_rounded),
    );
  }
}

class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({required this.message, this.onClose});

  final ChatMessage message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final text = message.isDeleted
        ? 'O‘chirilgan xabar'
        : message.text.trim().isEmpty
        ? 'Qadangan fayl'
        : message.text.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: LocalizedText.translate(context, 'Qadangan xabarni olib tashlash'),
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.sender,
    required this.isMine,
    required this.isReadByOther,
    required this.canSeeDeletedContent,
    required this.onReply,
    this.reply,
    this.onPin,
    this.onEdit,
    this.onDelete,
    this.onSenderTap,
    this.onReact,
    this.textScale = 1,
    this.onReaders, this.onSelect, this.selected=false, this.selectionMode=false,
  });

  final ChatMessage message;
  final ChatMessage? reply;
  final Profile? sender;
  final bool isMine;
  final bool isReadByOther;
  final bool canSeeDeletedContent;
  final VoidCallback onReply;
  final VoidCallback? onReaders,onSelect;
  final bool selected,selectionMode;
  final VoidCallback? onPin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSenderTap;
  final ValueChanged<String>? onReact;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final bg = isMine
        ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF163F68) : const Color(0xFFDCEEFF))
        : colors.surfaceContainerHighest;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isMine ? 20 : 5),
      bottomRight: Radius.circular(isMine ? 5 : 20),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .78,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: selectionMode?onSelect:()=>_showActions(context),
            onLongPress: onSelect??()=>_showActions(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    GestureDetector(
                      onTap: onSenderTap,
                      child: Text(
                        sender?.fullName ?? 'Foydalanuvchi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: colors.primary,
                        ),
                      ),
                    ),

                  if (reply != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        reply!.isDeleted
                            ? 'O‘chirilgan xabar'
                            : (reply!.text.isEmpty ? 'Fayl' : reply!.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  if (message.isDeleted)
                    _DeletedMessageContent(message: message, canSeeContent: canSeeDeletedContent)
                  else ...[
                    if (message.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(message.text, style: TextStyle(fontSize: 16 * textScale, height: 1.35)),
                      ),
                    if (message.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _AttachmentPreview(urls: message.attachments, onReply: onReply),
                      ),
                  ],

                  const SizedBox(height: 6),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _time(message.createdAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (message.isEdited)
                        Text(
                          ' • ${chatText(context, 'edited')}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (isMine)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            isReadByOther ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 16,
                            color: isReadByOther
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if(onSelect!=null) ListTile(leading:const Icon(Icons.checklist),title:Text(workflowText(context,'select')),
                  onTap:(){Navigator.pop(context);onSelect!();}),
              if(onReaders!=null) ListTile(leading:const Icon(Icons.done_all),title:Text(workflowText(context,'read_by')),
                  onTap:(){Navigator.pop(context);onReaders!();}),
              if(onReact!=null) Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:2,children:[
                for(final emoji in reactionEmojis) IconButton(tooltip:emoji,
                    onPressed:(){Navigator.pop(context);onReact!(emoji);},icon:Text(emoji,style:const TextStyle(fontSize:25))),
              ])),
              if (!message.isDeleted && message.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(chatText(context, 'copy')),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                  },
                ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const LocalizedText('Reply'),
                  onTap: () {
                    Navigator.pop(context);
                    onReply();
                  },
                ),
              if (onPin != null)
                ListTile(
                  leading: const Icon(Icons.push_pin_rounded),
                  title: const LocalizedText('Qadab qo‘yish'),
                  onTap: () {
                    Navigator.pop(context);
                    onPin!();
                  },
                ),
              if (onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const LocalizedText('Tahrirlash'),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit!();
                  },
                ),
              if (onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_rounded),
                  title: const LocalizedText('O‘chirish'),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete!();
                  },
                ),
            ],
          )),
        );
      },
    );
  }

  static String _time(DateTime date) {
    final tashkentTime = date.toLocal();
    return '${tashkentTime.hour.toString().padLeft(2, '0')}:${tashkentTime.minute.toString().padLeft(2, '0')}';
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.urls, required this.onReply});

  final List<String> urls;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in urls)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showAttachment(context, url),
            child: _isVideoUrl(url)
                ? Container(
              width: 178,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: [colors.secondaryContainer, colors.primaryContainer.withValues(alpha: .75)]),
                border: Border.all(color: colors.primary.withValues(alpha: .22)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_fill_rounded, size: 42, color: colors.primary),
                  const SizedBox(height: 8),
                  const LocalizedText('Videoni ilovada ko‘rish', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            )
                : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                width: 170,
                height: 120,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) => const SizedBox(width: 170, height: 120, child: Icon(Icons.broken_image_rounded)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showAttachment(BuildContext context, String url) async {
    final isVideo = _isVideoUrl(url);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
                  child: Row(
                    children: [
                      Icon(isVideo ? Icons.play_circle_rounded : Icons.image_rounded),
                      const SizedBox(width: 8),
                      Expanded(child: Text(isVideo ? 'Video' : 'Rasm', style: const TextStyle(fontWeight: FontWeight.w900))),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: isVideo
                        ? _ChatVideoPlayer(url: url)
                        : InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onReply();
                          },
                          icon: const Icon(Icons.reply_rounded),
                          label: const LocalizedText('Javob yozish'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isVideoUrl(String url) {
    final clean = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase().split('?').first;
    return clean.endsWith('.mp4') || clean.endsWith('.mov') || clean.endsWith('.webm') || clean.endsWith('.m4v') || clean.contains('/video/') || clean.contains('video');
  }
}


class _ChatVideoPlayer extends StatefulWidget {
  const _ChatVideoPlayer({required this.url});

  final String url;

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      _error = 'Video manzili noto‘g‘ri.';
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.addListener(_onVideoChanged);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isReady = true);
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _error = 'Videoni ilova ichida ochib bo‘lmadi.');
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final controller = _controller;

    if (_error != null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (defaultTargetPlatform == TargetPlatform.windows) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final uri = Uri.tryParse(widget.url);
                      if (uri == null) return;
                      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
                      catch (_) { /* Native launcher may be unavailable. */ }
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Videoni ochish'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (!_isReady || controller == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final aspectRatio = controller.value.aspectRatio <= 0
        ? 16 / 9
        : controller.value.aspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlay,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (!controller.value.isPlaying)
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 46,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onVideoChanged() {
    if (mounted && _isReady) setState(() {});
  }

  void _togglePlay() {
    final controller = _controller;
    if (!_isReady || controller == null) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }
}

class _DeletedMessageContent extends StatelessWidget {
  const _DeletedMessageContent({required this.message, required this.canSeeContent});

  final ChatMessage message;
  final bool canSeeContent;

  @override
  Widget build(BuildContext context) {
    final deletedText = message.deletedText?.trim() ?? '';
    final deletedFiles = message.deletedAttachments;
    if (!canSeeContent) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedText('Xabar o‘chirildi', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
          if (deletedText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('O‘chirilgan matn: $deletedText'),
          ],
          if (deletedFiles.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final url in deletedFiles)
                  Chip(
                    avatar: const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(url.split('/').last, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.profiles});

  final List<Profile> profiles;

  @override
  Widget build(BuildContext context) {
    final text = profiles.length == 1
        ? '${profiles.first.fullName} ${chatText(context, 'typing')}'
        : chatText(context, 'many_typing');

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                child: _TypingDots(),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = (controller.value * 3).floor() % 3;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
                (i) {
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 
                    i == active ? 1 : .35,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _UserInfoRow extends StatelessWidget {
  const _UserInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller, required this.focusNode,
    required this.attachments, required this.sending,
    required this.onPickImage, required this.onPickVideo, required this.onPickCamera,
    required this.onRemoveAttachment, required this.onSend,
    required this.onCancelReply, this.replyTo,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<PickedAttachment> attachments;
  final bool sending;
  final VoidCallback onPickImage, onPickVideo, onPickCamera, onSend, onCancelReply;
  final ValueChanged<int> onRemoveAttachment;
  final ChatMessage? replyTo;

  Future<void> _chooseAttachment(BuildContext context) async {
    final choice = await showModalBottomSheet<int>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final item in [(0, Icons.photo_library_rounded, 'photo'),
          (1, Icons.videocam_rounded, 'video'),
          (2, Icons.camera_alt_rounded, 'camera')])
          ListTile(leading: Icon(item.$2), title: Text(chatText(sheetContext, item.$3)),
              onTap: () => Navigator.pop(sheetContext, item.$1)),
        const SizedBox(height: 12),
      ])),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 0: onPickImage(); break;
      case 1: onPickVideo(); break;
      case 2: onPickCamera(); break;
    }
  }

  Future<void> _chooseEmoji(BuildContext context) async {
    const emojis = ['😀', '😊', '😂', '🥰', '😍', '😎', '🤔', '😢',
      '👍', '👎', '👏', '🙏', '❤️', '💙', '🎉', '🔥',
      '✅', '❗', '👋', '💪', '🏠', '🔧', '💡', '🚰'];
    final emoji = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(height: 260,
          child: GridView.count(crossAxisCount: 6, padding: const EdgeInsets.all(12),
              children: [for (final emoji in emojis) InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(sheetContext, emoji),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28)))),
              ]))),
    );
    if (!context.mounted || emoji == null) return;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(color: colors.surface, child: SafeArea(top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (replyTo != null)
            Container(margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(Icons.reply_rounded, color: colors.primary), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(chatText(context, 'reply'), style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700)),
                    Text(replyTo!.text.isEmpty ? chatText(context, 'attach') : replyTo!.text,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])),
                  IconButton(tooltip: chatText(context, 'cancel_reply'),
                      onPressed: sending ? null : onCancelReply, icon: const Icon(Icons.close_rounded)),
                ])),
          if (attachments.isNotEmpty)
            SizedBox(height: 96, child: ListView.separated(
              scrollDirection: Axis.horizontal, itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => SizedBox(width: 86, child: Stack(children: [
                Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: attachments[i].isVideo
                        ? ColoredBox(color: colors.secondaryContainer, child: const Icon(Icons.videocam_rounded))
                        : Image.memory(attachments[i].bytes, fit: BoxFit.cover, cacheWidth: 180))),
                Positioned(right: 0, top: 0, child: IconButton.filledTonal(
                    tooltip: chatText(context, 'remove'),
                    onPressed: sending ? null : () => onRemoveAttachment(i),
                    icon: const Icon(Icons.close_rounded, size: 16))),
              ])),
            )),
          if (attachments.isNotEmpty) const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(tooltip: chatText(context, 'attach'),
                onPressed: sending ? null : () => _chooseAttachment(context),
                icon: Icon(Icons.add_circle_rounded, color: colors.primary, size: 30)),
            Expanded(child: TextField(
              controller: controller, focusNode: focusNode, readOnly: sending,
              minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: chatText(context, 'message'), filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                suffixIcon: IconButton(tooltip: chatText(context, 'emoji'),
                    onPressed: sending ? null : () => _chooseEmoji(context),
                    icon: const Icon(Icons.sentiment_satisfied_alt_rounded)),
              ),
            )),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(valueListenable: controller,
                builder: (context, value, _) => IconButton.filled(
                  tooltip: chatText(context, 'send'),
                  onPressed: sending || (value.text.trim().isEmpty && attachments.isEmpty) ? null : onSend,
                  icon: sending ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                      : const Icon(Icons.arrow_upward_rounded),
                )),
          ]),
        ]),
      ),
    ));
  }
}
