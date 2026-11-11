import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:excel_community/excel_community.dart';

class BillingWorkbook {
  BillingWorkbook(this.accounts, this.ledger, this.transactions, this.companyNames, this.hash);
  final List<Map<String, dynamic>> accounts, ledger, transactions;
  final Set<String> companyNames;
  final String hash;

  static BillingWorkbook parse(Uint8List bytes) {
    if (bytes.lengthInBytes > 15 * 1024 * 1024) {
      throw const FormatException('Fayl 15 MB dan katta.');
    }
    final excel = Excel.decodeBytes(bytes);
    final accounts = <Map<String, dynamic>>[];
    final monthly = <Map<String, dynamic>>[];
    final transactions = <Map<String, dynamic>>[];
    final companies = <String>{};
    final accountKeys = <String>{};
    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;
      final header = sheet.rows.first.map((cell) => _key(_cell(cell))).toList();
      final accountCol = _col(header, ['Hisob raqami', 'account number', 'account_number', 'Shaxsiy hisob raqami']);
      if (accountCol < 0) continue;
      final balanceCol = _col(header, ['Balans', 'Qarzdorlik', 'balance']);
      final monthCol = _col(header, ['Oy', 'month']);
      final yearCol = _col(header, ['Yil', 'year']);
      final dateCol = _col(header, ["To'lov sanasi", 'Tolov sanasi', 'Payment date', 'Sana']);
      final amountCol = _col(header, ["To'lov summasi", 'Tolov summasi', 'Summa', 'Amount']);
      final isMonthly = monthCol >= 0 && yearCol >= 0;
      final isTransactions = amountCol >= 0 && dateCol >= 0;
      if (balanceCol < 0 && !isMonthly && !isTransactions) continue;

      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        String val(List<String> options) => _at(row, _col(header, options));
        final account = _at(row, accountCol).trim();
        if (account.isEmpty) continue;
        if (account.length < 4 || account.length > 50) {
          throw FormatException('${entry.key}: ${i + 1}-qator, hisob raqami noto‘g‘ri.');
        }
        if (isMonthly) {
          final year = int.tryParse(val(['Yil','year']));
          final month = _month(val(['Oy','month']));
          if (year == null || year < 2000 || year > 2200 || month == null) {
            throw FormatException('${entry.key}: ${i + 1}-qator, oy yoki yil noto‘g‘ri.');
          }
          monthly.add({
            'account_number': account, 'year': year, 'month': month,
            'area': _optionalMoney(val(['Umumiy maydon','Maydon','Area'])),
            'tariff': _optionalMoney(val(['Tarif','Tariff'])),
            'opening_balance': _optionalMoney(val(['Oy boshida','Boshlangich balans','Opening balance'])),
            'charged': _optionalMoney(val(['Hisoblangan','Charged'])),
            'penalty': _optionalMoney(val(['Penya','Penalty'])),
            'paid': _optionalMoney(val(["To'lov",'Tolov','Paid'])),
            'recalculated': _optionalMoney(val(['Qayta hisob kitob','Recalculated'])),
            'closing_balance': _optionalMoney(val(['Oy oxirida','Closing balance'])),
          });
          continue;
        }
        if (isTransactions) {
          final date = _date(row, dateCol);
          final amount = _requiredMoney(_at(row, amountCol), entry.key, i + 1);
          if (date == null) throw FormatException('${entry.key}: ${i + 1}-qator, to‘lov sanasi noto‘g‘ri.');
          final kind = _key(entry.key).contains('qayta') || _key(entry.key).contains('recalc')
            ? 'recalculation' : 'payment';
          final reference = val(['Tranzaksiya','Tranzaksiya raqami','Transaction','Reference']);
          final method = val(["To'lov turi",'Tolov turi','Payment method','Method']);
          final fingerprint = reference.isNotEmpty ? reference : '${date.toIso8601String()}|$amount|$method|${i + 1}';
          transactions.add({
            'account_number': account, 'kind': kind,
            'event_key': sha256.convert('$kind|$account|$fingerprint'.codeUnits).toString(),
            'occurred_at': date.toUtc().toIso8601String(), 'amount': amount,
            'method': method.isEmpty ? null : method,
            'reference': reference.isEmpty ? null : reference,
          });
          continue;
        }
        if (!accountKeys.add(account)) throw FormatException('Hisob raqami takrorlangan: $account');
        final company = val(['Kompaniya','Company']);
        if (company.isNotEmpty) companies.add(company);
        final raw = <String, String>{};
        for (var j = 0; j < header.length; j++) {
          if (header[j].isNotEmpty) raw[header[j]] = _at(row, j);
        }
        accounts.add({
          'account_number': account,
          'ordinal': int.tryParse(val(['№','N','Tartib raqami','No'])) ?? accounts.length + 1,
          'region': val(['Viloyat','Region']), 'district': val(['Tuman','District']),
          'address': val(['Uy manzili','Manzil','Address']),
          'full_name': val(['Abonent','Ism familiya','FIO','Full name']),
          'subscriber_type': val(['Turi','Abonent turi','Type']),
          'cadastral_number': val(['Kadastr raqami','Kadastr','Cadastral number']),
          'contract_status': val(['Shartnoma holati','Contract status']),
          'balance': _requiredMoney(_at(row, balanceCol), entry.key, i + 1),
          'source_row': raw,
        });
      }
    }
    if (accounts.isEmpty) {
      throw const FormatException('Excelda “Hisob raqami” va “Balans” ustunlari bilan abonentlar jadvali topilmadi.');
    }
    for (final row in [...monthly, ...transactions]) {
      if (!accountKeys.contains(row['account_number'])) {
        throw FormatException('Qo‘shimcha jadvalda asosiy ro‘yxatda yo‘q hisob: ${row['account_number']}');
      }
    }
    return BillingWorkbook(accounts, monthly, transactions, companies, sha256.convert(bytes).toString());
  }
}

