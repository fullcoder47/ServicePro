import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

class SubscriberAccount {
  const SubscriberAccount({required this.id, required this.companyId, required this.accountNumber,
    required this.balance, required this.address, required this.contractStatus,
    required this.isCurrent, this.ordinal, this.region = '', this.district = '',
    this.fullName, this.type, this.cadastralNumber, this.residentProfileId});
  final String id, companyId, accountNumber, address, contractStatus, region, district;
  final int? ordinal;
  final double balance;
  final String? fullName, type, cadastralNumber, residentProfileId;
  final bool isCurrent;
  factory SubscriberAccount.fromMap(Map<String, dynamic> r) => SubscriberAccount(
    id: '${r['id']}', companyId: '${r['company_id']}', accountNumber: '${r['account_number']}',
    ordinal: (r['ordinal'] as num?)?.toInt(),
    balance: (r['balance'] as num?)?.toDouble() ?? double.tryParse('${r['balance']}') ?? 0,
    address: '${r['address'] ?? ''}', contractStatus: '${r['contract_status'] ?? ''}',
    region: '${r['region'] ?? ''}', district: '${r['district'] ?? ''}',
    fullName: r['full_name'] as String?, type: r['subscriber_type'] as String?,
    cadastralNumber: r['cadastral_number'] as String?,
    residentProfileId: r['resident_profile_id'] as String?, isCurrent: r['is_current'] != false);
}

class AccountSearchResult {
  AccountSearchResult(this.items, this.total);
  final List<SubscriberAccount> items;
  final int total;
}

class BillingImport {
  BillingImport(Map<String, dynamic> r)
      : id = '${r['id']}', companyId = '${r['company_id']}', filename = '${r['filename']}',
        storagePath = '${r['storage_path'] ?? ''}', status = '${r['status']}',
        rowCount = (r['row_count'] as num?)?.toInt() ?? 0,
        createdAt = DateTime.tryParse('${r['created_at']}') ?? DateTime(2000),
        publishedAt = DateTime.tryParse('${r['published_at'] ?? ''}');
  final String id, companyId, filename, storagePath, status;
  final int rowCount;
  final DateTime createdAt;
  final DateTime? publishedAt;
}

class BillingImportResult {
  BillingImportResult(this.items, this.total);
  final List<BillingImport> items;
  final int total;
}

class BillingLinkRequest {
  BillingLinkRequest(Map<String, dynamic> row)
      : id = '${row['id']}',
        companyId = '${row['company_id']}',
        profileId = '${row['profile_id']}',
        lookupMethod = '${row['lookup_method']}',
        lookupValue = '${row['lookup_value']}',
        status = '${row['status']}',
        suggestedAccountId = row['suggested_account_id'] as String?,
        createdAt = DateTime.tryParse('${row['created_at']}') ?? DateTime(2000);

  final String id, companyId, profileId, lookupMethod, lookupValue, status;
  final String? suggestedAccountId;
  final DateTime createdAt;

  bool get pending => status == 'pending';
}

class BillingSnapshot {
  BillingSnapshot(this.balance, this.filename, this.date);
  final double balance;
  final String filename;
  final DateTime date;
}

class BillingLedgerMonth {
  BillingLedgerMonth(this.row, this.date);
  final Map<String, dynamic> row;
  final DateTime date;
  int get year => (row['year'] as num).toInt();
  int get month => (row['month'] as num).toInt();
  double? amount(String key) => (row[key] as num?)?.toDouble();
}

class BillingTransaction {
  BillingTransaction(this.row);
  final Map<String, dynamic> row;
  String get kind => '${row['kind']}';
  double get amount => (row['amount'] as num).toDouble();
  DateTime get date => DateTime.tryParse('${row['occurred_at']}') ?? DateTime(2000);
}

/// Database RLS checks every operation, independently of any Flutter checks.
class SubscriberBillingRepository {
  SubscriberBillingRepository(this.appState);
  final AppState appState;
  SupabaseClient get db => appState.client;

