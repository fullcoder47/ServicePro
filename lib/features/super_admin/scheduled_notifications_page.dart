import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

class ScheduledNotificationsPage extends StatefulWidget {
  const ScheduledNotificationsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<ScheduledNotificationsPage> createState() => _ScheduledNotificationsPageState();
}

class _ScheduledNotificationsPageState extends State<ScheduledNotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.appState.refreshScheduledNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final items = List<ScheduledNotification>.of(appState.scheduledNotifications)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final colors = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => appState.refreshScheduledNotifications(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primaryContainer,
                  colors.secondaryContainer.withValues(alpha: .72),
                  colors.surfaceContainerHighest,
                ],
              ),
              border: Border.all(color: colors.primary.withValues(alpha: .22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      child: const Icon(Icons.notifications_active_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        appState.tr('scheduled_notifications'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  appState.tr('scheduled_notifications_subtitle'),
                  style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: appState.loading ? null : () => _openEditor(context),
                  icon: const Icon(Icons.add_alarm_rounded),
                  label: Text(appState.tr('new_schedule')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            SectionCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 42, color: colors.primary),
                    const SizedBox(height: 10),
                    const Text(
                      'Hozircha rejali bildirishnoma yo‘q.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yangi reja yarating: kun, sana, vaqt va matnni tanlang.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in items)
              _ScheduleCard(
                item: item,
                appState: appState,
                onEdit: () => _openEditor(context, item: item),
              ),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {ScheduledNotification? item}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ScheduleEditorPage(appState: widget.appState, item: item),
      ),
    );
    if (saved == true && mounted) {
      await widget.appState.refreshScheduledNotifications();
    }
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.item, required this.appState, required this.onEdit});

  final ScheduledNotification item;
  final AppState appState;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: item.isActive ? colors.primaryContainer : colors.surfaceContainerHighest,
              child: Icon(item.isActive ? Icons.notifications_active_rounded : Icons.notifications_off_rounded),
            ),
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${item.daysLabel} • ${item.sendTime} • ${item.isActive ? appState.tr('active') : appState.tr('inactive')}'),
            trailing: IconButton.filledTonal(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
            ),
          ),
          if (item.body.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.body),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 18),
                label: Text('Toshkent vaqti: ${item.sendTime}'),
              ),
              if (item.lastSentAt != null)
                Chip(
                  avatar: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text('Oxirgi: ${_dateTime(item.lastSentAt!)}'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: appState.loading
                      ? null
                      : () async {
                          final ok = await appState.sendScheduledNotificationNow(item);
                          if (!context.mounted) return;
                          _snack(context, ok ? appState.tr('sent_now') : (appState.errorMessage ?? appState.tr('error_unknown')));
                        },
                  icon: const Icon(Icons.send_rounded),
                  label: Text(appState.tr('send_now')),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: appState.loading
                    ? null
                    : () async {
                        final ok = await appState.deleteScheduledNotification(item.id);
                        if (!context.mounted) return;
                        _snack(context, ok ? appState.tr('scheduled_deleted') : (appState.errorMessage ?? appState.tr('error_unknown')));
                      },
                icon: const Icon(Icons.delete_forever_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleEditorPage extends StatefulWidget {
  const _ScheduleEditorPage({required this.appState, this.item});

  final AppState appState;
  final ScheduledNotification? item;

  @override
  State<_ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends State<_ScheduleEditorPage> {
  late final TextEditingController title;
  late final TextEditingController body;
  late TimeOfDay time;
  late bool isActive;
  late bool useSpecificDate;
  DateTime? specificDate;
  final weekdays = <int>{};

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    title = TextEditingController(text: item?.title ?? 'ServicePro eslatma');
    body = TextEditingController(text: item?.body ?? 'Bugungi arizalar va chatlarni tekshirib qo‘ying.');
    final parts = (item?.sendTime ?? '09:00').split(':');
    time = TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    isActive = item?.isActive ?? true;
    useSpecificDate = item?.specificDate != null;
    specificDate = item?.specificDate;
    weekdays.addAll(item?.weekdays ?? <int>[1, 2, 3, 4, 5, 6, 7]);
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? appState.tr('new_schedule') : appState.tr('edit')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.title_rounded),
                    labelText: appState.tr('title'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.message_rounded),
                    labelText: appState.tr('text'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const LocalizedText('Vaqt'),
                  subtitle: Text('Toshkent vaqti: ${_timeText(time)}'),
                  trailing: FilledButton.tonal(
                    onPressed: _pickTime,
                    child: const LocalizedText('Tanlash'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
                  title: Text(isActive ? appState.tr('active') : appState.tr('inactive')),
                  subtitle: const LocalizedText('O‘chirilsa, avtomatik notification yuborilmaydi.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(appState.tr('week_days')), icon: const Icon(Icons.calendar_view_week_rounded)),
                    ButtonSegment(value: true, label: Text(appState.tr('specific_date')), icon: const Icon(Icons.event_rounded)),
                  ],
                  selected: {useSpecificDate},
                  onSelectionChanged: (value) => setState(() => useSpecificDate = value.first),
                ),
                const SizedBox(height: 12),
                if (useSpecificDate)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available_rounded),
                    title: Text(specificDate == null ? 'Sana tanlanmagan' : _date(specificDate!)),
                    subtitle: const LocalizedText('Bildirishnoma faqat shu sana va tanlangan vaqtda ketadi.'),
                    trailing: FilledButton.tonal(
                      onPressed: _pickDate,
                      child: const LocalizedText('Sana'),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => setState(() {
                            weekdays
                              ..clear()
                              ..addAll([1, 2, 3, 4, 5, 6, 7]);
                          }),
                          icon: const Icon(Icons.done_all_rounded),
                          label: Text(appState.tr('every_day')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(weekdays.clear),
                          icon: const Icon(Icons.clear_all_rounded),
                          label: const LocalizedText('Tozalash'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in _weekdayNames.entries)
                        FilterChip(
                          selected: weekdays.contains(entry.key),
                          label: Text(entry.value),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              weekdays.add(entry.key);
                            } else {
                              weekdays.remove(entry.key);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.primary.withValues(alpha: .25)),
                  ),
                  child: const Text(
                    'Avtomatik yuborish Supabase Edge Function scheduler orqali ishlaydi. Scheduler har 1 daqiqada ishga tushsa, notification tanlangan Toshkent vaqtida kechikmay yuboriladi.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: appState.loading ? null : _save,
            icon: appState.loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(appState.tr('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked != null) setState(() => time = picked);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: specificDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => specificDate = picked);
  }

  Future<void> _save() async {
    final ok = await widget.appState.saveScheduledNotification(
      id: widget.item?.id,
      title: title.text,
      body: body.text,
      sendTime: _timeText(time),
      weekdays: useSpecificDate ? <int>[] : weekdays.toList(),
      specificDate: useSpecificDate ? specificDate : null,
      isActive: isActive,
    );
    if (!mounted) return;
    _snack(context, ok ? widget.appState.tr('scheduled_saved') : (widget.appState.errorMessage ?? widget.appState.tr('error_unknown')));
    if (ok) Navigator.pop(context, true);
  }
}

const _weekdayNames = <int, String>{
  1: 'Dushanba',
  2: 'Seshanba',
  3: 'Chorshanba',
  4: 'Payshanba',
  5: 'Juma',
  6: 'Shanba',
  7: 'Yakshanba',
};

String _timeText(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

String _dateTime(DateTime value) {
  final d = value.toLocal();
  return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}
