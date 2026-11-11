part of 'app_state.dart';

/// Onboarding uses persistent Supabase sessions. Guest browsing never invents a
/// profile or grants authenticated access to personal/company data.
extension OnboardingState on AppState {
  Future<void> loadPublicCompanies() async {
    // Widget tests use AppState.forTesting() without an initialized Supabase
    // client. In that state no directory request should be made.
    if (!hasBackendClient) return;
    dynamic rows;

    try {
      rows = await client.rpc('servicepro_company_directory');
    } on PostgrestException catch (e) {
      final expired = e.code == 'PGRST303' &&
          e.message.toLowerCase().contains('jwt expired');

      if (!expired) rethrow;

      if (client.auth.currentSession == null) {
        throw Exception(
          'Saqlangan sessiya yo‘q, ammo server JWT expired qaytardi. '
              'Supabase ulanish kalitini tekshirish kerak.',
        );
      }

      await client.auth.refreshSession();

      rows = await client.rpc('servicepro_company_directory');
    }
    publicCompanies
      ..clear()
      ..addAll((rows as List).map((row) => Company.fromMap(Map<String, dynamic>.from(row))));
    publicCompanies.sort((a, b) {
      final aDefault = RegExp(r'^bigscanaspl(?:yus|us)').hasMatch(a.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''));
      final bDefault = RegExp(r'^bigscanaspl(?:yus|us)').hasMatch(b.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''));
      if (aDefault != bDefault) return aDefault ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    _notifyStateChanged();
  }

  Future<void> setGuestTheme(ThemeMode mode) async {
    guestThemeMode = mode;
    _notifyStateChanged();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guest_theme', mode.dbValue);
  }

  Future<bool> residentAccess({
    required bool register,
    required String companyId,
    required String phone,
    required String password,
    String firstName = '',
    String lastName = '',
    String neighborhood = '',
    String street = '',
    String houseNumber = '',
  }) async {
    if (authOperation) return false;
    var success = false;
    authOperation = true;
    await _run(() async {
      final digits = _normalizePhone(phone);
      if (!RegExp(r'^998\d{9}$').hasMatch(digits)) throw Exception(tr('phone_format'));
      if (register && password.length < 8) throw Exception(tr('password_min'));
      final email = _userAuthEmail(companyId: companyId, phoneDigits: digits);
      if (register) {
        if ([firstName, lastName, neighborhood, street, houseNumber].any((s) => s.trim().isEmpty)) {
          throw Exception(tr('fill_required'));
        }
        // Resume a partially completed registration only with valid credentials.
        if (client.auth.currentUser?.email != email) {
          try {
            await client.auth.signInWithPassword(email: email, password: password);
          } on AuthException catch (e) {
            if (e.code != 'invalid_credentials') rethrow;
            final response = await client.auth.signUp(email: email, password: password);
            if (response.session == null) throw Exception(tr('registration_unavailable'));
          }
        }
        final user = client.auth.currentUser;
        if (user == null) throw Exception(tr('registration_unavailable'));
        // RPC only creates the resident role and never overwrites existing data.
        await client.rpc('servicepro_complete_resident', params: {
          'p_company_id': companyId, 'p_first_name': firstName.trim(),
          'p_last_name': lastName.trim(), 'p_phone': digits,
          'p_neighborhood': neighborhood.trim(), 'p_street': street.trim(),
          'p_house_number': houseNumber.trim(), 'p_language': authLanguage.dbValue,
        });
      } else {
        await client.auth.signInWithPassword(email: email, password: password);
      }
      await _loadCurrentProfile();
      if (currentProfile?.role != UserRole.user || currentProfile?.companyId != companyId) {
        throw Exception(tr('account_mismatch'));
      }
      success = true;
    });
    if (currentProfile?.id != client.auth.currentUser?.id) clearSessionData();
    authOperation = false;
    _notifyStateChanged();
    return success;
  }

  static String staffEmail(String companyId, String firstName, String lastName) {
    final identity = '$companyId|${firstName.trim().toLowerCase()}|${lastName.trim().toLowerCase()}';
    return 'staff_${sha256.convert(utf8.encode(identity)).toString().substring(0, 48)}@servicepro.local';
  }

  Future<bool> staffAccess({required String companyId, required UserRole role,
    required String firstName, required String lastName, required String password,
    required String jobTitle, required bool firstAccess, required String companyCode}) async {
    if (authOperation) return false;
    authOperation = true;
    var success = false;
    await _run(() async {
      if (![UserRole.director, UserRole.admin, UserRole.worker].contains(role)) throw Exception(tr('account_mismatch'));
      final email = staffEmail(companyId, firstName, lastName);
      if (firstAccess && password.length < 8) throw Exception(tr('password_min'));
      final validCode = await client.rpc('servicepro_check_company_code', params: {
        'p_company_id': companyId, 'p_code': companyCode.trim(),
      });
      if (validCode != true) throw Exception(tr('company_code_invalid'));
      if (firstAccess) {
        try {
          await client.auth.signInWithPassword(email: email, password: password);
        } on AuthException catch (e) {
          if (e.code != 'invalid_credentials') rethrow;
          final response = await client.auth.signUp(email: email, password: password);
          if (response.session == null) throw Exception(tr('registration_unavailable'));
        }
        await client.rpc('servicepro_join_company_staff', params: {
          'p_company_id': companyId, 'p_role': role.dbValue, 'p_code': companyCode.trim(),
          'p_first_name': firstName.trim(), 'p_last_name': lastName.trim(),
          'p_job_title': jobTitle.trim(), 'p_language': authLanguage.dbValue,
        });
      } else {
        await client.auth.signInWithPassword(email: email, password: password);
      }
      final row = await client.from('profiles').select('role,company_id').eq('id', client.auth.currentUser!.id).single();
      if (row['role'] != role.dbValue || row['company_id'] != companyId) {
        await logout();
        throw Exception(tr('account_mismatch'));
      }
      await _loadCurrentProfile();
      success = currentProfile != null;
    });
    if (currentProfile?.id != client.auth.currentUser?.id) clearSessionData();
    authOperation = false;
    _notifyStateChanged();
    return success;
  }

  Future<bool> legacyAccess(String email, String password) async {
    if (authOperation) return false;
    authOperation = true;
    var success = false;
    await _run(() async {
      await client.auth.signInWithPassword(email: email.trim(), password: password);
      await _loadCurrentProfile();
      if (currentProfile == null) throw Exception(tr('account_mismatch'));
      success = true;
    });
    if (currentProfile?.id != client.auth.currentUser?.id) clearSessionData();
    authOperation = false;
    _notifyStateChanged();
    return success;
  }

  Future<void> refreshTeamStats() async {
    if (currentProfile == null || _teamStatsRefreshBusy) return;
    _teamStatsRefreshBusy = true;
    try {
      final rows = await client.rpc('servicepro_team_directory');
      teamStats..clear()..addAll((rows as List).map((r) => Map<String, dynamic>.from(r)));
      teamStatsError = null;
    } catch (error) {
      // Keep previously fetched actual ratings instead of silently showing an
      // empty or fabricated ranking when the server is temporarily unavailable.
      teamStatsError = friendlyError('$error');
    } finally {
      _teamStatsRefreshBusy = false;
      _notifyStateChanged();
    }
  }
}
