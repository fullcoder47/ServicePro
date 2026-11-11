import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_state.dart';
import 'billing_repository.dart';
import 'demo_billing_api.dart';
import 'subscriber_detail_page.dart';

class MyAccountPage extends StatefulWidget {
  const MyAccountPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  final _accountNumber = TextEditingController();
  final _demoCardStore = DemoPaymentCardStore();
  List<SubscriberAccount> _accounts = [];
  List<BillingLinkRequest> _requests = [];
  List<DemoPaymentCard> _demoCards = [];
  bool _loading = true;
  bool _submitting = false;
  bool _cardBusy = false;
  String? _error;
  String? _requestsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; _requestsError = null; });
    final repo = SubscriberBillingRepository(widget.appState);
    try {
      final found = await repo.ownAccounts();
      if (mounted) setState(() => _accounts = found);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    // Old deployments can still show linked accounts until the new SQL is run.
    try {
      final found = await repo.myLinkRequests();
      if (mounted) setState(() => _requests = found);
    } catch (e) {
      if (mounted) setState(() => _requestsError = '$e');
    }
    try {
      final id = widget.appState.currentProfile?.id ?? '';
      final cards = await _demoCardStore.list(id);
      if (mounted) setState(() => _demoCards = cards);
    } catch (_) {
      if (mounted) _snack('Demo kartalarni yuklash imkoni bo‘lmadi.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestLink(String method) async {
    if (_submitting) return;
    if (method == 'account' && _accountNumber.text.trim().length < 4) {
      _snack('Hisob raqamini to‘liq kiriting.');
      return;
    }
    final profile = widget.appState.currentProfile;
    if (method == 'address' && (profile == null ||
      profile.street.trim().isEmpty || profile.houseNumber.trim().isEmpty)) {
      _snack('Avval yashash manzilingizni to‘ldiring.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await SubscriberBillingRepository(widget.appState).requestAccountLink(
        method: method, accountNumber: _accountNumber.text);
      if (!mounted) return;
      if (result == 'already_linked') {
        _snack('Bu hisob allaqachon profilingizga biriktirilgan.');
      } else {
        _snack('So‘rovingiz yuborildi. Tashkilot tasdiqlagach qarzdorlik ko‘rinadi.');
      }
      _accountNumber.clear();
      await _load();
    } catch (e) {
      if (mounted) _snack('So‘rov yuborilmadi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editAddress() async {
    if (_submitting) return;
    final profile = widget.appState.currentProfile;
    if (profile == null) return;
    final neighborhood = TextEditingController(text: profile.neighborhood);
    final street = TextEditingController(text: profile.street);
    final house = TextEditingController(text: profile.houseNumber);
    final form = GlobalKey<FormState>();
    final edited = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yashash manzilini o‘zgartirish'),
        content: SizedBox(width: 430, child: SingleChildScrollView(
          child: Form(key: form, child:
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Hisobni manzil bo‘yicha izlash uchun uy va xonadon raqamini aniq kiriting.'),
            const SizedBox(height: 14),
            for (final item in [
              (neighborhood, 'Mahalla'),
              (street, 'Ko‘cha (masalan, Ipak yo‘li)'),
              (house, 'Uy va xonadon (masalan, 50, 1)'),
            ]) Padding(padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                controller: item.$1,
                decoration: InputDecoration(labelText: item.$2, border: const OutlineInputBorder()),
                validator: (value) => value == null || value.trim().isEmpty
                  ? 'Bu maydon majburiy' : null,
              )),
          ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: () {
            if (!(form.currentState?.validate() ?? false)) return;
            Navigator.pop(dialogContext, [
              neighborhood.text.trim(), street.text.trim(), house.text.trim(),
            ]);
          }, child: const Text('Saqlash')),
        ],
      ),
    );
    neighborhood.dispose(); street.dispose(); house.dispose();
    if (edited == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await SubscriberBillingRepository(widget.appState).updateResidentHomeAddress(
        neighborhood: edited[0], street: edited[1], houseNumber: edited[2]);
      if (mounted) { setState(() {}); _snack('Manzilingiz muvaffaqiyatli yangilandi.'); }
    } catch (e) {
      if (mounted) _snack('Manzil saqlanmadi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = widget.appState.currentProfile;
    final debt = _accounts.fold<double>(0, (sum, a) => sum + (a.balance > 0 ? a.balance : 0));
    final credit = _accounts.fold<double>(0, (sum, a) => sum + (a.balance < 0 ? -a.balance : 0));
    return RefreshIndicator(onRefresh: _load, child: ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 22 + MediaQuery.paddingOf(context).bottom),
      children: [Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _summaryCard(debt, credit),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_error != null) Card(color: colors.errorContainer,
            child: Padding(padding: const EdgeInsets.all(14),
              child: Text('Hisob ma’lumotlari yuklanmadi. Qayta urinib ko‘ring.\n$_error'))),
          if (_accounts.isNotEmpty) ...[
            _sectionTitle('Xonadonlarim'),
            for (final account in _accounts) _accountCard(account),
          ] else if (!_loading && _error == null) ...[
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 28, color: colors.primary),
              const SizedBox(width: 12),
              const Expanded(child: Text('Hisob hali ulanmagan. Quyida hisob raqami yoki manzil orqali so‘rov yuboring.')),
            ]))),
          ],
          _sectionTitle('To‘lov kartalari'),
          _demoCardSection(),
          _sectionTitle('Hisobni boshqarish'),
          Card(child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.add_link_rounded),
            title: const Text('Hisob raqamini bog‘lash', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Tashkilot tasdig‘idan so‘ng balans ko‘rinadi'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(controller: _accountNumber, enabled: !_submitting,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Hisob raqami', hintText: 'Masalan, 12345678',
                  prefixIcon: Icon(Icons.numbers_rounded), border: OutlineInputBorder())),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _submitting || _requestsError != null ? null : () => _requestLink('account'),
                icon: const Icon(Icons.link_rounded), label: const Text('Hisobni bog‘lash'))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _submitting || _requestsError != null ? null : () => _requestLink('address'),
                icon: const Icon(Icons.home_outlined), label: const Text('Manzil orqali so‘rov'))),
              if (_submitting) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              if (_requestsError != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Text('Biriktirish xizmati sozlanmagan. Billing SQL sozlamalarini tekshiring.',
                  style: TextStyle(color: colors.error))),
            ],
          )),
          Card(child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Mening manzilim'),
            subtitle: Text(profile?.homeAddress.isNotEmpty == true
              ? profile!.homeAddress : 'Manzil kiritilmagan'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _submitting ? null : _editAddress,
          )),
          if (_requests.isNotEmpty) Card(child: ExpansionTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Biriktirish so‘rovlari'),
            subtitle: Text('${_requests.length} ta so‘rov'),
            children: [for (final request in _requests.take(5)) ListTile(
              dense: true,
              title: Text(request.lookupMethod == 'account'
                ? 'Hisob: ${request.lookupValue}' : 'Manzil bo‘yicha so‘rov'),
              subtitle: Text(_linkStatus(request.status)),
              leading: Icon(request.pending ? Icons.schedule_rounded
                : request.status == 'approved' ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: request.pending ? colors.tertiary : colors.primary),
            )],
          )),
        ]),
      ))],
    ));
  }

  Widget _sectionTitle(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium
      ?.copyWith(fontWeight: FontWeight.w800)),
  );

  Widget _summaryCard(double debt, double credit) {
    final linked = _accounts.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF122B49), Color(0xFF246A83)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 25),
          SizedBox(width: 10),
          Expanded(child: Text('Mening hisobim',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
        const SizedBox(height: 22),
        Text(linked ? 'Jami qarzdorlik' : 'Hisob holati',
          style: const TextStyle(color: Color(0xFFD6E9F2))),
        const SizedBox(height: 5),
        Text(linked ? billingMoney(debt) : 'Hisob ulanmagan',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 27)),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.home_outlined, color: Color(0xFFC9F7E9), size: 17),
          const SizedBox(width: 5),
          Expanded(child: Text(linked ? '${_accounts.length} ta hisob biriktirilgan'
            : 'Hisobni quyida bog‘lang',
            style: const TextStyle(color: Color(0xFFD6E9F2), fontSize: 13))),
          if (credit > 0) Flexible(child: Text('Ortiqcha: ${billingMoney(credit)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFFC9F7E9), fontSize: 12))),
        ]),
      ]),
    );
  }

  Widget _accountCard(SubscriberAccount account) {
    final colors = Theme.of(context).colorScheme;
    final debt = account.balance > 0;
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => SubscriberDetailPage(appState: widget.appState, account: account))),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: colors.primaryContainer,
              child: Icon(Icons.home_rounded, color: colors.onPrimaryContainer)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hisob № ${account.accountNumber}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(account.address.isEmpty ? 'Manzil ko‘rsatilmagan' : account.address,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Text(debt ? 'Qarzdorlik' : account.balance < 0
              ? 'Ortiqcha to‘lov' : 'Qarz yo‘q')),
            Text(billingMoney(account.balance.abs()), style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 17,
              color: debt ? colors.error : colors.primary)),
          ]),
        ])),
    ));
  }

  Widget _demoCardSection() {
    final colors = Theme.of(context).colorScheme;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.credit_card_rounded, color: colors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Mening kartalarim',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Chip(label: const Text('DEMO'),
            backgroundColor: colors.tertiaryContainer,
            visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 7),
        Text('Hozircha faqat test. Haqiqiy karta raqami yoki CVV kiritmang.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 12),
        if (_demoCards.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Demo karta qo‘shilmagan',
              style: TextStyle(color: colors.onSurfaceVariant))),
        for (final card in _demoCards) Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Container(
            decoration: BoxDecoration(color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.payment_rounded),
              title: Text(card.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Test karta · real bankka ulanmagan'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Kartani o‘chirish',
                onPressed: _cardBusy ? null : () => _removeDemoCard(card)),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _cardBusy ? null : _addDemoCard,
          icon: const Icon(Icons.add_card_rounded), label: const Text('Demo karta qo‘shish')),
        if (_demoCards.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _cardBusy ? null : _testPayment,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Demo to‘lovni sinash')),
        ],
      ])),
    );
  }

  Future<void> _addDemoCard() async {
    final profileId = widget.appState.currentProfile?.id;
    if (profileId == null) return;
    String lastFour = '';
    String brand = 'UZCARD';
    final selection = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (ctx, redraw) => AlertDialog(
        title: const Text('Demo karta qo‘shish'),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Faqat sinov uchun. To‘liq karta raqami va CVV so‘ralmaydi.'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(initialValue: brand,
              decoration: const InputDecoration(labelText: 'Karta turi'),
              items: const [
                DropdownMenuItem(value: 'UZCARD', child: Text('UZCARD')),
                DropdownMenuItem(value: 'HUMO', child: Text('HUMO')),
              ],
              onChanged: (value) => redraw(() => brand = value ?? 'UZCARD')),
            const SizedBox(height: 12),
            TextField(keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => redraw(() => lastFour = value),
              decoration: const InputDecoration(labelText: 'Oxirgi 4 raqam',
                hintText: '4242', border: OutlineInputBorder())),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: lastFour.length == 4
            ? () => Navigator.pop(dialogContext, {
                'brand': brand, 'lastFour': lastFour,
              }) : null,
            child: const Text('Qo‘shish')),
        ],
      )),
    );
    if (selection == null || !mounted) return;
    setState(() => _cardBusy = true);
    try {
      await _demoCardStore.add(profileId: profileId,
        brand: selection['brand']!, lastFour: selection['lastFour']!);
      final cards = await _demoCardStore.list(profileId);
      if (mounted) setState(() => _demoCards = cards);
      _snack('Demo karta qo‘shildi. Haqiqiy bankka ulanmagan.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  Future<void> _removeDemoCard(DemoPaymentCard card) async {
    final profileId = widget.appState.currentProfile?.id;
    if (profileId == null) return;
    setState(() => _cardBusy = true);
    try {
      await _demoCardStore.remove(profileId, card.id);
      final cards = await _demoCardStore.list(profileId);
      if (mounted) setState(() => _demoCards = cards);
    } catch (_) {
      _snack('Demo kartani o‘chirib bo‘lmadi.');
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  Future<void> _testPayment() async {
    if (_demoCards.isEmpty || _cardBusy) return;
    final approved = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Demo to‘lov'),
        content: const Text('1 000 so‘mlik test operatsiyasi yaratiladi. '
          'Pul yechilmaydi, haqiqiy qarz va to‘lovlar tarixi o‘zgarmaydi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Test qilish')),
        ],
      ));
    if (approved != true || !mounted) return;
    setState(() => _cardBusy = true);
    try {
      final receipt = await const DemoBillingApi().testPayment(
        accountNumber: 'DEMO-1001',
        amountUzS: 1000, card: _demoCards.first);
      _snack('Demo muvaffaqiyatli: ${receipt.number}. Pul yechilmadi.');
    } catch (e) {
      _snack('Demo to‘lov bajarilmadi: $e');
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  String _linkStatus(String status) {
    switch (status) {
      case 'pending': return 'Tasdiq kutilmoqda';
      case 'approved': return 'Tasdiqlangan';
      case 'rejected': return 'Rad etilgan';
      case 'cancelled': return 'Yangisiga almashtirilgan';
      default: return status;
    }
  }
}
