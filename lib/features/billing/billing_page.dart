import 'dart:ui' show ImageFilter;

import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Application-wide visual billing gate. It is intentionally rendered above
/// MaterialApp's Navigator so pushed routes, dialogs and desktop controls are
/// equally non-interactive. Guests, residents and Super Admin are unaffected.
class BillingAccessGate extends StatefulWidget {
  const BillingAccessGate({super.key, required this.appState, required this.child});
  final AppState appState;
  final Widget child;

  @override
  State<BillingAccessGate> createState() => _BillingAccessGateState();
}

class _BillingAccessGateState extends State<BillingAccessGate> {
  bool _refreshing = false;
  bool _loggingOut = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.appState.refreshBillingStatus();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await widget.appState.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Chiqishda xatolik. Qayta urinib ko‘ring.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isBillingBlocked) return widget.child;
    final colors = Theme.of(context).colorScheme;
    final companyId = widget.appState.currentProfile?.companyId;
    final company = widget.appState.companyById(companyId);
    final subscription = widget.appState.subscriptionForCompany(companyId);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: true,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: widget.child,
          ),
        ),
        ColoredBox(color: colors.scrim.withValues(alpha: .59)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(26),
                  clipBehavior: Clip.antiAlias,
                  elevation: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(17),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(Icons.lock_person_rounded,
                              size: 37, color: colors.onErrorContainer),
                        ),
                        const SizedBox(height: 16),
                        Text('Tashkilot vaqtincha bloklangan',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(company?.name ?? 'Tashkilot',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Text(
                          'Super administrator tashkilot faoliyatini vaqtincha '
                          'to‘xtatgan. Direktor, administrator va ishchilar '
                          'uchun bo‘limlar hozircha yopiq. '
                          'Blok olib tashlangach, ilova yana ishlaydi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
                        ),
                        if (subscription?.note?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text('Izoh: ${subscription!.note}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant)),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _refreshing ? null : _refresh,
                            icon: _refreshing
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded),
                            label: const Text('Holatni tekshirish'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loggingOut ? null : _logout,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Hisobdan chiqish'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.appState.refreshBilling();
      if (widget.appState.currentProfile?.role == UserRole.superAdmin) {
        widget.appState.ensureAllCompanySubscriptions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.appState.currentProfile?.role;
    if (role == UserRole.superAdmin) return _SuperBilling(appState: widget.appState);
    return _CompanyBilling(appState: widget.appState);
  }
}

class _CompanyBilling extends StatelessWidget {
  const _CompanyBilling({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final profile = appState.currentProfile!;
    final company = appState.companyById(profile.companyId);
    final sub = appState.subscriptionForCompany(profile.companyId);
    final payments = profile.companyId == null ? <CompanyPayment>[] : appState.paymentsForCompany(profile.companyId!);
    final colors = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => appState.refreshBilling(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroBillingCard(
            title: appState.tr('billing_title'),
            subtitle: company?.name ?? appState.tr('all_companies'),
            amount: sub == null ? 0 : sub.payableAmount,
            status: sub?.status.label ?? 'Trial',
            days: sub?.remainingDays ?? 0,
          ),
          const SizedBox(height: 12),
          if (sub == null)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appState.tr('billing_sql_missing'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => appState.refreshBilling(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(appState.tr('refresh')),
                  ),
                ],
              ),
            )
          else
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appState.tr('subscription_status'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _InfoTile(icon: Icons.verified_rounded, label: appState.tr('subscription_status'), value: sub.status.label),
                  _InfoTile(icon: Icons.sell_rounded, label: appState.tr('monthly_price'), value: _money(sub.monthlyPrice)),
                  _InfoTile(icon: Icons.percent_rounded, label: appState.tr('discount_percent'), value: '${sub.discountPercent}%'),
                  _InfoTile(icon: Icons.local_offer_rounded, label: appState.tr('discount_amount'), value: _money(sub.discountAmount)),
                  _InfoTile(icon: Icons.payments_rounded, label: appState.tr('payable_amount'), value: _money(sub.payableAmount)),
                  if (sub.note?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(sub.note!, style: TextStyle(color: colors.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          SectionCard(
            child: _PaymentHistory(appState: appState, payments: payments),
          ),
        ],
      ),
    );
  }
}

class _SuperBilling extends StatelessWidget {
  const _SuperBilling({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await appState.refreshAllForSuperAdmin();
        await appState.ensureAllCompanySubscriptions();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroBillingCard(
            title: appState.tr('billing_title'),
            subtitle: appState.tr('billing_subtitle'),
            amount: appState.totalPaidAmount,
            status: '${appState.activeSubscriptionCount} faol / ${appState.subscriptions.where((s) => s.status == SubscriptionStatus.blocked).length} bloklangan',
            days: 0,
          ),
          const SizedBox(height: 12),
          _GlobalPriceCard(appState: appState),
          const SizedBox(height: 12),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: 180, child: _MiniMetric(
                title: 'Faol', value: '${appState.activeSubscriptionCount}',
                icon: Icons.check_circle_rounded)),
              SizedBox(width: 180, child: _MiniMetric(
                title: 'Bloklangan',
                value: '${appState.subscriptions.where((s) => s.status == SubscriptionStatus.blocked).length}',
                icon: Icons.lock_rounded)),
              SizedBox(width: 180, child: _MiniMetric(
                title: 'Muddati tugagan',
                value: '${appState.subscriptions.where((s) => s.status != SubscriptionStatus.blocked && !s.isUsable).length}',
                icon: Icons.warning_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: appState.loading ? null : () => appState.ensureAllCompanySubscriptions(),
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const LocalizedText('Eski kompaniyalarga billing yaratish'),
          ),
          const SizedBox(height: 12),
          for (final company in appState.companies)
            _CompanyBillingTile(
              key: ValueKey('billing_company_${company.id}'),
              appState: appState,
              company: company,
            ),
        ],
      ),
    );
  }
}

class _GlobalPriceCard extends StatefulWidget {
  const _GlobalPriceCard({required this.appState});

  final AppState appState;

  @override
  State<_GlobalPriceCard> createState() => _GlobalPriceCardState();
}

class _GlobalPriceCardState extends State<_GlobalPriceCard> {
  late final TextEditingController _priceController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final price = widget.appState.globalMonthlyPrice;
    _priceController = TextEditingController(
      text: price <= 0 ? '499000' : '$price',
    );
  }

  @override
  void didUpdateWidget(covariant _GlobalPriceCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final current = int.tryParse(
      _priceController.text.trim().replaceAll(' ', ''),
    ) ??
        0;

    final price = widget.appState.globalMonthlyPrice;

    if (!_saving && price > 0 && current != price) {
      _priceController.text = '$price';
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currentPrice = widget.appState.globalMonthlyPrice;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Asosiy umumiy narx',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Yangi yaratiladigan kompaniyalar uchun asosiy oylik obuna narxi. Xohlasangiz mavjud kompaniyalarga ham qo‘llaysiz.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration:  InputDecoration(
              prefixIcon: Icon(Icons.payments_rounded),
              labelText: LocalizedText.translate(context, 'Oylik narx'),
              suffixText: 'so‘m',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.sell_rounded, size: 18),
                label: Text(
                  'Hozirgi: ${_money(currentPrice <= 0 ? 499000 : currentPrice)}',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(applyToAll: false),
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_rounded),
                  label: const LocalizedText('Saqlash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(applyToAll: true),
                  icon: const Icon(Icons.done_all_rounded),
                  label: const LocalizedText('Barchasiga qo‘llash'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save({required bool applyToAll}) async {
    final messenger = ScaffoldMessenger.of(context);

    final price = int.tryParse(
      _priceController.text.trim().replaceAll(' ', ''),
    );

    if (price == null || price <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: LocalizedText('Narxni to‘g‘ri kiriting.')),
      );
      return;
    }

    setState(() => _saving = true);

    final ok = await widget.appState.saveGlobalMonthlyPrice(
      price,
      applyToAllCompanies: applyToAll,
    );

    if (!mounted) return;

    setState(() => _saving = false);

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? applyToAll
              ? 'Umumiy narx saqlandi va barcha kompaniyalarga qo‘llandi.'
              : 'Umumiy narx saqlandi.'
              : widget.appState.errorMessage ?? 'Narx saqlanmadi.',
        ),
      ),
    );
  }
}


