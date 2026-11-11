import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/media_viewer.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'work_activity_repository.dart';
import 'work_media_picker.dart';

/// A small, single-purpose work screen. Existing work_items, evidence and
/// events are kept as-is; this screen does not migrate or delete any data.
class WorkActivityPage extends StatefulWidget {
  const WorkActivityPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<WorkActivityPage> createState() => _WorkActivityPageState();
}

class _WorkActivityPageState extends State<WorkActivityPage> {
  List<WorkItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  bool _more = false;
  bool _loadingMore = false;
  bool _wasActive = false;
  String? _error;
  int _section = 0;
  int _requestId = 0;
  String? _selectedCompanyId;
  bool _showArchived = false;

  WorkActivityRepository get _repository => WorkActivityRepository(widget.appState);
  bool get _isSuperAdmin =>
      widget.appState.currentProfile?.role == UserRole.superAdmin;
  bool get _isManager =>
      _isSuperAdmin ||
      widget.appState.currentProfile?.role == UserRole.director ||
      widget.appState.currentProfile?.role == UserRole.admin;
  int get _tabIndex => _isSuperAdmin ? 11 : (_isManager ? 8 : 5);

  @override
  void initState() {
    super.initState();
    _wasActive = widget.appState.selectedIndex == _tabIndex;
    widget.appState.addListener(_onAppStateChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void didUpdateWidget(covariant WorkActivityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.appState, widget.appState)) {
      oldWidget.appState.removeListener(_onAppStateChange);
      widget.appState.addListener(_onAppStateChange);
      _wasActive = false;
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _requestId++;
    widget.appState.removeListener(_onAppStateChange);
    super.dispose();
  }

  void _onAppStateChange() {
    final active = widget.appState.selectedIndex == _tabIndex;
    if (active && !_wasActive && !_busy) unawaited(_reload());
    _wasActive = active;
  }

  Future<void> _reload() async {
    final currentRequest = ++_requestId;
    final profile = widget.appState.currentProfile;
    if (profile == null) return;
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.fetchItems(limit: 60,
        companyFilter: _selectedCompanyId, archived: _isSuperAdmin && _showArchived);
      if (!mounted || currentRequest != _requestId ||
          widget.appState.currentProfile?.id != profile.id) return;
      setState(() {
        _items = result;
        _more = result.length == 60;
      });
    } catch (e) {
      if (mounted && currentRequest == _requestId) {
        setState(() => _error = widget.appState.friendlyError('$e'));
      }
    } finally {
      if (mounted && currentRequest == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_more) return;
    final currentRequest = _requestId;
    setState(() => _loadingMore = true);
    try {
      final result = await _repository.fetchItems(
          offset: _items.length, limit: 60,
          companyFilter: _selectedCompanyId,
          archived: _isSuperAdmin && _showArchived);
      if (!mounted || currentRequest != _requestId) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items = [..._items, ...result.where((e) => known.add(e.id))];
        _more = result.length == 60;
      });
    } catch (e) {
      _showMessage('Yuklab bo‘lmadi: ${widget.appState.friendlyError('$e')}');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _showMessage(success);
      await _reload();
    } catch (e) {
      _showMessage('Amal bajarilmadi: ${widget.appState.friendlyError('$e')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_WorkInput?> _openEditor(String type, {
    WorkItem? item,
    List<Profile> workers = const [],
  }) => showModalBottomSheet<_WorkInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .88,
      child: _WorkEditor(type: type, item: item, workers: workers),
    ),
  );

  Future<void> _create() async {
    if (_isSuperAdmin) {
      await _adminCreate('assignment');
      return;
    }
    final workers = _isManager
        ? widget.appState.workersForCompany(
            widget.appState.currentProfile?.companyId)
        : <Profile>[];
    if (_isManager && workers.isEmpty) {
      _showMessage('Avval tashkilotingizga ishchi qo‘shing.');
      return;
    }
    final input = await _openEditor(
        _isManager ? 'assignment' : 'daily', workers: workers);
    if (input == null || !mounted) return;
    if (_isManager) {
      await _run(() => _repository.createAssignment(
        workerId: input.workerId!, title: input.title,
        description: input.description, location: input.location,
        category: 'other', priority: 'normal', dueOn: null,
        files: input.files,
      ), 'Topshiriq ishchiga yuborildi.');
    } else {
      await _run(() => _repository.createDaily(
        title: input.title, description: input.description,
        location: input.location, category: 'other',
        workDate: DateTime.now(), files: input.files,
      ), 'Kunlik hisobot yuborildi.');
    }
  }

  Future<void> _adminCreate(String kind) async {
    String? targetId = _selectedCompanyId;
    if (targetId == null) {
      targetId = await showDialog<String>(context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Tashkilotni tanlang'),
          children: widget.appState.companies.map((c) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c.id), child: Text(c.name),
          )).toList(),
        ),
      );
    }
    if (targetId == null || !mounted) return;
    final workers = widget.appState.workersForCompany(targetId);
    if (workers.isEmpty) {
      _showMessage('Ushbu tashkilotga avval ishchi qo‘shing.');
      return;
    }
    final input = await _openEditor(kind == 'daily' ? 'admin_daily' : 'assignment',
      workers: workers);
    if (input == null || !mounted) return;
    await _run(() => _repository.adminSave(
      targetCompanyId: targetId!, workerId: input.workerId!,
      kind: kind, title: input.title, description: input.description,
      location: input.location, files: input.files,
    ), kind == 'daily' ? 'Hisobot qo‘shildi.' : 'Vazifa qo‘shildi.');
  }

  Future<void> _adminEdit(WorkItem item) async {
    final workers = widget.appState.workersForCompany(item.companyId);
    if (workers.isEmpty) {
      _showMessage('Tashkilotda ishchi mavjud emas.');
      return;
    }
    final input = await _openEditor('admin_edit', item: item, workers: workers);
    if (input == null || !mounted) return;
    await _run(() => _repository.adminSave(
      item: item, targetCompanyId: item.companyId,
      workerId: input.workerId!, kind: item.kind,
      title: input.title, description: input.description,
      location: input.location, files: input.files,
    ), 'O‘zgarishlar saqlandi.');
  }

  Future<void> _adminArchive(WorkItem item) async {
    final archive = item.archivedAt == null;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archive ? 'Arxivga o‘tkazish' : 'Arxivdan tiklash'),
        content: Text(archive
          ? '“${item.title}” oddiy ro‘yxatdan yashiriladi. Ma’lumot va rasmlar saqlanadi.'
          : '“${item.title}” oddiy ro‘yxatga qaytarilsinmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(archive ? 'Arxivlash' : 'Tiklash')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => _repository.adminArchive(item, archive: archive),
      archive ? 'Arxivga o‘tkazildi.' : 'Qayta tiklandi.');
  }

  Future<void> _submit(WorkItem item) async {
    final input = await _openEditor('result', item: item);
    if (input == null || !mounted) return;
    final action = item.isTask
        ? () => _repository.submitAssignment(item,
            description: input.description, workDate: DateTime.now(),
            files: input.files)
        : () => _repository.resubmitDaily(item,
            description: input.description, workDate: DateTime.now(),
            files: input.files);
    await _run(action, 'Ish natijasi tekshiruvga yuborildi.');
  }

  Future<void> _review(WorkItem item, bool approved) async {
    String note = '';
    final response = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approved ? 'Ishni tasdiqlash' : 'Qayta ishlash'),
        content: TextField(
          autofocus: !approved,
          onChanged: (value) => note = value,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: approved ? 'Izoh (ixtiyoriy)' : 'Nimani tuzatish kerak?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Orqaga')),
          FilledButton(onPressed: () {
            if (!approved && note.trim().length < 4) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Sababni kamida 4 ta belgi bilan yozing.'),
              ));
              return;
            }
            Navigator.pop(ctx, note.trim());
          }, child: Text(approved ? 'Tasdiqlash' : 'Qaytarish')),
        ],
      ),
    );
    if (response == null || !mounted) return;
    await _run(() => _isSuperAdmin
      ? _repository.adminReview(item, approved: approved, note: response)
      : _repository.review(item, approved: approved, note: response),
      approved ? 'Hisobot tasdiqlandi.' : 'Ish qayta ishlashga qaytarildi.');
  }

  Future<void> _cancelAssignment(WorkItem item) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Topshiriqni bekor qilish'),
        content: Text('“${item.title}” bekor qilinsinmi? Ish tarixi saqlanadi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo‘q')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bekor qilish')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _run(() => _repository.cancel(item,
      'Rahbar tomonidan bekor qilindi.'), 'Topshiriq bekor qilindi.');
  }

  Future<void> _showMedia(WorkItem item, bool evidence) async {
    final paths = evidence ? item.evidencePaths : item.instructionPaths;
    if (paths.isEmpty) return;
    try {
      final urls = await _repository.signedUrls(paths);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) =>
        MediaViewerDialog(title: item.title, body: '',
          mediaUrls: urls, mediaTypes: _repository.mediaTypes(paths)));
    } catch (e) {
      _showMessage('Fayl ochilmadi: ${widget.appState.friendlyError('$e')}');
    }
  }

  Future<void> _history(WorkItem item) async {
    try {
      final events = await _repository.fetchEvents(item.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16),
              child: Text('Ish tarixi', style: Theme.of(ctx).textTheme.titleLarge)),
            Expanded(child: events.isEmpty
              ? const Center(child: Text('Tarix mavjud emas'))
              : ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(_statusName(events[i].action)),
                    subtitle: Text('${_formatDate(events[i].createdAt)}  '
                        '${events[i].note}'),
                  ),
                ),
            ),
          ]),
        )),
      );
    } catch (e) {
      _showMessage('Tarix ochilmadi: ${widget.appState.friendlyError('$e')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = _items.where((item) {
      if (_section == 0) return item.isTask;
      return !item.isTask || item.evidencePaths.isNotEmpty;
    }).toList();
    final reviewCount = _items.where((item) => item.pendingReview).length;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16,
          110 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text(_isManager ? 'Vazifalar va hisobotlar' : 'Mening ishlarim',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_isManager
              ? 'Topshiriq bering va ishchilar yuborgan hisobotlarni tekshiring.'
              : 'Berilgan vazifalarni bajaring va kunlik ishlaringizni yuboring.',
            style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          if (_isSuperAdmin) ...[
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: _busy ? null : () => _adminCreate('assignment'),
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Vazifa'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _adminCreate('daily'),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Hisobot'))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedCompanyId),
              initialValue: _selectedCompanyId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tashkilot bo‘yicha ko‘rish', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: '', child: Text('Barcha tashkilotlar')),
                ...widget.appState.companies.map((c) => DropdownMenuItem(
                  value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (value) {
                setState(() => _selectedCompanyId = value == '' ? null : value);
                unawaited(_reload());
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('Arxivlanganlarini ko‘rsatish'),
              contentPadding: EdgeInsets.zero,
              value: _showArchived,
              onChanged: (value) {
                setState(() => _showArchived = value);
                unawaited(_reload());
              },
            ),
          ] else FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_rounded),
            label: Text(_isManager ? 'Ishchiga vazifa berish' : 'Kunlik hisobot yuborish'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _sectionButton(0, 'Vazifalar')),
            const SizedBox(width: 8),
            Expanded(child: _sectionButton(1, 'Hisobotlar')),
          ]),
          if (_isManager && reviewCount > 0) ...[
            const SizedBox(height: 10),
            Text('$reviewCount ta hisobot tasdiq kutmoqda',
              style: TextStyle(color: colors.primary,
                fontWeight: FontWeight.w600)),
          ],
          if (_loading || _busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(color: colors.errorContainer, child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Ma’lumotlar yuklanmadi. Serverdagi '
                    '“work_items” bo‘limi sozlanganini tekshiring.'),
                const SizedBox(height: 8),
                SelectableText(_error!),
                TextButton.icon(onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Qayta urinish')),
              ]),
            )),
          ],
          if (!_loading && _error == null && items.isEmpty) ...[
            const SizedBox(height: 24),
            const Center(child: Text('Hozircha bu yerda ma’lumot yo‘q.')),
          ],
          const SizedBox(height: 12),
          for (final item in items) _itemCard(item),
          if (_more) OutlinedButton(
            onPressed: _loadingMore ? null : _loadMore,
            child: Text(_loadingMore ? 'Yuklanmoqda...' : 'Yana ko‘rsatish'),
          ),
        ],
      ),
    );
  }

  Widget _sectionButton(int section, String label) => OutlinedButton(
    onPressed: () => setState(() => _section = section),
    style: OutlinedButton.styleFrom(
      backgroundColor: _section == section
        ? Theme.of(context).colorScheme.primaryContainer : null,
      foregroundColor: _section == section
        ? Theme.of(context).colorScheme.onPrimaryContainer : null,
    ),
    child: Text(label),
  );

  Widget _itemCard(WorkItem item) {
    final colors = Theme.of(context).colorScheme;
    final worker = item.workerId == null
        ? null : widget.appState.profileById(item.workerId!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(item.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Text(_statusName(item.status),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: item.pendingReview ? colors.tertiary : colors.primary)),
          ]),
          const SizedBox(height: 5),
          if (worker != null) Text('Ishchi: ${worker.fullName}'),
          if (_isSuperAdmin) Text('Tashkilot: '
            '${widget.appState.companyById(item.companyId)?.name ?? item.companyId}'),
          if (item.location.isNotEmpty) Text('Manzil: ${item.location}'),
          if (item.workDate != null)
            Text('Sana: ${_formatDate(item.workDate!)}'),
          const SizedBox(height: 6),
          Text(item.description),
          if (item.reportText.isNotEmpty && item.reportText != item.description) ...[
            const SizedBox(height: 7),
            Text('Natija: ${item.reportText}'),
          ],
          if (item.reviewNote.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Rahbar izohi: ${item.reviewNote}',
                style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 3, children: [
            if (item.instructionPaths.isNotEmpty) TextButton.icon(
              onPressed: () => _showMedia(item, false),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Vazifa rasmi')),
            if (item.evidencePaths.isNotEmpty) TextButton.icon(
              onPressed: () => _showMedia(item, true),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Natija rasmi/video')),
            TextButton.icon(onPressed: () => _history(item),
              icon: const Icon(Icons.history), label: const Text('Tarix')),
            if (_isSuperAdmin) ...[
              if (item.archivedAt == null) OutlinedButton.icon(
                onPressed: _busy ? null : () => _adminEdit(item),
                icon: const Icon(Icons.edit_outlined), label: const Text('Tahrirlash')),
              TextButton.icon(
                onPressed: _busy ? null : () => _adminArchive(item),
                icon: Icon(item.archivedAt == null
                  ? Icons.archive_outlined : Icons.restore_rounded),
                label: Text(item.archivedAt == null ? 'Arxivga' : 'Tiklash')),
            ],
            if (!_isManager && item.canStart) OutlinedButton(
              onPressed: _busy ? null : () => _run(
                () => _repository.startAssignment(item), 'Ish boshlandi.'),
              child: const Text('Boshlash')),
            if (!_isManager &&
                (item.canSubmit || (!item.isTask && item.status == 'rework')))
              FilledButton(
                onPressed: _busy ? null : () => _submit(item),
                child: const Text('Ishni topshirish')),
            if (_isManager && item.archivedAt == null && item.pendingReview) ...[
              FilledButton(onPressed: _busy ? null : () => _review(item, true),
                child: const Text('Tasdiqlash')),
              OutlinedButton(onPressed: _busy ? null : () => _review(item, false),
                child: const Text('Qaytarish')),
            ],
            if (_isManager && !_isSuperAdmin && item.isTask &&
                {'assigned', 'in_progress', 'rework'}.contains(item.status))
              TextButton(onPressed: _busy ? null : () => _cancelAssignment(item),
                child: const Text('Bekor qilish')),
          ]),
        ]),
      ),
    );
  }
}

