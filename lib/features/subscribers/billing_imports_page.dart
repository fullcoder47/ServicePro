import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import 'billing_excel.dart';
import 'billing_repository.dart';

class BillingImportsPage extends StatefulWidget {
  const BillingImportsPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<BillingImportsPage> createState() => _BillingImportsPageState();
}

class _BillingImportsPageState extends State<BillingImportsPage> {
  String? _company;
  String _progress = '';
  String? _error;
  bool _busy = false;
  List<BillingImport> _imports = [];
  int _historyPage = 0, _totalImports = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final result = await SubscriberBillingRepository(widget.appState).imports(_company,
        offset: _historyPage * 30);
      if (mounted) setState(() { _imports = result.items; _totalImports = result.total; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _companyName(String id) {
    for (final c in widget.appState.companies) { if (c.id == id) return c.name; }
    return 'Tashkilot';
  }

  Future<void> _importExcel() async {
    if (_busy) return;
    final companyId = _company;
    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avval tashkilotni tanlang.')));
      return;
    }
    setState(() { _busy = true; _error = null; _progress = 'Excel tanlanmoqda…'; });
    try {
      final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: const ['xlsx']);
      if (file == null) return;
      if (!file.name.toLowerCase().endsWith('.xlsx')) throw const FormatException('Faqat .xlsx faylni yuklang.');
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('Fayl bo‘sh yoki o‘qib bo‘lmadi.');
      setState(() => _progress = 'Jadval tekshirilmoqda…');
      final book = BillingWorkbook.parse(bytes);
      final companyName = _companyName(companyId).toLowerCase()
        .replaceAll(RegExp(r'\b(mchj|ооо|masuliyati|cheklangan|jamiyati)\b'), '').trim();
      if (book.companyNames.isNotEmpty && !book.companyNames.every((name) {
        final source = name.toLowerCase().replaceAll(RegExp(r'\b(mchj|ооо|masuliyati|cheklangan|jamiyati)\b'), '').trim();
        return source.contains(companyName) || companyName.contains(source);
      })) {
        throw FormatException('Excel ichidagi kompaniya nomi tanlangan “${_companyName(companyId)}” bilan mos kelmadi.');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Excel importini tasdiqlash'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tashkilot: ${_companyName(companyId)}'),
            Text('Fayl: ${file.name}'),
            const SizedBox(height: 12),
            Text('Abonentlar: ${book.accounts.length} ta'),
            Text('Oylik yozuvlar: ${book.ledger.length} ta'),
            Text('To‘lov / qayta hisob: ${book.transactions.length} ta'),
            const SizedBox(height: 12),
            const Text('Yangi balanslar e’lon qilinadi. Oldingi Excel va barcha tarixiy balanslar saqlanadi.'),
            const SizedBox(height: 8),
            const Text('Bu faylda mavjud bo‘lmagan abonentlar faol ro‘yxatdan chiqariladi, lekin tarixdan o‘chirilmaydi.',
              style: TextStyle(fontSize: 12)),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tasdiqlab yuklash')),
        ],
      ));
      if (confirmed != true || !mounted) return;

      final repository = SubscriberBillingRepository(widget.appState);
      setState(() => _progress = 'Import yaratilmoqda…');
      final batch = await repository.beginImport(companyId, file.name, book.hash);
      final id = '${batch['id']}';
      setState(() => _progress = 'Asl Excel xavfsiz saqlanmoqda…');
      await repository.uploadOriginal('${batch['storage_path']}', bytes);
      setState(() => _progress = '${book.accounts.length} ta abonent tekshirilmoqda…');
      await repository.stageRows(id, book.accounts);
      if (book.ledger.isNotEmpty) {
        setState(() => _progress = 'Oylik hisob-kitob yuklanmoqda…');
        await repository.stageLedger(id, book.ledger);
      }
      if (book.transactions.isNotEmpty) {
        setState(() => _progress = 'To‘lovlar tarixi yuklanmoqda…');
        await repository.stageTransactions(id, book.transactions);
      }
      setState(() => _progress = 'Balanslar yangilanmoqda…');
      await repository.publish(id, book.accounts.length);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:
          Text('${book.accounts.length} ta abonent yangilandi. Oldingi tarix saqlandi.')));
        _historyPage = 0;
        await _load();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Import yakunlanmadi: $e\nOldingi e’lon qilingan balanslar o‘zgarmadi.');
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  Future<void> _download(BillingImport item) async {
    try {
      setState(() { _busy = true; _progress = 'Excel yuklab olinmoqda…'; });
      final bytes = await SubscriberBillingRepository(widget.appState).downloadOriginal(item);
      await FilePicker.saveFile(dialogTitle: 'Excel faylni saqlash', fileName: item.filename, bytes: bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'Faylni yuklab olishda xatolik: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerHigh])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.inventory_2_rounded, size: 34), const SizedBox(height: 10),
          Text('Excel billing importlari', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Joriy abonentlar va o‘chirilmaydigan importlar tarixi.'),
        ])),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(initialValue: _company, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tashkilotni tanlang',
          prefixIcon: Icon(Icons.apartment_rounded), border: OutlineInputBorder()),
        items: [const DropdownMenuItem(value: null, child: Text('Barcha tashkilotlar')),
          for (final c in widget.appState.companies)
            DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
        onChanged: _busy ? null : (id) {
          setState(() { _company = id; _historyPage = 0; }); _load();
        }),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _busy || _company == null ? null : _importExcel,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Excel (.xlsx) yuklash')),
      const SizedBox(height: 10),
      const Text('Yuklashdan avval faylda kamida “Hisob raqami” va “Balans” ustunlari bo‘lishi kerak. '
        'Oylik hisob-kitob, to‘lov va qayta hisob-kitoblar uchun alohida varaqlar ixtiyoriy.',
        style: TextStyle(fontSize: 12)),
      if (_busy) ...[const SizedBox(height: 14), const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(8), child: Text(_progress))],
      if (_error != null) Card(color: colors.errorContainer,
        child: Padding(padding: const EdgeInsets.all(15), child: Text(_error!))),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text('Yuklashlar tarixi',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_imports.isEmpty && _error == null)
        const Card(child: Padding(padding: EdgeInsets.all(22),
          child: Center(child: Text('Hali Excel importi mavjud emas.')))),
      for (final item in _imports)
        Card(margin: const EdgeInsets.symmetric(vertical: 5), child: ListTile(
          leading: CircleAvatar(backgroundColor: item.status == 'published'
            ? colors.primaryContainer : colors.surfaceContainerHighest,
            child: Icon(item.status == 'published' ? Icons.task_alt_rounded : Icons.hourglass_top_rounded)),
          title: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${_companyName(item.companyId)}\n'
            '${billingDate(item.createdAt)} · ${item.rowCount} satr · ${item.status == 'published' ? 'Tasdiqlangan' : 'Tugallanmagan'}'),
          isThreeLine: true,
          onTap: item.status != 'published' ? null : () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => _ImportDetailsPage(appState: widget.appState, item: item))),
          trailing: item.storagePath.isEmpty ? null : IconButton(
            tooltip: 'Asl Excelni yuklab olish', onPressed: _busy ? null : () => _download(item),
            icon: const Icon(Icons.download_rounded)),
        )),
      if (_totalImports > 30)
        Padding(padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(onPressed: _historyPage == 0 || _busy ? null
              : () { setState(() => _historyPage--); _load(); },
              icon: const Icon(Icons.chevron_left_rounded)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${_historyPage + 1} / ${(_totalImports / 30).ceil()}')),
            IconButton.filledTonal(onPressed: (_historyPage + 1) * 30 >= _totalImports || _busy
              ? null : () { setState(() => _historyPage++); _load(); },
              icon: const Icon(Icons.chevron_right_rounded)),
          ])),
      const SizedBox(height: 14),
      const Text('Eslatma: importlar arxivida barcha tasdiqlangan Excel snapshotlari qoladi. '
        'Balansdagi o‘zgarishlar avtomatik ravishda to‘lov deb belgilanmaydi.',
        style: TextStyle(fontSize: 12)),
    ]));
  }
}

