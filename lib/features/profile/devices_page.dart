import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/session_devices_repository.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late final SessionDevicesRepository _repository;
  List<ServiceProDeviceSession> _sessions = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = SessionDevicesRepository(widget.appState.client);
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repository.touchCurrent();
      final sessions = await _repository.listSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().contains('PGRST202') ||
              error.toString().contains('Could not find the function')
          ? 'Qurilmalarni boshqarish uchun Supabase SQL yangilanishi hali o‘rnatilmagan.'
          : 'Sessiyalar ro‘yxatini yuklab bo‘lmadi. Internetni tekshirib qayta urinib ko‘ring.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm({required String title, required String description,
      required String actionLabel}) async {
    if (!mounted) return false;
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _perform(Future<void> Function() work, {bool signOut = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
      if (!mounted) return;
      if (signOut) {
        Navigator.of(context).maybePop();
      } else {
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Qurilmalar ro‘yxati yangilandi.')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Amal bajarilmadi. Internet va sessiya holatini tekshirib qayta urinib ko‘ring.',
        )),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeOne(ServiceProDeviceSession session) async {
    if (session.isCurrent || _busy) return;
    final yes = await _confirm(
      title: 'Qurilmani chiqarish',
      description: '“${session.label}” qurilmasining sessiyasi bekor qilinadi. '
          'O‘sha qurilmada qayta kirish uchun parol talab qilinadi.',
      actionLabel: 'Sessiyani bekor qilish',
    );
    if (yes) await _perform(() => _repository.revokeOne(session.id));
  }

  Future<void> _removeOthers() async {
    if (_busy || _sessions.where((e) => !e.isCurrent).isEmpty) return;
    final yes = await _confirm(
      title: 'Boshqa barcha qurilmalar',
      description: 'Barcha boshqa telefon va kompyuterlardagi sessiyalar bekor qilinadi. '
          'Siz hozirgi qurilmada qolishingiz mumkin.',
      actionLabel: 'Boshqalarini chiqarish',
    );
    if (yes) await _perform(_repository.revokeOtherDevices);
  }

  Future<void> _removeAll() async {
    if (_busy) return;
    final yes = await _confirm(
      title: 'Barcha qurilmalardan chiqish',
      description: 'Hozirgi qurilmangiz ham hisobdan chiqariladi. '
          'Agar begona kirishdan shubhalansangiz, keyin parolni ham almashtiring.',
      actionLabel: 'Barcha sessiyalarni yopish',
    );
    if (yes) await _perform(
      () => widget.appState.logout(allDevices: true), signOut: true,
    );
  }

  Future<void> _renameCurrent(ServiceProDeviceSession session) async {
    if (_busy) return;
    var enteredName = session.label;
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Qurilma nomini o‘zgartirish'),
        content: TextFormField(
          initialValue: session.label,
          onChanged: (value) => enteredName = value,
          maxLength: 64,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Qurilma nomi',
            hintText: 'Masalan: Samandarning noutbuki',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, enteredName),
              child: const Text('Saqlash')),
        ],
      ),
    );
    if (label != null && label.trim().length >= 2) {
      await _perform(() => _repository.renameThisDevice(label));
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'android': return Icons.phone_android_rounded;
      case 'ios': return Icons.phone_iphone_rounded;
      case 'windows': return Icons.laptop_windows_rounded;
      case 'macos': return Icons.laptop_mac_rounded;
      case 'linux': return Icons.computer_rounded;
      case 'web': return Icons.public_rounded;
      default: return Icons.devices_other_rounded;
    }
  }

  String _date(DateTime date) {
    final d = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _sessionCard(ServiceProDeviceSession session) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: session.isCurrent ? colors.primary.withValues(alpha: .55)
            : colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(_platformIcon(session.platform), color: colors.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Wrap(spacing: 7, runSpacing: 6, children: [
                if (session.isCurrent) const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.verified_user_rounded, size: 16),
                  label: Text('Joriy qurilma'),
                ),
                if (session.isOnline) Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.circle, size: 10, color: Colors.green),
                  label: const Text('Hozir faol'),
                  backgroundColor: Colors.green.withValues(alpha: .08),
                ),
                if (session.assuranceLevel == 'aal2') const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.shield_rounded, size: 16),
                  label: Text('2 bosqichli himoya'),
                ),
              ]),
            ])),
          ]),
          const SizedBox(height: 12),
          _detail(Icons.login_rounded, 'Kirilgan vaqt', _date(session.loginAt)),
          _detail(Icons.history_rounded, 'Oxirgi faollik', _date(session.lastSeenAt)),
          if (session.ipAddress.isNotEmpty)
            _detail(Icons.network_check_rounded, 'IP manzil', session.ipAddress),
          if (session.appVersion.isNotEmpty)
            _detail(Icons.apps_rounded, 'ServicePro versiyasi', session.appVersion),
          if (session.platform == 'unknown' && session.userAgent.isNotEmpty)
            _detail(Icons.info_outline_rounded, 'Dastur turi', session.userAgent),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: session.isCurrent
              ? TextButton.icon(
                  onPressed: _busy ? null : () => _renameCurrent(session),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Nomini o‘zgartirish'),
                )
              : OutlinedButton.icon(
                  onPressed: _busy ? null : () => _removeOne(session),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Qurilmani chiqarish'),
                  style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                )),
        ]),
      ),
    );
  }

  Widget _detail(IconData icon, String title, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(width: 115, child: Text(title,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        Expanded(child: SelectableText(value, style: theme.textTheme.bodySmall)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = _sessions.where((session) => !session.isCurrent).toList();
    final current = _sessions.where((session) => session.isCurrent).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kirilgan qurilmalar'),
        actions: [
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _busy || _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _refresh, child: const Text('Qayta urinish')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
                      Card(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(children: [
                            Icon(Icons.shield_outlined, size: 27),
                            SizedBox(width: 12),
                            Expanded(child: Text(
                              'Bu yerda hisobingizga kirgan qurilmalarni ko‘rasiz. '
                              'Notanish qurilmani uchratsangiz, sessiyasini bekor qiling '
                              'va parolingizni almashtiring.',
                            )),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('JORIY QURILMA', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 9),
                      ...current.map(_sessionCard),
                      if (current.isEmpty) const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Joriy sessiya aniqlanmadi. Ro‘yxatni yangilang.'),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: Text('BOSHQA QURILMALAR', style: theme.textTheme.labelLarge)),
                        Text('${others.length} ta', style: theme.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 9),
                      if (others.isEmpty) const Card(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Boshqa ochiq sessiyalar yo‘q.')),
                      )),
                      ...others.map(_sessionCard),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _busy || others.isEmpty ? null : _removeOthers,
                        icon: const Icon(Icons.phonelink_erase_rounded),
                        label: const Text('Boshqa barcha qurilmalarni chiqarish'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _removeAll,
                        icon: const Icon(Icons.logout_rounded),
                        style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        label: const Text('Barcha qurilmalardan chiqish'),
                      ),
                      const SizedBox(height: 12),
                      Text('Eslatma: yangi kirgan qurilmalar avtomatik qayd etiladi. '
                          'Oldin kirilgan ayrim qurilmalar modeli aniqlanmasligi mumkin. '
                          'Bekor qilingan sessiyalarning eski tokenlari muddati tugaguncha '
                          'ayrim so‘rovlar ishlashi mumkin.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  )),
                ),
    );
  }
}