String _statusName(String value) => switch (value) {
  'assigned' => 'Yangi',
  'started' || 'in_progress' => 'Jarayonda',
  'submitted' => 'Tekshiruvda',
  'approved' => 'Tasdiqlangan',
  'rework' => 'Qaytarilgan',
  'cancelled' => 'Bekor qilingan',
  'edited' => 'Tahrirlangan',
  'archived' => 'Arxivga o‘tkazilgan',
  'restored' => 'Qayta tiklangan',
  _ => value,
};

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

class _WorkInput {
  const _WorkInput({required this.title, required this.description,
    required this.location, required this.files, this.workerId});
  final String title;
  final String description;
  final String location;
  final String? workerId;
  final List<PickedAttachment> files;
}

class _WorkEditor extends StatefulWidget {
  const _WorkEditor({required this.type, required this.workers, this.item});
  final String type;
  final List<Profile> workers;
  final WorkItem? item;

  @override
  State<_WorkEditor> createState() => _WorkEditorState();
}

class _WorkEditorState extends State<_WorkEditor> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  List<PickedAttachment> _files = const [];
  String? _workerId;
  String? _error;

  bool get _assignment => widget.type == 'assignment';
  bool get _adminDaily => widget.type == 'admin_daily';
  bool get _edit => widget.type == 'admin_edit';
  bool get _needsWorker => _assignment || _adminDaily || _edit;
  bool get _result => widget.type == 'result';

  @override
  void initState() {
    super.initState();
    final previousWorkerId = widget.item?.workerId;
    _workerId = widget.workers.any((w) => w.id == previousWorkerId)
        ? previousWorkerId
        : (widget.workers.isEmpty ? null : widget.workers.first.id);
    if ((_result || _edit) && widget.item != null) {
      _title.text = widget.item!.title;
      _location.text = widget.item!.location;
      if (_edit) _description.text = widget.item!.description;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final description = _description.text.trim();
    String? problem;
    if (!_result && title.length < 4) {
      problem = 'Ish nomini kamida 4 ta belgi bilan yozing.';
    } else if (description.length < 5) {
      problem = 'Bajariladigan ishni kamida 5 ta belgi bilan yozing.';
    } else if (_needsWorker && _workerId == null) {
      problem = 'Ishchini tanlang.';
    } else if (!_assignment && !_edit && _files.isEmpty) {
      problem = 'Rasm yoki video biriktirish majburiy.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, _WorkInput(
      title: _result ? widget.item!.title : title,
      description: description,
      location: _location.text.trim(),
      workerId: _workerId,
      files: List.of(_files),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // One scrollable surface also works with the phone keyboard open. A fixed
    // Column + Expanded can overflow on small screens while typing.
    return SafeArea(child: ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16,
        MediaQuery.viewInsetsOf(context).bottom + 24),
      children: [
        Text(_edit ? 'Vazifa/hisobotni tahrirlash' : _assignment
            ? 'Yangi vazifa' : _result ? 'Ish natijasi' : 'Kunlik hisobot',
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
          if (_needsWorker) ...[
            DropdownButtonFormField<String>(
              initialValue: _workerId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Mas’ul ishchi', border: OutlineInputBorder()),
              items: widget.workers.map((worker) => DropdownMenuItem(
                value: worker.id,
                child: Text(worker.fullName,
                    overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) => setState(() => _workerId = value),
            ),
            const SizedBox(height: 12),
          ],
          if (!_result) ...[
            TextField(controller: _title, maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Ish nomi',
                hintText: 'Masalan, yerto‘lani tekshirish',
                border: OutlineInputBorder(),
              )),
            const SizedBox(height: 8),
          ],
          TextField(controller: _description, minLines: 3, maxLines: 5,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: _result ? 'Nima ish bajarildi?' : 'Ish tavsifi',
              border: const OutlineInputBorder(),
            )),
          const SizedBox(height: 8),
          if (!_result) ...[
            TextField(controller: _location,
              decoration: const InputDecoration(
                labelText: 'Manzil (ixtiyoriy)',
                hintText: 'Ipak yo‘li, 50-uy',
                border: OutlineInputBorder(),
              )),
            const SizedBox(height: 16),
          ],
          WorkMediaPicker(
            files: _files,
            requiredMedia: !_assignment && !_edit,
            onChanged: (files) => setState(() => _files = files),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error)),
          ],
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.send_rounded),
          label: Text(_edit ? 'O‘zgarishlarni saqlash'
            : _assignment ? 'Vazifa berish' : 'Yuborish'),
        )),
      ],
    ));
  }
}
