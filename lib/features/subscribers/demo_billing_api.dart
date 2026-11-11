import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Faqat interfeysni sinash uchun. Bu API bankka yoki Mening Uyim'ga ulanmaydi.
/// Haqiqiy billing API kelganda shu interfeysga yangi implementatsiya qo'shiladi.
abstract class BillingApi {
  Future<List<DemoBillingRecord>> organizationAccounts(String companyId);

  Future<DemoPaymentReceipt> testPayment({
    required String accountNumber,
    required int amountUzS,
    required DemoPaymentCard card,
  });
}

class DemoBillingRecord {
  const DemoBillingRecord({
    required this.accountNumber,
    required this.fullName,
    required this.address,
    required this.type,
    required this.balanceUzS,
    required this.monthlyChargeUzS,
    required this.lastPaymentUzS,
    required this.tariffUzS,
    required this.area,
    required this.updatedAt,
  });

  final String accountNumber, fullName, address, type;
  final int balanceUzS, monthlyChargeUzS, lastPaymentUzS, tariffUzS;
  final double area;
  final DateTime updatedAt;
}

class DemoPaymentReceipt {
  const DemoPaymentReceipt({required this.number, required this.createdAt});
  final String number;
  final DateTime createdAt;
}

class DemoBillingApi implements BillingApi {
  const DemoBillingApi();

  @override
  Future<List<DemoBillingRecord>> organizationAccounts(String companyId) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (companyId.trim().isEmpty) return [];
    final now = DateTime.now();
    return [
      DemoBillingRecord(
        accountNumber: 'DEMO-1001', fullName: 'Namuna abonent 1',
        address: 'Namuna ko‘chasi, 10-uy, 1-xonadon', type: 'Aholi',
        balanceUzS: 285000, monthlyChargeUzS: 65000,
        lastPaymentUzS: 100000, tariffUzS: 1300,
        area: 50, updatedAt: now,
      ),
      DemoBillingRecord(
        accountNumber: 'DEMO-1002', fullName: 'Namuna abonent 2',
        address: 'Namuna ko‘chasi, 10-uy, 2-xonadon', type: 'Aholi',
        balanceUzS: 0, monthlyChargeUzS: 52000,
        lastPaymentUzS: 52000, tariffUzS: 1300,
        area: 40, updatedAt: now,
      ),
      DemoBillingRecord(
        accountNumber: 'DEMO-2001', fullName: 'Namuna do‘kon',
        address: 'Namuna ko‘chasi, 12-uy, noturar joy', type: 'Noturar',
        balanceUzS: 620000, monthlyChargeUzS: 160000,
        lastPaymentUzS: 0, tariffUzS: 4000,
        area: 40, updatedAt: now,
      ),
    ];
  }

  @override
  Future<DemoPaymentReceipt> testPayment({
    required String accountNumber,
    required int amountUzS,
    required DemoPaymentCard card,
  }) async {
    if (accountNumber.trim().isEmpty || amountUzS <= 0 || card.lastFour.length != 4) {
      throw const FormatException('Demo to‘lov ma’lumotlarini tekshiring.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return DemoPaymentReceipt(
      number: 'DEMO-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
  }
}

class DemoPaymentCard {
  const DemoPaymentCard({
    required this.id,
    required this.brand,
    required this.lastFour,
  });

  final String id, brand, lastFour;

  String get label => '$brand  •••• $lastFour';

  Map<String, String> toMap() => {
    'id': id, 'brand': brand, 'lastFour': lastFour,
  };

  static DemoPaymentCard? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = '${value['id'] ?? ''}';
    final brand = '${value['brand'] ?? ''}';
    final lastFour = '${value['lastFour'] ?? ''}';
    if (id.isEmpty || !['UZCARD', 'HUMO'].contains(brand) ||
        !RegExp(r'^\d{4}$').hasMatch(lastFour)) return null;
    return DemoPaymentCard(id: id, brand: brand, lastFour: lastFour);
  }
}

/// Karta ma'lumotlari DEMO: faqat turi va oxirgi 4 ta raqami saqlanadi.
/// To'liq karta raqami, CVV, amal qilish muddati va bank tokeni saqlanmaydi.
class DemoPaymentCardStore {
  static String _key(String profileId) => 'servicepro_demo_cards_$profileId';

  Future<List<DemoPaymentCard>> list(String profileId) async {
    if (profileId.trim().isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId));
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data.map(DemoPaymentCard.fromMap)
          .whereType<DemoPaymentCard>().toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<DemoPaymentCard> add({
    required String profileId,
    required String brand,
    required String lastFour,
  }) async {
    if (profileId.trim().isEmpty || !['UZCARD', 'HUMO'].contains(brand) ||
        !RegExp(r'^\d{4}$').hasMatch(lastFour)) {
      throw const FormatException('Karta turi va oxirgi 4 raqamini kiriting.');
    }
    final cards = (await list(profileId)).toList();
    if (cards.length >= 5) {
      throw StateError('Demo rejimda 5 tagacha karta qo‘shish mumkin.');
    }
    if (cards.any((c) => c.brand == brand && c.lastFour == lastFour)) {
      throw StateError('Bunday demo karta allaqachon qo‘shilgan.');
    }
    final card = DemoPaymentCard(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      brand: brand,
      lastFour: lastFour,
    );
    cards.add(card);
    await _save(profileId, cards);
    return card;
  }

  Future<void> remove(String profileId, String cardId) async {
    final cards = (await list(profileId)).where((c) => c.id != cardId).toList();
    await _save(profileId, cards);
  }

  Future<void> _save(String profileId, List<DemoPaymentCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId), jsonEncode(cards.map((c) => c.toMap()).toList()));
  }
}
