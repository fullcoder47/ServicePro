import 'package:flutter/material.dart';

import 'billing_repository.dart';
import 'demo_billing_api.dart';

/// Tashkilot uchun kelajakdagi qarzdorlik API'sining xavfsiz namoyishi.
/// Hech qanday real abonent yoki bank ma'lumoti o'zgartirilmaydi.
class BillingDemoPreviewPage extends StatefulWidget {
  const BillingDemoPreviewPage({super.key, required this.companyId});

  final String companyId;

  @override
  State<BillingDemoPreviewPage> createState() => _BillingDemoPreviewPageState();
}

class _BillingDemoPreviewPageState extends State<BillingDemoPreviewPage> {
  late Future<List<DemoBillingRecord>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = const DemoBillingApi().organizationAccounts(widget.companyId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Billing API · DEMO'), actions: [
        IconButton(onPressed: () => setState(_refresh),
          tooltip: 'Yangilash', icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: FutureBuilder<List<DemoBillingRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Demo ma’lumot yuklanmadi: ${snapshot.error}'));
          }
          final records = snapshot.data ?? [];
          final totalDebt = records.fold<int>(0,
            (sum, row) => sum + (row.balanceUzS > 0 ? row.balanceUzS : 0));
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.science_outlined), SizedBox(width: 8),
                  Expanded(child: Text('Sinov ma’lumotlari',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
                ]),
                const SizedBox(height: 10),
                const Text('Bu 3 ta uydirma abonentdan iborat demo API. '
                  'Haqiqiy Mening Uyim API ulanishi hali yo‘q. '
                  'Quyidagi summalarni real qarz yoki to‘lov deb qabul qilmang.'),
                const SizedBox(height: 12),
                Text('${records.length} ta test abonent',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Jami demo qarz: ${billingMoney(totalDebt)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              ])),
            const SizedBox(height: 12),
            for (final r in records) Card(child: ExpansionTile(
              leading: CircleAvatar(child: Icon(r.type == 'Noturar'
                ? Icons.storefront_outlined : Icons.person_outline_rounded)),
              title: Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${r.accountNumber} · ${r.address}', maxLines: 2),
              trailing: Text(billingMoney(r.balanceUzS),
                style: TextStyle(fontWeight: FontWeight.w800,
                  color: r.balanceUzS > 0 ? colors.error : colors.primary)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const Divider(),
                _line('Abonent turi', r.type),
                _line('Hisob raqami', r.accountNumber),
                _line('Manzil', r.address),
                _line('Joriy qarz', billingMoney(r.balanceUzS)),
                _line('Oylik hisoblanma', billingMoney(r.monthlyChargeUzS)),
                _line('Oxirgi to‘lov (demo)', billingMoney(r.lastPaymentUzS)),
                _line('Tarif (demo)', billingMoney(r.tariffUzS)),
                _line('Maydon', '${r.area.toStringAsFixed(1)} m²'),
                _line('Ma’lumot vaqti', billingDate(r.updatedAt)),
              ],
            )),
          ]);
        },
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      Flexible(child: Text(value, textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w700))),
    ]),
  );
}
