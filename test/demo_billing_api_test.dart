import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servicepro/features/subscribers/demo_billing_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('demo cards are isolated between resident profiles', () async {
    final store = DemoPaymentCardStore();
    await store.add(profileId: 'person-a', brand: 'UZCARD', lastFour: '4242');
    expect((await store.list('person-a')).single.label, contains('4242'));
    expect(await store.list('person-b'), isEmpty);
  });

  test('demo cards only store brand and last four, not card credentials', () async {
    final store = DemoPaymentCardStore();
    await store.add(profileId: 'person-a', brand: 'HUMO', lastFour: '9876');
    final prefs = await SharedPreferences.getInstance();
    final serialized = prefs.getString('servicepro_demo_cards_person-a')!;
    expect(serialized, contains('9876'));
    expect(serialized, isNot(contains('cvv')));
    expect(serialized, isNot(contains('cardNumber')));
    expect(serialized, isNot(contains('expiry')));
  });

  test('invalid or duplicate demo card is rejected', () async {
    final store = DemoPaymentCardStore();
    await expectLater(store.add(profileId: 'person-a', brand: 'HUMO', lastFour: '11'),
      throwsFormatException);
    await store.add(profileId: 'person-a', brand: 'HUMO', lastFour: '1111');
    await expectLater(store.add(profileId: 'person-a', brand: 'HUMO', lastFour: '1111'),
      throwsStateError);
  });

  test('demo debt provider never loads actual subscriber accounts', () async {
    final records = await const DemoBillingApi().organizationAccounts('test-company');
    expect(records.length, 3);
    expect(records.every((r) => r.accountNumber.startsWith('DEMO-')), isTrue);
    expect(records.every((r) => r.fullName.startsWith('Namuna')), isTrue);
  });

  test('test payment only produces a demo receipt', () async {
    const card = DemoPaymentCard(id: 'test', brand: 'UZCARD', lastFour: '4242');
    final receipt = await const DemoBillingApi().testPayment(
      accountNumber: 'DEMO-1001', amountUzS: 1000, card: card);
    expect(receipt.number, startsWith('DEMO-'));
  });
}
