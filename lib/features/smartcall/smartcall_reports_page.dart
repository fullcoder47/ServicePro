import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/supabase_config.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';

/// Read-only SmartCall reports. Calls themselves are managed on smartcall.uz.
class SmartCallReportsPage extends StatefulWidget {
  const SmartCallReportsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<SmartCallReportsPage> createState() => _SmartCallReportsPageState();
}

class _SmartCallReportsPageState extends State<SmartCallReportsPage> {
  bool _loading = true;
  String? _error;
  String _companyId = '';
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _calls = [];
  List<Map<String, dynamic>> _snapshots = [];
  int _generation = 0;

  bool get _super => widget.appState.currentProfile?.role == UserRole.superAdmin;

  @override
  void initState() {
    super.initState();
    if (!_super) _companyId = widget.appState.currentProfile?.companyId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final db = widget.appState.client;
      // RLS also enforces the company filter on the server, not only here.
      final campaigns = await db.from('smartcall_campaigns')
          .select('id,company_id,group_name,external_group_id,created_at')
          .order('group_name');
      final events = await db.from('smartcall_pressed_one_events')
          .select('id,company_id,campaign_id,phone,operator_name,call_duration_seconds,clicked_at')
          .order('clicked_at', ascending: false).limit(200);
      final calls = await db.from('smartcall_calls')
          .select('id,company_id,campaign_id,phone,status,dialed_at,answered,pressed_one,duration_seconds,operator_name,recording_url')
          .order('dialed_at', ascending: false).limit(100);
      final snapshots = await db.from('smartcall_campaign_snapshots')
          .select('id,company_id,campaign_id,total_calls,answered_calls,pressed_one_calls,snapshot_at,source')
          .order('snapshot_at', ascending: false).limit(200);
      if (!mounted || generation != _generation) return;
      setState(() {
        _campaigns = List<Map<String, dynamic>>.from(campaigns);
        _events = List<Map<String, dynamic>>.from(events);
        _calls = List<Map<String, dynamic>>.from(calls);
        _snapshots = List<Map<String, dynamic>>.from(snapshots);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Hisobot yuklanmadi: $error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  String _companyName(String? id) =>
      widget.appState.companyById(id)?.name ?? 'Tashkilot';

  String _groupName(String? id) {
    for (final item in _campaigns) {
      if (item['id'] == id) return '${item['group_name']}';
    }
    return 'SmartCall guruhi';
  }

  String _date(dynamic raw) {
    final parsed = DateTime.tryParse('$raw')?.toLocal();
    if (parsed == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.day)}.${two(parsed.month)}.${parsed.year} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String _duration(dynamic raw) {
    if (raw is! num) return '—';
    final total = raw.toInt();
    return '${total ~/ 60}m ${total % 60}s';
  }

  String _eventSubtitle(Map<String, dynamic> event) {
    final group = _groupName(event['campaign_id']?.toString());
    final company = _super ? ' • ${_companyName(event['company_id']?.toString())}' : '';
    final operator = event['operator_name'] ?? '—';
    final duration = _duration(event['call_duration_seconds']);
    return '$group$company\nOperator: $operator • Suhbat: $duration';
  }

  String _callSubtitle(Map<String, dynamic> call) {
    final group = _groupName(call['campaign_id']?.toString());
    final status = call['status'] ?? 'unknown';
    final duration = _duration(call['duration_seconds']);
    final pressed = call['pressed_one'] == true ? 'Ha' : 'Yo‘q';
    return '$group • $status • $duration • 1 bosgan: $pressed';
  }

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> source) =>
      _companyId.isEmpty ? source : source.where((r) => r['company_id'] == _companyId).toList();

  Future<void> _mapGroup() async {
    if (!_super) return;
    final nameController = TextEditingController();
    final idController = TextEditingController();
    String company = _companyId;
    if (company.isEmpty && widget.appState.companies.isNotEmpty) {
      company = widget.appState.companies.first.id;
    }
    bool saving = false;
    try {
      await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
        builder: (context, changeState) => AlertDialog(
          title: const Text('SmartCall guruhini tashkilotga bog‘lash'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Guruh nomini SmartCall sahifasidagidek aniq yozing. '
                  'Bir nom faqat bitta tashkilotga biriktiriladi.'),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: company.isEmpty ? null : company,
                decoration: const InputDecoration(labelText: 'Tashkilot'),
                items: widget.appState.companies.map((c) => DropdownMenuItem(
                  value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: saving ? null : (id) => changeState(() => company = id ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(controller: nameController, maxLength: 160,
                decoration: const InputDecoration(labelText: 'SmartCall guruhi nomi *')),
              TextField(controller: idController, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Guruh ID (ixtiyoriy)')),
            ],
          )),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Bekor qilish')),
            FilledButton(onPressed: saving ? null : () async {
              final name = nameController.text.trim();
              final groupId = int.tryParse(idController.text.trim());
              if (company.isEmpty || name.isEmpty ||
                  (idController.text.trim().isNotEmpty && groupId == null)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Tashkilot, guruh nomi va ID ni tekshiring.')));
                return;
              }
              changeState(() => saving = true);
              try {
                await widget.appState.client.from('smartcall_campaigns').insert({
                  'company_id': company,
                  'group_name': name,
                  if (groupId != null) 'external_group_id': groupId,
                });
                if (!context.mounted) return;
                Navigator.pop(dialogContext);
                await _reload();
              } catch (error) {
                if (!context.mounted) return;
                changeState(() => saving = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Guruh bog‘lanmadi: $error')));
              }
            }, child: const Text('Bog‘lash')),
          ],
        ),
      ));
    } finally {
      nameController.dispose();
      idController.dispose();
    }
  }

  Future<void> _issueWebhook() async {
    if (!_super) return;
    final proceed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Webhook manzili yaratilsinmi?'),
      content: const Text('Maxfiy URL faqat bir marta ko‘rsatiladi. Uni hech kimga '
          'yubormang; faqat SmartCall → Webhook sozlamasiga kiriting. '
          'Avval SmartCall guruhlarini tashkilotlarga bog‘lang.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yaratish')),
      ],
    ));
    if (proceed != true || !mounted) return;
    try {
      final token = await widget.appState.client.rpc('smartcall_issue_webhook_token');
      if (!mounted) return;
      final url = '${SupabaseConfig.url}/functions/v1/smartcall-webhook?token=$token';
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('SmartCall webhook URL'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quyidagi manzilni SmartCall Webhook bo‘limiga kiriting. '
                'Bu URL maxfiy; uni ommaga tarqatmang.'),
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Eslatma: webhook faqat “1 bosib operator bilan gaplashgan” '
                'qo‘ng‘iroqlar haqida xabar beradi.'),
          ],
        )),
        actions: [
          TextButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) Navigator.pop(context);
          }, icon: const Icon(Icons.copy), label: const Text('Nusxalash')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Yopish')),
        ],
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Webhook URL yaratilmadi: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = _visible(_campaigns);
    final events = _visible(_events);
    final calls = _visible(_calls);
    final snapshots = _visible(_snapshots);
    final latest = <String, Map<String, dynamic>>{};
    for (final row in snapshots) {
      latest.putIfAbsent('${row['campaign_id']}', () => row);
    }
    final latestTotals = latest.values.toList();
    final totalsAvailable = latestTotals.isNotEmpty;
    final totalCalls = latestTotals.fold<int>(0, (sum, r) => sum + (r['total_calls'] as int? ?? 0));
    final answered = latestTotals.fold<int>(0, (sum, r) => sum + (r['answered_calls'] as int? ?? 0));
    final pressed = latestTotals.fold<int>(0, (sum, r) => sum + (r['pressed_one_calls'] as int? ?? 0));

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        Row(children: [
          const Expanded(child: Text('SmartCall • qo‘ng‘iroqlar hisoboti',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          IconButton(onPressed: _loading ? null : _reload,
            tooltip: 'Yangilash', icon: const Icon(Icons.refresh)),
        ]),
        const Text('Qo‘ng‘iroqlar SmartCall saytida amalga oshiriladi. '
            'ServicePro faqat tasdiqlangan hisobotlarni ko‘rsatadi.'),
        if (_super) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _companyId,
            decoration: const InputDecoration(labelText: 'Tashkilot bo‘yicha'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Barcha tashkilotlar')),
              ...widget.appState.companies.map((c) => DropdownMenuItem(
                value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (value) => setState(() => _companyId = value ?? ''),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _mapGroup,
              icon: const Icon(Icons.link), label: const Text('Guruhni ulash')),
            OutlinedButton.icon(onPressed: _issueWebhook,
              icon: const Icon(Icons.key), label: const Text('Webhook manzili')),
          ]),
        ],
        if (_loading) const Padding(padding: EdgeInsets.all(22),
          child: Center(child: CircularProgressIndicator())),
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
        if (!_loading && _error == null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _NumberChip(label: 'Ulangan guruhlar', value: '${campaigns.length}', icon: Icons.groups_2),
            _NumberChip(label: 'Webhook: 1 bosgan', value: '${events.length}${events.length == 200 ? '+' : ''}',
              icon: Icons.touch_app),
            _NumberChip(label: 'Jami qo‘ng‘iroq', value: totalsAvailable ? '$totalCalls' : '—',
              icon: Icons.call),
            _NumberChip(label: 'Javob berilgan', value: totalsAvailable ? '$answered' : '—',
              icon: Icons.call_received),
            _NumberChip(label: 'Hisobotda 1 bosgan', value: totalsAvailable ? '$pressed' : '—',
              icon: Icons.check_circle_outline),
          ]),
          const SizedBox(height: 10),
          if (!totalsAvailable) const _Notice(
            'SmartCall umumiy qo‘ng‘iroqlar ro‘yxati va audio yozuvlar uchun API taqdim etmagani '
            'sabab jami/javob berilgan/o‘tkazib yuborilgan sonlar hozircha ulanmagan. '
            'Webhook faqat “1 ni bosib operator bilan gaplashgan” holatlarni yuboradi.'),
          if (campaigns.isEmpty) const _Notice(
            'Hali SmartCall guruhi bog‘lanmagan. Superadmin avval SmartCall dagi guruh nomini '
            'tegishli BSKga biriktirishi va webhook URLni SmartCallga kiritishi kerak.'),
          const SizedBox(height: 16),
          Text('Guruhlar', style: Theme.of(context).textTheme.titleMedium),
          for (final campaign in campaigns) Card(child: ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: Text('${campaign['group_name']}'),
            subtitle: Text('${_companyName(campaign['company_id']?.toString())}'
                '${campaign['external_group_id'] == null ? '' : ' • ID: ${campaign['external_group_id']}'}'),
          )),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('“1 ni bosgan” voqealar (so‘nggi 200 ta)',
              style: Theme.of(context).textTheme.titleMedium)),
          ]),
          if (events.isEmpty) const ListTile(
            leading: Icon(Icons.notifications_none), title: Text('Hozircha webhook ma’lumoti yo‘q'),
            subtitle: Text('SmartCall webhook manzili sozlanib, chaqiruvda 1 bosilganda keladi.')),
          for (final event in events) Card(child: ListTile(
            leading: const Icon(Icons.touch_app, color: Colors.green),
            title: Text('${event['phone']} • ${_date(event['clicked_at'])}'),
            subtitle: Text(_eventSubtitle(event)),
            isThreeLine: true,
          )),
          const SizedBox(height: 16),
          Text('Qo‘ng‘iroqlar tafsiloti (so‘nggi 100 ta)',
            style: Theme.of(context).textTheme.titleMedium),
          if (calls.isEmpty) const ListTile(
            leading: Icon(Icons.record_voice_over_outlined),
            title: Text('Qo‘ng‘iroqlar tarixi ulanmagan'),
            subtitle: Text('Barcha holatlar, aniq vaqtlar va audio yozuvlar uchun '
                'SmartCall hisobot/recording API’si talab qilinadi.')),
          for (final call in calls) Card(child: ListTile(
            leading: Icon(call['answered'] == true ? Icons.call_received : Icons.call_missed),
            title: Text('${call['phone']} • ${_date(call['dialed_at'])}'),
            subtitle: Text(_callSubtitle(call)),
            trailing: call['recording_url'] is String &&
                Uri.tryParse('${call['recording_url']}')?.scheme == 'https'
                ? IconButton(tooltip: 'Audio yozuv', icon: const Icon(Icons.play_circle_outline),
                  onPressed: () async {
                    final url = Uri.tryParse('${call['recording_url']}');
                    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
                  }) : null,
          )),
        ],
      ]),
    );
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 23), const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    ]),
  ));
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      const Icon(Icons.info_outline), const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ])),
  );
}
