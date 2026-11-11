import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/features/subscribers/billing_excel.dart';
import 'package:servicepro/features/subscribers/billing_repository.dart';

Uint8List _workbook({bool duplicate = false}) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  sheet.appendRow([
    TextCellValue('№'), TextCellValue('Kompaniya'), TextCellValue('Uy manzili'),
    TextCellValue('Hisob raqami'), TextCellValue('Balans'), TextCellValue('Shartnoma holati'),
  ]);
  sheet.appendRow([
    IntCellValue(1), TextCellValue('MCHJ BIG SCAN AS PLYUS'),
    TextCellValue("Furqat MFY, Ipak yo'li ko'chasi, 49-uy"),
    TextCellValue('1255218197'), TextCellValue('6094362.26'),
    TextCellValue('Shartnoma yuklanmagan'),
  ]);
  if (duplicate) {
    sheet.appendRow([
      IntCellValue(2), TextCellValue('MCHJ BIG SCAN AS PLYUS'), TextCellValue('Boshqa manzil'),
      TextCellValue('1255218197'), TextCellValue('10.00'), TextCellValue(''),
    ]);
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  test('Hisob raqami matn sifatida saqlanadi, balans to‘g‘ri o‘qiladi', () {
    final result = BillingWorkbook.parse(_workbook());
    expect(result.accounts.length, 1);
    expect(result.accounts.single['account_number'], '1255218197');
    expect(result.accounts.single['balance'], 6094362.26);
    expect(result.companyNames, contains('MCHJ BIG SCAN AS PLYUS'));
    expect(result.ledger, isEmpty);
    expect(result.transactions, isEmpty);
  });

  test('Bir faylda takrorlangan hisob raqamini qabul qilmaydi', () {
    expect(() => BillingWorkbook.parse(_workbook(duplicate: true)), throwsFormatException);
  });

  test('Qarzdorlik, ortiqcha to‘lov va minglik ajratkich to‘g‘ri', () {
    expect(billingMoney(6094362.26), '6 094 362,26 so‘m');
    expect(billingMoney(-59150.25), '-59 150,25 so‘m');
  });
}