  Future<AccountSearchResult> search({String? companyId, String text = '',
    String street = '', String house = '', String type = '', String contract = '',
    int offset = 0, int limit = 40}) async {
    var query = db.from('billing_accounts').select('*');
    if (companyId != null && companyId.isNotEmpty) query = query.eq('company_id', companyId);
    query = query.eq('is_current', true);
    if (type.isNotEmpty) query = query.eq('subscriber_type', type);
    if (contract.isNotEmpty) query = query.eq('contract_status', contract);
    final safeStreet = street.trim().replaceAll(RegExp(r'[%*]'), ' ');
    final safeHouse = house.trim().replaceAll(RegExp(r'[%*]'), ' ');
    if (safeStreet.isNotEmpty) query = query.ilike('address', '%$safeStreet%');
    if (safeHouse.isNotEmpty) query = query.ilike('address', '%$safeHouse%');
    final safe = text.trim().replaceAll(RegExp(r'[,().%*\\]'), ' ');
    if (safe.isNotEmpty) {
      query = query.or('account_number.ilike.%$safe%,full_name.ilike.%$safe%,address.ilike.%$safe%,cadastral_number.ilike.%$safe%');
    }
    final response = await query
        .order('ordinal', ascending: true, nullsFirst: false)
        .order('account_number')
        .range(offset, offset + limit - 1)
        .count(CountOption.exact);
    return AccountSearchResult((response.data as List)
        .map((e) => SubscriberAccount.fromMap(Map<String, dynamic>.from(e))).toList(), response.count);
  }

