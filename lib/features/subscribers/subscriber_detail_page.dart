import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import 'billing_repository.dart';

class SubscriberDetailPage extends StatefulWidget {
  const SubscriberDetailPage({super.key, required this.appState, required this.account,
    this.allowLink = false});
  final AppState appState;
  final SubscriberAccount account;
  final bool allowLink;

  @override
  State<SubscriberDetailPage> createState() => _SubscriberDetailPageState();
}

class _SubscriberDetailPageState extends State<SubscriberDetailPage> {
  List<BillingSnapshot> _history = [];
  List<BillingLedgerMonth> _ledger = [];
  List<BillingTransaction> _transactions = [];
  String? _error;
  bool _loading = true;
  String? _linkedProfileId;

  @override
  void initState() {
    super.initState();
    _linkedProfileId = widget.account.residentProfileId;
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final repository = SubscriberBillingRepository(widget.appState);
      final result = await Future.wait<dynamic>([
        repository.history(widget.account), repository.ledger(widget.account),
        repository.transactions(widget.account),
      ]);
      if (!mounted) return;
      setState(() {
        _history = result[0] as List<BillingSnapshot>;
        _ledger = result[1] as List<BillingLedgerMonth>;
        _transactions = result[2] as List<BillingTransaction>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _linkResident() async {
    final people = widget.appState.profiles.where((p) => p.role == UserRole.user &&
        p.companyId == widget.account.companyId).toList()
      ..sort((a,b) => a.fullName.compareTo(b.fullName));
    String term = '';
    final selected = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (ctx, redraw) {
        final filtered = people.where((p) =>
            '${p.fullName} ${p.phone}'.toLowerCase().contains(term.toLowerCase())).toList();
        return AlertDialog(
          title: const Text('Aholi akkauntini bog‘lash'),
          content: SizedBox(width: 430, height: 390,
            child: Column(children: [
              const Text('Faqat manzili va shaxsi tasdiqlangan aholini tanlang.',
                style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                hintText: 'Ism yoki telefon'), onChanged: (value) => redraw(() => term = value)),
              const SizedBox(height: 8),
              Expanded(child: ListView.builder(itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(filtered[i].fullName), subtitle: Text(filtered[i].phone),
                  onTap: () => Navigator.pop(dialogContext, filtered[i].id),
                ))),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Bekor qilish')),
            if (_linkedProfileId != null)
              TextButton(onPressed: () => Navigator.pop(dialogContext, '__unlink__'),
                child: const Text('Bog‘lanishni uzish')),
          ],
        );
      }),
    );
    if (selected == null || !mounted) return;
    try {
      final id = selected == '__unlink__' ? null : selected;
      await SubscriberBillingRepository(widget.appState).linkResident(widget.account, id);
      if (!mounted) return;
      setState(() => _linkedProfileId = id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonent akkaunti yangilandi.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bog‘lashda xato: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(title: const Text('Abonent kartasi'), actions: [
          IconButton(tooltip: 'Yangilash', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 10), child: Column(children: [
            Container(width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [colors.primary, Color.lerp(colors.primary, Colors.black, .25)!]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.account_balance_wallet_rounded, color: colors.onPrimary),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Hisob raqami ${account.accountNumber}',
                    style: TextStyle(color: colors.onPrimary.withValues(alpha: .87), fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 15),
                Text(account.balance > 0 ? 'Joriy qarzdorlik' : account.balance < 0 ? 'Ortiqcha to‘lov' : 'Joriy balans',
                  style: TextStyle(color: colors.onPrimary.withValues(alpha: .8))),
                const SizedBox(height: 4),
                FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown,
                  child: Text(billingMoney(account.balance.abs()), style: TextStyle(
                    color: colors.onPrimary, fontSize: 30, fontWeight: FontWeight.w900))),
                const SizedBox(height: 12),
                Text('Balans oxirgi tasdiqlangan Excel importiga asoslangan.',
                  style: TextStyle(color: colors.onPrimary.withValues(alpha: .78), fontSize: 12)),
              ])),
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: colors.surfaceContainerLow,
                border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(account.fullName?.isNotEmpty == true ? account.fullName!
                  : (_linkedProfileId == null ? null : widget.appState.profileById(_linkedProfileId!)?.fullName)
                    ?? 'Abonent ismi kiritilmagan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _SmallInfo(Icons.location_on_outlined, account.address.isEmpty ? 'Manzil mavjud emas' : account.address),
                const SizedBox(height: 5),
                Wrap(spacing: 12, runSpacing: 6, children: [
                  _SmallInfo(Icons.tag_rounded, '№ ${account.ordinal ?? '—'}'),
                  _SmallInfo(Icons.home_work_outlined, account.type?.isNotEmpty == true ? account.type! : 'Turi ko‘rsatilmagan'),
                  _SmallInfo(Icons.description_outlined, account.contractStatus.isEmpty ? 'Shartnoma —' : account.contractStatus),
                  if (account.cadastralNumber?.isNotEmpty == true)
                    _SmallInfo(Icons.pin_outlined, account.cadastralNumber!),
                ]),
                if (widget.allowLink) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _linkResident,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_linkedProfileId == null ? 'Aholi akkauntini bog‘lash' : 'Bog‘langan akkauntni o‘zgartirish')),
                ],
              ])),
          ])),
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Hisob-kitob'), Tab(text: 'To‘lovlar'),
            Tab(text: 'Qayta hisob'), Tab(text: 'Murojaatlar'),
          ]),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: colors.error))),
          Expanded(child: TabBarView(children: [
            _billingTab(), _transactionTab('payment'), _transactionTab('recalculation'), _ticketTab(),
          ])),
        ]),
      ),
    );
  }

  Widget _billingTab() {
    final byYear = <int,List<BillingLedgerMonth>>{};
    for (final row in _ledger) { byYear.putIfAbsent(row.year, () => []).add(row); }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Oylik hisob-kitob', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_ledger.isEmpty) const _EmptyBilling(text: 'Bu Excelda oylik hisoblanmalar yo‘q. Keyingi importga “Oy”, “Yil”, “Hisoblangan”, “To‘lov” ustunlarini qo‘shish mumkin.'),
      for (final year in (byYear.keys.toList()..sort((a,b) => b.compareTo(a))))
        Card(child: ExpansionTile(title: Text('$year-yil'), initiallyExpanded: year == byYear.keys.reduce((a,b) => a>b?a:b),
          children: [for (final row in byYear[year]!)
            ExpansionTile(title: Text('${_months[row.month-1]} • ${billingMoney(row.amount('closing_balance') ?? 0)}'),
              subtitle: const Text('Oy oxiridagi balans'), children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(children: [
                    _dataLine('Umumiy maydon', row.amount('area')?.toString() ?? '—'),
                    _dataLine('Tarif', _maybeMoney(row.amount('tariff'))),
                    _dataLine('Oy boshida', _maybeMoney(row.amount('opening_balance'))),
                    _dataLine('Hisoblangan', _maybeMoney(row.amount('charged'))),
                    _dataLine('Penya', _maybeMoney(row.amount('penalty'))),
                    _dataLine('To‘lov', _maybeMoney(row.amount('paid'))),
                    _dataLine('Qayta hisob', _maybeMoney(row.amount('recalculated'))),
                    _dataLine('Oy oxirida', _maybeMoney(row.amount('closing_balance'))),
                  ])),
              ]),
          ])),
      const SizedBox(height: 18),
      Text('Excel importlari bo‘yicha balans tarixi',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_history.isEmpty) const _EmptyBilling(text: 'Balans tarixi hali mavjud emas.'),
      for (var i = 0; i < _history.length; i++)
        Card(child: ListTile(leading: CircleAvatar(child: Text('${_history.length-i}')),
          title: Text(billingMoney(_history[i].balance)),
          subtitle: Text('${billingDate(_history[i].date)} · ${_history[i].filename}',
            maxLines: 2, overflow: TextOverflow.ellipsis))),
      const SizedBox(height: 10),
      const Text('Balans farqi alohida to‘lov deb hisoblanmaydi: unga hisoblanma, penya yoki qayta hisob ham ta’sir qilishi mumkin.',
        style: TextStyle(fontSize: 12)),
    ]);
  }

  Widget _transactionTab(String kind) {
    final list = _transactions.where((t) => t.kind == kind).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(kind == 'payment' ? 'To‘lovlar tarixi' : 'Qayta hisob-kitoblar',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (list.isEmpty) _EmptyBilling(text: kind == 'payment'
        ? 'Yuklangan Excelda alohida to‘lov tranzaksiyalari yo‘q. To‘lov qilinmagan degani emas.'
        : 'Yuklangan Excelda qayta hisob-kitob yozuvlari yo‘q.'),
      for (final item in list)
        Card(child: ListTile(
          leading: CircleAvatar(child: Icon(kind == 'payment' ? Icons.payments_rounded : Icons.sync_alt_rounded)),
          title: Text(billingMoney(item.amount)),
          subtitle: Text('${billingDate(item.date)}${item.row['method'] == null ? '' : ' · ${item.row['method']}'}'),
          trailing: item.row['reference'] == null ? null : const Icon(Icons.receipt_long_rounded),
        )),
    ]);
  }

  Widget _ticketTab() {
    final residentId = _linkedProfileId ??
      (widget.appState.currentProfile?.role == UserRole.user ? widget.appState.currentProfile?.id : null);
    final tickets = widget.appState.tickets.where((t) => t.createdBy == residentId).toList()
      ..sort((a,b) => b.createdAt.compareTo(a.createdAt));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Arizalar tarixi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (residentId == null) const _EmptyBilling(text: 'Arizalarni ko‘rish uchun abonentga aholi akkauntini bog‘lang.'),
      if (residentId != null && tickets.isEmpty) const _EmptyBilling(text: 'Hozircha murojaatlar yo‘q.'),
      for (final ticket in tickets)
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
          title: Text('${ticket.number} · ${ticket.status.label}'),
          subtitle: Text('${billingDate(ticket.createdAt)}\n${ticket.description}', maxLines: 3),
          isThreeLine: true,
        )),
    ]);
  }
}

const _months = ['Yanvar','Fevral','Mart','Aprel','May','Iyun','Iyul','Avgust','Sentyabr','Oktyabr','Noyabr','Dekabr'];
String _maybeMoney(double? value) => value == null ? '—' : billingMoney(value);
Widget _dataLine(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(children: [Expanded(child: Text(label)), Flexible(child: Text(value,
    textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)))]));

class _SmallInfo extends StatelessWidget {
  const _SmallInfo(this.icon, this.value);
  final IconData icon;
  final String value;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(width: 5),
    Flexible(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall)),
  ]);
}

class _EmptyBilling extends StatelessWidget {
  const _EmptyBilling({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18)),
    child: Column(children: [const Icon(Icons.info_outline_rounded, size: 28),
      const SizedBox(height: 10), Text(text, textAlign: TextAlign.center)]));
}