class _CompanyBillingTile extends StatefulWidget {
  const _CompanyBillingTile({
    super.key,
    required this.appState,
    required this.company,
  });

  final AppState appState;
  final Company company;

  @override
  State<_CompanyBillingTile> createState() => _CompanyBillingTileState();
}

class _CompanyBillingTileState extends State<_CompanyBillingTile> {
  late final TextEditingController _price;
  late final TextEditingController _percent;
  late final TextEditingController _amount;
  late final TextEditingController _days;
  late final TextEditingController _note;
  SubscriptionStatus _status = SubscriptionStatus.trial;
  bool _expanded = false;
  bool _saving = false;

  AppState get appState => widget.appState;
  Company get company => widget.company;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController();
    _percent = TextEditingController();
    _amount = TextEditingController();
    _days = TextEditingController(text: '30');
    _note = TextEditingController();
    _fillFromSubscription();
  }

  @override
  void didUpdateWidget(covariant _CompanyBillingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.id != widget.company.id || !_expanded) {
      _fillFromSubscription();
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _percent.dispose();
    _amount.dispose();
    _days.dispose();
    _note.dispose();
    super.dispose();
  }

  void _fillFromSubscription() {
    final sub = appState.subscriptionForCompany(company.id);
    _price.text = '${sub?.monthlyPrice ?? appState.globalMonthlyPrice}';
    _percent.text = '${sub?.discountPercent ?? 0}';
    _amount.text = '${sub?.discountAmount ?? 0}';
    _days.text = '30';
    _note.text = sub?.note ?? '';
    _status = sub?.status ?? SubscriptionStatus.trial;
  }

  @override
  Widget build(BuildContext context) {
    final sub = appState.subscriptionForCompany(company.id);
    final colors = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Icon(
                sub?.isUsable == true
                    ? Icons.verified_rounded
                    : Icons.lock_clock_rounded,
              ),
            ),
            title: Text(
              company.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              sub == null
                  ? appState.tr('billing_sql_missing')
                  : '${sub.status.label} • ${_money(sub.payableAmount)} • ${sub.remainingDays} kun',
            ),
            trailing: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.chevron_right_rounded,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: sub.status == SubscriptionStatus.blocked
                  ? FilledButton.icon(
                      onPressed: _saving ? null : () => _changeBlock(blocked: false),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Blokdan chiqarish'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _saving ? null : () => _changeBlock(blocked: true),
                      icon: const Icon(Icons.lock_rounded),
                      label: const Text('Tashkilotni bloklash'),
                      style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                    ),
            ),
          ],
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(color: colors.outlineVariant),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SubscriptionStatus>(
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: appState.tr('subscription_status'),
                      border: const OutlineInputBorder(),
                    ),
                    // Explicit blocks are controlled only by the audited
                    // Block/Unblock buttons, not by this pricing form.
                    items: SubscriptionStatus.values
                        .where((e) => e != SubscriptionStatus.blocked ||
                            _status == SubscriptionStatus.blocked)
                        .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.label),
                        ))
                        .toList(),
                    onChanged: _saving || _status == SubscriptionStatus.blocked
                        ? null
                        : (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 10),
                  _numField(_price, appState.tr('monthly_price'), Icons.sell_rounded),
                  _numField(_percent, appState.tr('discount_percent'), Icons.percent_rounded),
                  _numField(_amount, appState.tr('discount_amount'), Icons.local_offer_rounded),
                  _numField(_days, appState.tr('period_days'), Icons.date_range_rounded),
                  TextField(
                    controller: _note,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 3,
                    decoration:  InputDecoration(
                      labelText: LocalizedText.translate(context, 'Izoh'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(appState.tr('save')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _addPayment,
                          icon: const Icon(Icons.add_card_rounded),
                          label: Text(appState.tr('add_payment')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PaymentHistory(
                    appState: appState,
                    payments: appState.paymentsForCompany(company.id),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeBlock({required bool blocked}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(blocked ? 'Tashkilotni bloklash' : 'Blokdan chiqarish'),
        content: Text(blocked
            ? '"${company.name}" tashkilotining direktor, admin va '
              'ishchilari barcha bo‘limlarda bloklangan ekranni ko‘radi. '
              'Davom etasizmi?'
            : '"${company.name}" tashkilotiga kirishni qayta ochasizmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(blocked ? 'Bloklash' : 'Ochish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final ok = await appState.setCompanyBillingBlocked(
        companyId: company.id, blocked: blocked);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _fillFromSubscription();
    });
    _snack(context, ok
        ? (blocked ? 'Tashkilot bloklandi.' : 'Tashkilot blokdan chiqarildi.')
        : (appState.errorMessage ?? 'Holatni o‘zgartirib bo‘lmadi. SQL migratsiyasini tekshiring.'));
  }

  Widget _numField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  int _readInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim().replaceAll(' ', '')) ?? fallback;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final ok = await appState.saveSubscription(
      companyId: company.id,
      monthlyPrice: _readInt(_price, appState.globalMonthlyPrice),
      discountPercent: _readInt(_percent, 0),
      discountAmount: _readInt(_amount, 0),
      status: _status,
      trialDays: _status == SubscriptionStatus.trial ? _readInt(_days, 30) : null,
      activeDays: _status == SubscriptionStatus.active ? _readInt(_days, 30) : null,
      note: _note.text.trim(),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    _snack(
      context,
      ok
          ? appState.tr('billing_saved')
          : (appState.errorMessage ?? appState.tr('error_unknown')),
    );
  }

  Future<void> _addPayment() async {
    final sub = appState.subscriptionForCompany(company.id);
    setState(() => _saving = true);

    final ok = await appState.addManualPayment(
      companyId: company.id,
      amount: sub?.payableAmount ?? _readInt(_price, appState.globalMonthlyPrice),
      periodDays: _readInt(_days, 30),
      note: _note.text.trim(),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    _snack(
      context,
      ok
          ? appState.tr('payment_added')
          : (appState.errorMessage ?? appState.tr('error_unknown')),
    );
  }
}


class _HeroBillingCard extends StatelessWidget {
  const _HeroBillingCard({required this.title, required this.subtitle, required this.amount, required this.status, required this.days});
  final String title;
  final String subtitle;
  final int amount;
  final String status;
  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.secondaryContainer.withValues(alpha: .75), colors.surfaceContainerHighest],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: colors.primary, foregroundColor: colors.onPrimary, child: const Icon(Icons.workspace_premium_rounded)),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 12),
          Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text(_money(amount), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text(status)),
            if (days > 0) Chip(label: Text('$days kun qoldi')),
          ]),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(value, style: const TextStyle(fontWeight: FontWeight.w900))]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w900)));
  }
}

class _PaymentHistory extends StatelessWidget {
  const _PaymentHistory({required this.appState, required this.payments});
  final AppState appState;
  final List<CompanyPayment> payments;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appState.tr('payment_history'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          LocalizedText('Hozircha to‘lov yo‘q', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          for (final item in payments.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_rounded),
              title: Text(_money(item.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${item.provider} • ${item.periodDays} kun • ${_date(item.paidAt ?? item.createdAt)}'),
              trailing: Text(item.status),
            ),
      ],
    );
  }
}

String _money(int value) {
  final s = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buffer.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(' ');
  }
  return '${buffer.toString()} so‘m';
}

String _date(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(children: [const Icon(Icons.info_rounded), const SizedBox(width: 10), Expanded(child: Text(text))]),
    ),
  );
}
