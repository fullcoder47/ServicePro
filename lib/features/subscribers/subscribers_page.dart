import 'dart:async';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import 'billing_repository.dart';
import 'billing_demo_preview_page.dart';
import 'billing_link_requests_page.dart';
import 'subscriber_detail_page.dart';

class SubscribersPage extends StatefulWidget {
  const SubscribersPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<SubscribersPage> createState() => _SubscribersPageState();
}

class _SubscribersPageState extends State<SubscribersPage> {
  final _query = TextEditingController();
  final _street = TextEditingController();
  final _house = TextEditingController();
  Timer? _debounce;
  List<SubscriberAccount> _accounts = [];
  int _total = 0, _page = 0, _generation = 0;
  bool _busy = true;
  bool _exporting = false;
  String? _error;
  String _company = '', _contract = '', _type = '';
  static const int pageSize = 40;

  @override
  void initState() {
    super.initState();
    final profile = widget.appState.currentProfile;
    if (profile?.role != UserRole.superAdmin) _company = profile?.companyId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose(); _street.dispose(); _house.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () { _page = 0; _load(); });
  }

  Future<void> _load() async {
    final request = ++_generation;
    if (mounted) setState(() { _busy = true; _error = null; });
    try {
      final data = await SubscriberBillingRepository(widget.appState).search(
        companyId: _company, text: _query.text, street: _street.text,
        house: _house.text, type: _type, contract: _contract,
        offset: _page * pageSize, limit: pageSize);
      if (!mounted || request != _generation) return;
      setState(() { _accounts = data.items; _total = data.total; });
    } catch (error) {
      if (mounted && request == _generation) setState(() => _error = '$error');
    } finally {
      if (mounted && request == _generation) setState(() => _busy = false);
    }
  }

  void _changeFilter(void Function() update) {
    setState(() { update(); _page = 0; });
    _load();
  }

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final workbook = Excel.createExcel();
      final sheet = workbook['Sheet1'];
      sheet.appendRow(['№', 'Kompaniya', 'Hisob raqami', 'Abonent', 'Turi',
        'Manzil', 'Balans', 'Shartnoma holati', 'Kadastr raqami']
        .map((v) => TextCellValue(v)).toList());
      final repo = SubscriberBillingRepository(widget.appState);
      var offset = 0;
      while (true) {
        final page = await repo.search(companyId: _company, text: _query.text,
          street: _street.text, house: _house.text, type: _type, contract: _contract,
          offset: offset, limit: 200);
        for (final a in page.items) {
          sheet.appendRow([
            IntCellValue(a.ordinal ?? offset + 1),
            TextCellValue(widget.appState.companyById(a.companyId)?.name ?? ''),
            TextCellValue(a.accountNumber), TextCellValue(a.fullName ?? ''),
            TextCellValue(a.type ?? ''), TextCellValue(a.address),
            DoubleCellValue(a.balance), TextCellValue(a.contractStatus),
            TextCellValue(a.cadastralNumber ?? ''),
          ]);
        }
        offset += page.items.length;
        if (page.items.isEmpty || offset >= page.total) break;
      }
      final encoded = workbook.encode();
      if (encoded == null) throw const FormatException('Excel fayl yaratilmadi.');
      await FilePicker.saveFile(fileName: 'ServicePro_abonentlar.xlsx',
        bytes: Uint8List.fromList(encoded));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Excel eksportida xatolik: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final isSuper = widget.appState.currentProfile?.role == UserRole.superAdmin;
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerHigh])),
        child: Row(children: [
          CircleAvatar(radius: 26, backgroundColor: colors.primary,
            child: Icon(Icons.groups_2_rounded, color: colors.onPrimary, size: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Abonentlar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('Hisob raqami, qarzdorlik va shartnoma holatini boshqarish',
              style: TextStyle(color: colors.onSurfaceVariant)),
          ])),
          if (!_busy) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$_total', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const Text('ta abonent'),
          ]),
        ])),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BillingLinkRequestsPage(
              appState: widget.appState, companyId: _company)));
          if (mounted) _load();
        },
        icon: const Icon(Icons.how_to_reg_rounded),
        label: const Text('Aholining biriktirish so‘rovlari'),
      )),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BillingDemoPreviewPage(
            companyId: _company.isEmpty ? 'DEMO' : _company))),
        icon: const Icon(Icons.science_outlined),
        label: const Text('API ma’lumotlari (demo ko‘rinish)'),
      )),
      const SizedBox(height: 14),
      if (isSuper) ...[
        DropdownButtonFormField<String>(initialValue: _company, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tashkilot', prefixIcon: Icon(Icons.apartment_rounded)),
          items: [const DropdownMenuItem(value: '', child: Text('Barcha tashkilotlar')),
            for (final c in widget.appState.companies)
              DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _changeFilter(() => _company = v ?? '')),
        const SizedBox(height: 12),
      ],
      TextField(controller: _query, onChanged: (_) => _scheduleSearch(),
        decoration: InputDecoration(labelText: 'Qidirish', hintText: 'Hisob raqami, F.I.Sh., manzil, kadastr',
          prefixIcon: const Icon(Icons.search_rounded), border: const OutlineInputBorder(),
          suffixIcon: _query.text.isNotEmpty ? IconButton(onPressed: () { _query.clear(); _scheduleSearch(); },
            icon: const Icon(Icons.close_rounded)) : null)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(width: wide ? 240 : 160, child: TextField(controller: _street,
          onChanged: (_) => _scheduleSearch(), decoration: const InputDecoration(
            labelText: 'Ko‘cha', prefixIcon: Icon(Icons.route_rounded), border: OutlineInputBorder()))),
        SizedBox(width: wide ? 180 : 140, child: TextField(controller: _house,
          onChanged: (_) => _scheduleSearch(), decoration: const InputDecoration(
            labelText: 'Uy', prefixIcon: Icon(Icons.home_outlined), border: OutlineInputBorder()))),
        SizedBox(width: wide ? 190 : 155, child: DropdownButtonFormField<String>(initialValue: _type, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Abonent turi', border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value:'',child:Text('Barcha turlar')),
            DropdownMenuItem(value:'Aholi',child:Text('Aholi')),
            DropdownMenuItem(value:'Noturar',child:Text('Noturar'))],
          onChanged: (v) => _changeFilter(() => _type = v ?? ''))),
        SizedBox(width: wide ? 250 : 180, child: DropdownButtonFormField<String>(initialValue: _contract,
          isExpanded: true, decoration: const InputDecoration(labelText: 'Shartnoma holati',
            border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value:'',child:Text('Barcha holatlar')),
            DropdownMenuItem(value:'Shartnoma yuklanmagan',child:Text('Yuklanmagan')),
            DropdownMenuItem(value:'Shartnoma yuklangan',child:Text('Yuklangan'))],
          onChanged: (v) => _changeFilter(() => _contract = v ?? ''))),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text('Natijalar: $_total ta', style: const TextStyle(fontWeight: FontWeight.w800))),
        OutlinedButton.icon(onPressed: _exporting || _busy ? null : _exportExcel,
          icon: _exporting ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.table_view_rounded),
          label: const Text('Excel')),
        const SizedBox(width: 5),
        IconButton(onPressed: _load, tooltip: 'Yangilash', icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Card(color: colors.errorContainer, child: Padding(padding: const EdgeInsets.all(16),
          child: Text('Abonentlar yuklanmadi. SQL sozlamalari va internetni tekshiring.\n$_error'))),
      if (!_busy && _error == null && _accounts.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Hech qanday abonent topilmadi.'))),
      if (_accounts.isNotEmpty && wide) _table(colors),
      if (_accounts.isNotEmpty && !wide) ...[
        for (final account in _accounts) _mobileCard(account, colors),
      ],
      if (_total > pageSize) Padding(padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: _page <= 0 || _busy ? null : () { setState(() => _page--); _load(); },
            icon: const Icon(Icons.chevron_left_rounded)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${_page + 1} / ${(_total / pageSize).ceil()}')),
          IconButton.filledTonal(onPressed: (_page + 1) * pageSize >= _total || _busy ? null
            : () { setState(() => _page++); _load(); }, icon: const Icon(Icons.chevron_right_rounded)),
        ])),
    ]));
  }

  Widget _table(ColorScheme colors) => Card(clipBehavior: Clip.antiAlias,
    child: Column(children: [
      Container(color: colors.surfaceContainerHigh, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: const Row(children: [
          SizedBox(width: 50, child: Text('№', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Hisob raqami', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('Abonent / turi', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 4, child: Text('Manzil', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Balans', style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 26),
        ])),
      for (final a in _accounts) ...[
        InkWell(onTap: () => _open(a), child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            SizedBox(width: 50, child: Text('${a.ordinal ?? '—'}')),
            Expanded(flex: 2, child: Text(a.accountNumber, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_displayName(a), maxLines: 2),
              Text(a.type?.isNotEmpty == true ? a.type! : 'Turi —', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ])),
            Expanded(flex: 4, child: Text(a.address, maxLines: 2, overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(billingMoney(a.balance),
              style: TextStyle(color: a.balance > 0 ? colors.error : colors.primary, fontWeight: FontWeight.bold))),
            const SizedBox(width: 26, child: Icon(Icons.chevron_right_rounded)),
          ]))),
        const Divider(height: 1),
      ],
    ]));

  Widget _mobileCard(SubscriberAccount a, ColorScheme colors) => Card(
    margin: const EdgeInsets.only(bottom: 10), clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: () => _open(a), child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: colors.primaryContainer,
            child: Text('${a.ordinal ?? '—'}', style: TextStyle(color: colors.onPrimaryContainer))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.accountNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(_displayName(a),
              style: TextStyle(color: colors.onSurfaceVariant)),
          ])),
          const Icon(Icons.chevron_right_rounded),
        ]),
        const SizedBox(height: 12),
        Text(a.address, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(a.type?.isNotEmpty == true ? a.type! : 'Turi —',
            style: TextStyle(color: colors.onSurfaceVariant))),
          Text(billingMoney(a.balance), style: TextStyle(fontWeight: FontWeight.w900,
            color: a.balance > 0 ? colors.error : colors.primary)),
        ]),
      ]))));

  Future<void> _open(SubscriberAccount account) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubscriberDetailPage(
      appState: widget.appState, account: account, allowLink: true)));
    if (mounted) _load();
  }

  String _displayName(SubscriberAccount account) {
    if (account.fullName?.isNotEmpty == true) return account.fullName!;
    if (account.residentProfileId != null) {
      final resident = widget.appState.profileById(account.residentProfileId!);
      if (resident != null) return resident.fullName;
    }
    return 'F.I.Sh. kiritilmagan';
  }
}