class _ImportDetailsPage extends StatefulWidget {
  const _ImportDetailsPage({required this.appState, required this.item});
  final AppState appState;
  final BillingImport item;
  @override
  State<_ImportDetailsPage> createState() => _ImportDetailsPageState();
}

class _ImportDetailsPageState extends State<_ImportDetailsPage> {
  List<Map<String, dynamic>> _rows = [];
  int _page = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.appState.client.from('billing_import_rows')
        .select('ordinal,account_number,address,full_name,balance,contract_status')
        .eq('import_id', widget.item.id)
        .order('ordinal', ascending: true).range(_page*50, _page*50+49);
      if (mounted) {
        setState(() => _rows = (rows as List)
          .map((r) => Map<String, dynamic>.from(r)).toList());
      }
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item.filename, maxLines: 1)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Import: ${billingDate(widget.item.createdAt)} · ${widget.item.rowCount} abonent',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      for (final r in _rows)
        Card(child: ListTile(
          leading: CircleAvatar(child: Text('${r['ordinal'] ?? '—'}')),
          title: Text('${r['account_number']} · ${billingMoney((r['balance'] as num).toDouble())}'),
          subtitle: Text('${r['full_name'] ?? 'Abonent'}\n${r['address'] ?? ''}', maxLines: 3))),
      if (widget.item.rowCount > 50)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: _page == 0 ? null : () { _page--; _load(); },
            icon: const Icon(Icons.chevron_left)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${_page+1}')),
          IconButton.filledTonal(onPressed: (_page+1)*50 >= widget.item.rowCount ? null
            : () { _page++; _load(); }, icon: const Icon(Icons.chevron_right)),
        ]),
    ]));
}
