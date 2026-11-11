import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import 'billing_repository.dart';

/// Company reviewers confirm the resident and the unit before granting access.
/// The original manual linking option in SubscriberDetailPage remains available.
class BillingLinkRequestsPage extends StatefulWidget {
  const BillingLinkRequestsPage({
    super.key, required this.appState, this.companyId,
  });

  final AppState appState;
  final String? companyId;

  @override
  State<BillingLinkRequestsPage> createState() => _BillingLinkRequestsPageState();
}

class _BillingLinkRequestsPageState extends State<BillingLinkRequestsPage> {
  List<BillingLinkRequest> _items = [];
  bool _loading = true;
  String? _error;
  String? _workingId;

  SubscriberBillingRepository get repo => SubscriberBillingRepository(widget.appState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await repo.pendingLinkRequests(companyId: widget.companyId);
      if (mounted) setState(() => _items = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<SubscriberAccount?> _chooseAccount(BillingLinkRequest request) async {
    final initial = request.lookupMethod == 'account'
      ? request.lookupValue
      : (request.lookupValue.split(',').length > 1
          ? request.lookupValue.split(',')[1].trim() : '');
    final input = TextEditingController(text: initial);
    List<SubscriberAccount> found = [];
    bool searching = false;
    bool initialSearchScheduled = false;
    String? error;

    final chosen = await showDialog<SubscriberAccount>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (ctx, redraw) {
        Future<void> search() async {
          redraw(() { searching = true; error = null; });
          try {
            final result = await repo.search(
              companyId: request.companyId, text: input.text.trim(), limit: 30);
            if (ctx.mounted) redraw(() => found = result.items);
          } catch (e) {
            if (ctx.mounted) redraw(() => error = '$e');
          } finally {
            if (ctx.mounted) redraw(() => searching = false);
          }
        }
        if (!initialSearchScheduled) {
          initialSearchScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) search();
          });
        }

        return AlertDialog(
          title: const Text('Abonentni tekshirib tanlang'),
          content: SizedBox(width: 510,
            height: (MediaQuery.sizeOf(ctx).height * .55)
              .clamp(230.0, 430.0).toDouble(),
            child: Column(children: [
            const Text('Manzil, ism-familiya va hisob raqami haqiqatan mos '
              'ekanini tasdiqlang. Natija avtomatik biriktirilmaydi.'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: input,
                onSubmitted: (_) => search(),
                decoration: const InputDecoration(
                  labelText: 'Hisob raqami / ko‘cha / F.I.Sh.',
                  border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              IconButton(onPressed: searching ? null : search,
                icon: const Icon(Icons.search_rounded), tooltip: 'Qidirish'),
            ]),
            if (searching) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: TextStyle(
              color: Theme.of(ctx).colorScheme.error)),
            const SizedBox(height: 12),
            Expanded(child: ListView.builder(
              itemCount: found.length,
              itemBuilder: (_, index) {
                final account = found[index];
                final suggestion = request.suggestedAccountId == account.id;
                return Card(child: ListTile(
                  leading: Icon(suggestion
                    ? Icons.tips_and_updates_rounded : Icons.home_outlined),
                  title: Text('№ ${account.accountNumber}'),
                  subtitle: Text([
                    account.address,
                    if (account.fullName?.isNotEmpty == true) account.fullName!,
                    if (account.residentProfileId != null) 'Avval biriktirilgan',
                    if (suggestion) 'Tizim topgan taxminiy moslik',
                  ].join(' • '), maxLines: 3, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(dialogContext, account),
                ));
              },
            )),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Yopish')),
          ],
        );
      }),
    );
    input.dispose();
    return chosen;
  }

  Future<bool> _confirm(String title, String description) async {
    return await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(title: Text(title),
        content: Text(description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tasdiqlash')),
        ])) ?? false;
  }

  Future<void> _review(BillingLinkRequest request, {required bool approve}) async {
    if (_workingId != null) return;
    SubscriberAccount? selected;
    if (approve) {
      selected = await _chooseAccount(request);
      if (selected == null || !mounted) return;
      final person = widget.appState.profileById(request.profileId);
      final okay = await _confirm('Biriktirishni tasdiqlash',
        '${person?.fullName ?? 'Aholi'} profiliga ${selected.accountNumber} '
        'hisob raqamini biriktirasizmi?\n\n${selected.address}');
      if (!okay || !mounted) return;
    } else {
      final okay = await _confirm('So‘rovni rad etish',
        'Aholining ushbu biriktirish so‘rovini rad etasizmi?');
      if (!okay || !mounted) return;
    }
    setState(() => _workingId = request.id);
    try {
      await repo.reviewLinkRequest(request.id,
        approve: approve, accountId: selected?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        approve ? 'Hisob aholi profiliga biriktirildi.' : 'So‘rov rad etildi.')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Amal bajarilmadi: $e')));
      }
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Biriktirish so‘rovlari'),
        actions: [IconButton(onPressed: _load,
          tooltip: 'Yangilash', icon: const Icon(Icons.refresh_rounded))]),
      body: RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Aholi hisoblarini tasdiqlash',
                style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Hisob raqami yoki manzil orqali yuborilgan so‘rovlarni '
                'tekshiring. Faqat hujjat va yashash manzili tasdiqlangandan so‘ng '
                'abonentni biriktiring. Avvalgi qo‘lda biriktirish usuli ham ishlaydi.'),
            ]))),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Card(color: colors.errorContainer,
            child: Padding(padding: const EdgeInsets.all(16),
              child: Text('So‘rovlar yuklanmadi. SQL yangilanishini tekshiring.\n$_error'))),
          if (!_loading && _error == null && _items.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(22),
              child: Center(child: Text('Hozircha tasdiq kutayotgan so‘rovlar yo‘q.')))),
          for (final request in _items)
            Card(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(request.lookupMethod == 'account'
                    ? Icons.numbers_rounded : Icons.location_on_outlined,
                    color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    widget.appState.profileById(request.profileId)?.fullName
                      ?? 'Aholi profili',
                    style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
                  const Chip(label: Text('Kutilmoqda')),
                ]),
                const SizedBox(height: 6),
                Text(request.lookupMethod == 'account'
                  ? 'Hisob raqami: ${request.lookupValue}'
                  : 'Manzil: ${request.lookupValue}'),
                const SizedBox(height: 4),
                Text(widget.appState.companyById(request.companyId)?.name ?? '',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(onPressed: _workingId != null
                    ? null : () => _review(request, approve: true),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Hisobni tanlash va tasdiqlash')),
                  OutlinedButton.icon(onPressed: _workingId != null
                    ? null : () => _review(request, approve: false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Rad etish')),
                ]),
              ]))),
        ])),
    );
  }
}