String _key(String s) => s.toLowerCase().trim()
  .replaceAll(RegExp(r'[\s\-_.:;‘’\x27"/\\]+'), '');
int _col(List<String> headers, List<String> options) {
  for (final option in options) {
    final index = headers.indexOf(_key(option));
    if (index >= 0) return index;
  }
  return -1;
}
String _at(List<Data?> row, int index) => index < 0 || index >= row.length ? '' : _cell(row[index]);
String _cell(Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  if (value is TextCellValue) return _spanText(value.value).trim();
  if (value is IntCellValue) return value.value.toString();
  if (value is DoubleCellValue) return value.value.toString();
  if (value is DateTimeCellValue) return value.asDateTimeLocal().toIso8601String();
  if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
  return value.toString();
}
String _spanText(TextSpan span) => (span.text ?? '') +
  (span.children?.map(_spanText).join() ?? '');
double _requiredMoney(String raw, String sheet, int line) =>
  _optionalMoney(raw) ?? (throw FormatException('$sheet: $line-qator, summa noto‘g‘ri: “$raw”.'));
double? _optionalMoney(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[\s\u00a0]'), '');
  if (s.isEmpty) return null;
  var v = s;
  if (v.contains('.') && v.contains(',')) {
    v = v.lastIndexOf('.') > v.lastIndexOf(',') ? v.replaceAll(',', '')
      : v.replaceAll('.', '').replaceAll(',', '.');
  } else if (v.contains(',')) {
    v = RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(v)
      ? v.replaceAll(',', '') : v.replaceAll(',', '.');
  }
  return double.tryParse(v);
}
int? _month(String name) {
  final numeric = int.tryParse(name);
  if (numeric != null) return numeric >= 1 && numeric <= 12 ? numeric : null;
  const months = ['yanvar','fevral','mart','aprel','may','iyun','iyul','avgust','sentyabr','oktyabr','noyabr','dekabr'];
  final index = months.indexOf(_key(name));
  return index < 0 ? null : index + 1;
}
DateTime? _date(List<Data?> row, int index) {
  if (index < 0 || index >= row.length) return null;
  final value = row[index]?.value;
  if (value is DateTimeCellValue) return value.asDateTimeLocal();
  if (value is DateCellValue) return value.asDateTimeLocal();
  if (value is DoubleCellValue || value is IntCellValue) {
    final serial = double.tryParse(_cell(row[index]));
    if (serial != null && serial > 10000 && serial < 100000) {
      return DateTime(1899,12,30).add(Duration(milliseconds: (serial * 86400000).round()));
    }
  }
  final text = _at(row,index).trim();
  final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (parsed != null) return parsed;
  final match = RegExp(r'^(\d{2})[./](\d{2})[./](\d{4})(?:\s+(\d{2}):(\d{2}))?').firstMatch(text);
  if (match == null) return null;
  return DateTime(int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!),
    int.tryParse(match[4] ?? '') ?? 0, int.tryParse(match[5] ?? '') ?? 0);
}