  Future<List<SubscriberAccount>> ownAccounts() async {
    final profile = appState.currentProfile;
    if (profile == null || profile.role != UserRole.user) return [];
    final rows = await db.from('billing_accounts').select()
        .eq('resident_profile_id', profile.id).eq('is_current', true).order('account_number');
    return (rows as List).map((e) => SubscriberAccount.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  /// These requests never grant account access: a company reviewer must link it.
  Future<String> requestAccountLink({required String method, String? accountNumber}) async {
    final profile = appState.currentProfile;
    if (profile == null || profile.role != UserRole.user) {
      throw StateError('Faqat aholi akkaunti hisob biriktirish so‘rovini yuborishi mumkin.');
    }
    if (method != 'account' && method != 'address') {
      throw ArgumentError.value(method, 'method');
    }
    if (method == 'account' && (accountNumber?.trim().length ?? 0) < 4) {
      throw const FormatException('Hisob raqamini to‘liq kiriting.');
    }
    final result = await db.rpc('billing_request_resident_link', params: {
      'p_method': method,
      'p_value': method == 'account' ? accountNumber!.trim() : null,
    });
    return '$result';
  }

  Future<List<BillingLinkRequest>> myLinkRequests() async {
    final profile = appState.currentProfile;
    if (profile == null || profile.role != UserRole.user) return [];
    final rows = await db.from('billing_link_requests').select()
      .eq('profile_id', profile.id)
      .order('created_at', ascending: false).limit(20);
    return (rows as List).map((e) => BillingLinkRequest(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<BillingLinkRequest>> pendingLinkRequests({String? companyId}) async {
    final profile = appState.currentProfile;
    if (profile == null || ![UserRole.superAdmin, UserRole.director, UserRole.admin]
        .contains(profile.role)) {
      return [];
    }
    var query = db.from('billing_link_requests').select().eq('status', 'pending');
    if (companyId != null && companyId.isNotEmpty) {
      query = query.eq('company_id', companyId);
    }
    final rows = await query.order('created_at', ascending: false).limit(200);
    return (rows as List).map((e) => BillingLinkRequest(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> reviewLinkRequest(String requestId, {
    required bool approve, String? accountId,
  }) async {
    await db.rpc('billing_review_resident_link', params: {
      'p_request_id': requestId,
      'p_account_id': approve ? accountId : null,
      'p_approve': approve,
    });
  }

  Future<void> updateResidentHomeAddress({
    required String neighborhood, required String street,
    required String houseNumber,
  }) async {
    final p = appState.currentProfile;
    if (p == null || p.role != UserRole.user) {
      throw StateError('Aholi profili topilmadi.');
    }
    final cleaned = [neighborhood, street, houseNumber].map((s) => s.trim()).toList();
    if (cleaned.any((s) => s.isEmpty)) {
      throw const FormatException('Mahalla, ko‘cha va uy/xonadonni to‘liq kiriting.');
    }
    await db.rpc('servicepro_save_ticket_contact', params: {
      'p_first': p.firstName.trim(),
      'p_last': p.lastName.trim(),
      'p_phone': p.phone.trim(),
      'p_neighborhood': cleaned[0],
      'p_street': cleaned[1],
      'p_house': cleaned[2],
    });
    p.neighborhood = cleaned[0];
    p.street = cleaned[1];
    p.houseNumber = cleaned[2];
    appState.notifyStateChanged();
  }

  Future<BillingImportResult> imports(String? companyId, {int offset = 0, int limit = 30}) async {
    var query = db.from('billing_imports').select();
    if (companyId != null && companyId.isNotEmpty) query = query.eq('company_id', companyId);
    final result = await query
      .order('created_at', ascending: false)
      .range(offset, offset + limit - 1)
      .count(CountOption.exact);
    return BillingImportResult((result.data as List)
      .map((e) => BillingImport(Map<String, dynamic>.from(e))).toList(), result.count);
  }

  Future<List<BillingSnapshot>> history(SubscriberAccount a) async {
    final rows = <dynamic>[];
    for (var start = 0; ; start += 500) {
      final chunk = await db.from('billing_import_rows')
        .select('balance,billing_imports!inner(filename,published_at,status)')
        .eq('company_id', a.companyId).eq('account_number', a.accountNumber)
        .eq('billing_imports.status', 'published')
        .order('import_id').range(start, start + 499);
      rows.addAll(chunk);
      if (chunk.length < 500) break;
    }
    return rows.map((entry) {
      final r = Map<String, dynamic>.from(entry);
      final b = Map<String, dynamic>.from(r['billing_imports'] as Map);
      return BillingSnapshot((r['balance'] as num).toDouble(), '${b['filename']}',
          DateTime.tryParse('${b['published_at']}') ?? DateTime(2000));
    }).toList()..sort((a,b) => b.date.compareTo(a.date));
  }

  Future<List<BillingLedgerMonth>> ledger(SubscriberAccount a) async {
    final rows = <dynamic>[];
    for (var start = 0; ; start += 500) {
      final chunk = await db.from('billing_ledger').select('*,billing_imports!inner(status,published_at)')
        .eq('company_id', a.companyId).eq('account_number', a.accountNumber)
        .eq('billing_imports.status', 'published')
        .order('year', ascending: false).order('month', ascending: false)
        .order('id').range(start, start + 499);
      rows.addAll(chunk);
      if (chunk.length < 500) break;
    }
    final all = rows.map((e) {
      final r = Map<String, dynamic>.from(e);
      final b = Map<String, dynamic>.from(r['billing_imports'] as Map);
      return BillingLedgerMonth(r, DateTime.tryParse('${b['published_at']}') ?? DateTime(2000));
    }).toList()..sort((a,b) => b.date.compareTo(a.date));
    final seen = <String>{};
    return all.where((r) => seen.add('${r.year}-${r.month}')).toList()
      ..sort((a,b) => b.year == a.year ? b.month.compareTo(a.month) : b.year.compareTo(a.year));
  }

  Future<List<BillingTransaction>> transactions(SubscriberAccount a) async {
    final rows = <dynamic>[];
    for (var start = 0; ; start += 500) {
      final chunk = await db.from('billing_transactions').select()
        .eq('company_id', a.companyId).eq('account_number', a.accountNumber)
        .order('occurred_at', ascending: false).range(start, start + 499);
      rows.addAll(chunk);
      if (chunk.length < 500) break;
    }
    final seen = <String>{};
    return rows.map((e) => BillingTransaction(Map<String, dynamic>.from(e)))
      .where((t) => seen.add('${t.kind}:${t.row['event_key']}')).toList();
  }

  Future<void> linkResident(SubscriberAccount account, String? id) async {
    await db.rpc('billing_link_resident', params: {'p_account_id': account.id, 'p_profile_id': id});
  }

  Future<Map<String, dynamic>> beginImport(String companyId, String filename, String hash) async =>
    Map<String, dynamic>.from(await db.rpc('billing_begin_import', params: {
      'p_company_id': companyId, 'p_filename': filename, 'p_sha256': hash}) as Map);

  Future<void> uploadOriginal(String path, Uint8List bytes) async {
    await db.storage.from('billing-imports').uploadBinary(path, bytes,
      fileOptions: const FileOptions(contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
  }
  Future<Uint8List> downloadOriginal(BillingImport item) => db.storage.from('billing-imports').download(item.storagePath);

  Future<void> _stage(String functionName, String id, List<Map<String, dynamic>> rows) async {
    for (var i = 0; i < rows.length; i += 200) {
      final end = (i + 200).clamp(0, rows.length);
      await db.rpc(functionName, params: {'p_import_id': id, 'p_rows': rows.sublist(i, end)});
    }
  }
  Future<void> stageRows(String id, List<Map<String, dynamic>> rows) => _stage('billing_stage_rows', id, rows);
  Future<void> stageLedger(String id, List<Map<String, dynamic>> rows) => _stage('billing_stage_ledger', id, rows);
  Future<void> stageTransactions(String id, List<Map<String, dynamic>> rows) => _stage('billing_stage_transactions', id, rows);
  Future<void> publish(String id, int count) async {
    await db.rpc('billing_publish_import', params: {'p_import_id': id, 'p_expected_rows': count});
  }
}

String billingMoney(num n) {
  final parts = n.abs().toStringAsFixed(2).split('.');
  final grouped = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '${n < 0 ? '-' : ''}$grouped,${parts.last} so‘m';
}
String billingDate(DateTime value) {
  final v = value.toLocal();
  return '${v.day.toString().padLeft(2,'0')}.${v.month.toString().padLeft(2,'0')}.${v.year}';
}
