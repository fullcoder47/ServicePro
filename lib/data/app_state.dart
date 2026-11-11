import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../core/platform/browser_io_stub.dart' if (dart.library.io) 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/platform/upload_from_path.dart';
import '../core/platform/internet_probe.dart';
import '../core/notifications/notification_service.dart';
import 'models.dart';
import 'session_devices_repository.dart';

part 'onboarding_state.dart';
part 'workforce_state.dart';

bool _validAdvertisementUrl(String value) {
  if (value.length > 2048 || value.contains(RegExp(r'\s'))) return false;
  final parsed = Uri.tryParse(value);
  return parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty && parsed.userInfo.isEmpty;
}

class AppState extends ChangeNotifier {
  /// Inert state for isolated widget tests; never initializes network services.
  AppState.forTesting() { appReady = true; }

  AppState() {
    if (SupabaseConfig.isConfigured) {
      _client = Supabase.instance.client;
      _authSub = _client!.auth.onAuthStateChange.listen((event) async {
        if (authOperation || event.event == AuthChangeEvent.tokenRefreshed) return;
        try {
          await boot();
        } catch (e) {
          errorMessage = _prettyError(e);
          notifyListeners();
        }
      });
      _initializeApp();
    } else {
      appReady = true;
    }


    _loadAddressSuggestions();
    _loadAuthLanguage();
    // Browser runtimes cannot resolve DNS with InternetAddress.lookup.
    // Keep the app reachable on web; network failures are reported by the
    // actual Supabase request instead of a false offline screen.
    if (kIsWeb) {
      isOnline = true;
      networkChecked = true;
    } else {
      _startInternetChecker();
    }



  }

  Future<void> _initializeApp() async {
    final startedAt = DateTime.now();
    try {
      // Never leave the startup screen spinning forever on a slow connection.
      // The pending request can still finish and update the signed-in profile.
      await boot().timeout(const Duration(seconds: 8));
    } catch (e) {
      errorMessage = e is TimeoutException
          ? 'Ulanish sekin. Internetni tekshiring va qayta urinib ko‘ring.'
          : _prettyError(e);
    } finally {
      final elapsed = DateTime.now().difference(startedAt);
      // Only keep the brand splash long enough to avoid a visual flash.
      // Remote lists are fetched after the initial profile is available.
      const minimumSplash = Duration(milliseconds: 350);
      if (elapsed < minimumSplash) {
        await Future<void>.delayed(minimumSplash - elapsed);
      }
      appReady = true;
      notifyListeners();
    }
  }

  static const superAdminEmail = 'fullcoder47@gmail.com';

  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<Map<String, dynamic>>>? _billingSub;
  StreamSubscription<List<Map<String, dynamic>>>? _ticketSub;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSub;
  StreamSubscription<List<Map<String, dynamic>>>? _chatRoomsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _chatMessagesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _typingSub;
  StreamSubscription<List<Map<String, dynamic>>>? _chatReadsSub;
  Timer? _autoRefreshTimer;
  Timer? _sessionHeartbeatTimer;
  Timer? _billingRefreshTimer;
  bool _billingRefreshInProgress = false;
  Timer? _typingStopTimer;
  Timer? _readRefreshTimer;
  Timer? _networkTimer;
  bool _networkCheckInProgress = false;
  bool _autoRefreshInProgress = false;
  final Set<String> _knownNotificationIds = <String>{};
  final Set<String> _knownTicketIds = <String>{};
  final Set<String> _knownMessageIds = <String>{};
  final Map<String, Set<String>> _messageReadBy = <String, Set<String>>{};

  bool authOperation = false;
  ThemeMode guestThemeMode = ThemeMode.system;
  final List<Company> publicCompanies = [];
  final List<Map<String, dynamic>> teamStats = [];
  String? teamStatsError;
  bool _teamStatsRefreshBusy = false;
  bool loading = false;
  bool appReady = false;
  bool isOnline = true;
  bool networkChecked = false;
  String? errorMessage;
  Profile? currentProfile;
  int selectedIndex = 0;
  AppLanguage authLanguage = AppLanguage.uz;

  final List<Company> companies = [];
  final List<Profile> profiles = [];
  final List<Building> buildings = [];
  final List<Ticket> tickets = [];
  final List<ServiceNotification> notifications = [];
  final List<ChatRoom> chatRooms = [];
  final List<ChatMessage> activeChatMessages = [];
  // Keep a small, profile-scoped snapshot so reopening a room is immediate.
  final Map<String, List<ChatMessage>> _recentChatMessages = {};
  int chatRevision = 0;
  final uploadProgress = ValueNotifier<double?>(null);
  int _chatWatchGeneration = 0;
  final Set<String> _committedTicketRequests = {};
  bool isTicketRequestCommitted(String id) => _committedTicketRequests.contains(id);
  bool _notificationBaselineReady = false;
  bool _markingChatRead = false;
  final Map<String, Map<PickedAttachment, String>> _ticketUploadCache = {};
  final List<CompanySubscription> subscriptions = [];
  final List<CompanyPayment> payments = [];
  final List<ScheduledNotification> scheduledNotifications = [];
  final Map<String, dynamic> appSettings = <String, dynamic>{};
  final List<Profile> typingProfiles = [];
  Map<String, Set<String>> get messageReadBy => _messageReadBy;
  final List<String> addressSuggestions = [];
  String? activeChatRoomId;

  ThemeMode get themeMode => currentProfile?.themeMode ?? guestThemeMode;
  bool get isConfigured => SupabaseConfig.isConfigured;

  // Same-library extensions call this instance member instead of the protected
  // ChangeNotifier method directly.
  void _notifyStateChanged() => notifyListeners();

  SupabaseClient get client => _client ?? Supabase.instance.client;

  /// True when this instance was constructed with a connected client.
  /// Offline widget tests deliberately use a state without one.
  bool get hasBackendClient => _client != null;

  /// Notify dependent screens after an extension/repository updates a profile.
  void notifyStateChanged() => notifyListeners();

  @override
  void dispose() {
    uploadProgress.dispose();
    _authSub?.cancel();
    _ticketSub?.cancel();
    _notificationSub?.cancel();
    _chatRoomsSub?.cancel();
    _chatMessagesSub?.cancel();
    _typingSub?.cancel();
    _chatReadsSub?.cancel();
    _autoRefreshTimer?.cancel();
    _sessionHeartbeatTimer?.cancel();
    _billingRefreshTimer?.cancel();
    _billingSub?.cancel();
    _typingStopTimer?.cancel();
    _readRefreshTimer?.cancel();
    _networkTimer?.cancel();
    super.dispose();
  }


  void _startInternetChecker() {
    _networkTimer?.cancel();
    unawaited(checkInternetNow());
    _networkTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(checkInternetNow());
    });
  }

  Future<bool> checkInternetNow() async {
    if (kIsWeb) {
      if (!isOnline || !networkChecked) {
        isOnline = true;
        networkChecked = true;
        notifyListeners();
      }
      return true;
    }
    if (_networkCheckInProgress) return isOnline;
    _networkCheckInProgress = true;
    var online = false;
    try {
      online = await probeInternet();
    } catch (_) {
      online = false;
    } finally {
      _networkCheckInProgress = false;
    }
    if (online != isOnline || !networkChecked) {
      isOnline = online;
      networkChecked = true;
      notifyListeners();
      if (online && currentProfile != null) {
        unawaited(refreshTickets(notify: false));
        unawaited(refreshNotifications(notify: false));
        unawaited(refreshChatRooms(notify: false));
      }
    }
    return online;
  }

  Future<void> boot() async {
    if (!isConfigured) return;
    final user = client.auth.currentUser;
    if (user == null) {
      clearSessionData();
      notifyListeners();
      return;
    }
    await _loadCurrentProfile();
  }

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      errorMessage = _prettyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _prettyError(Object error) {
    final text = error.toString();
    if(text.contains('worker_required')) return tr('choose_worker');
    if(text.contains('worker_access_denied')) return tr('only_own_workers');
    if(text.contains('invalid_rating') || text.contains('rating_unavailable')) return tr('rating_failed');
    if (text.contains('Email not confirmed')) return 'Email tasdiqlanmagan. Supabase Auth settingsdan Confirm emailni test payti o‘chirib qo‘ying.';
    if (text.contains('Invalid login credentials')) return 'Email yoki parol noto‘g‘ri.';
    if (text.contains('JWT')) return 'Sessiya tugagan. Qayta kiring.';
    if (text.contains('create_service_ticket')) return 'Server yangilanishi kerak. Tegishli yangi migratsiyani o‘rnating.';
    if (text.contains('address_text')) return 'Supabase tickets jadvalida address_text ustuni yo‘q. servicepro_schema.sql ni qayta run qiling.';
    if (text.contains('ticket-files')) return 'Supabase Storage’da ticket-files bucket yaratilmagan yoki policy yo‘q.';
    if (text.contains('chat_') || text.contains('chat_rooms') || text.contains('chat_messages')) return 'Supabase chat SQL yangilanmagan. servicepro_schema.sql faylini qayta run qiling.';
    if (text.contains('scheduled_notifications')) return 'Bildirishnoma jadvali yangilanishi kerak. Tegishli migratsiyani o‘rnating.';
    if (text.contains('subscriptions') || text.contains('payments') || text.contains('billing')) return tr('billing_sql_missing');
    if (text.contains('media_urls') || text.contains('notification_type') || text.contains('avatar_url') || text.contains('ad_group_id') || text.contains('device_tokens')) return 'Server yangilanishi kerak. Tegishli yangi migratsiyani o‘rnating.';
    return friendlyError(text.replaceAll('Exception: ', ''));
  }

  String friendlyError(String raw) {
    final lang = currentProfile?.language ?? authLanguage;
    var cleaned = raw
        .replaceAll('PostgrestException(message:', '')
        .replaceAll('AuthException(message:', '')
        .replaceAll('StorageException(message:', '')
        .replaceAll('Exception:', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final text = cleaned.toLowerCase();

    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('offline') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception')) {
      return AppStrings.translate('error_network', lang);
    }
    if (text.contains('permission') ||
        text.contains('denied') ||
        text.contains('policy') ||
        text.contains('rls') ||
        text.contains('not authorized')) {
      return AppStrings.translate('error_permission', lang);
    }
    if (text.contains('duplicate') ||
        text.contains('unique') ||
        text.contains('already exists')) {
      return AppStrings.translate('error_duplicate', lang);
    }
    if (text.contains('not found') ||
        text.contains('0 rows') ||
        text.contains('no rows')) {
      return AppStrings.translate('error_not_found', lang);
    }
    if (text.contains('timeout')) {
      return AppStrings.translate('error_timeout', lang);
    }

    // Play Marketga tayyor ko‘rinish uchun texnik SQL/stack textlarni userga chiqarmaymiz.
    if (cleaned.length > 140 ||
        text.contains('code:') ||
        text.contains('details:') ||
        text.contains('hint:') ||
        text.contains('pgrst') ||
        text.contains('sqlstate')) {
      return AppStrings.translate('error_unknown', lang);
    }

    return cleaned.isEmpty ? AppStrings.translate('error_unknown', lang) : cleaned;
  }

  bool _requireFields(Map<String, String> fields) {
    for (final entry in fields.entries) {
      if (entry.value.trim().isEmpty) {
        errorMessage = '${entry.key} majburiy.';
        notifyListeners();
        return false;
      }
    }
    return true;
  }


  Future<void> _loadAuthLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      authLanguage = AppLanguageX.fromDb(prefs.getString('auth_language'));
      guestThemeMode = ThemeModeDbX.fromDb(prefs.getString('guest_theme'));
      notifyListeners();
    } catch (_) {
      // Til yuklanmasa app default Uzbek bilan davom etadi.
    }
  }

  Future<void> setAuthLanguage(AppLanguage language) async {
    authLanguage = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_language', language.dbValue);
    } catch (_) {
      // Til saqlanmasa ham UI ishlashda davom etadi.
    }
  }

  String authTr(String key) => AppStrings.translate(key, authLanguage);

  Future<void> signIn({required String email, required String password}) async {
    if (!_requireFields({'Email': email, 'Parol': password})) return;
    await _run(() async {
      await client.auth.signInWithPassword(email: email.trim(), password: password.trim());
      await _loadCurrentProfile();
    });
  }

  Future<void> signInWithGoogle() async {
    if (!isConfigured) {
      errorMessage = 'Supabase sozlanmagan.';
      notifyListeners();
      return;
    }

    errorMessage = null;
    loading = true;
    notifyListeners();

    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.fullcoder.servicepro://login-callback',
      );
      if (!launched) {
        throw Exception('Google kirish oynasi ochilmadi. Qayta urinib ko‘ring.');
      }
    } catch (e) {
      errorMessage = _prettyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> signInUserWithPhone({
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
    required String companyPassword,
  }) async {
    if (!_requireFields({'Telefon': phone, 'Parol': password, 'Kompaniya kodi': companyPassword})) return;
    await _run(() async {
      final cleanPassword = password.trim();
      if (cleanPassword.length < 6) throw Exception('Parol kamida 6 ta belgidan iborat bo‘lsin.');

      final company = await client.rpc('find_company_by_join_password', params: {'p_join_password': companyPassword.trim()}).single();
      final companyId = '${company['id']}';
      final phoneDigits = _normalizePhone(phone);
      if (phoneDigits.length < 7) throw Exception('Telefon raqamni to‘liq kiriting.');

      final authEmail = _userAuthEmail(companyId: companyId, phoneDigits: phoneDigits);
      var createdNewUser = false;

      try {
        await client.auth.signInWithPassword(email: authEmail, password: cleanPassword);
      } catch (e) {
        final message = e.toString().toLowerCase();
        final canTryCreate = message.contains('invalid login') || message.contains('credentials') || message.contains('not found');
        if (!canTryCreate) rethrow;
        if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
          throw Exception('Birinchi kirishda ism va familiya majburiy. Oldin ro‘yxatdan o‘tgan bo‘lsangiz, telefon yoki parolni tekshiring.');
        }
        final auth = await client.auth.signUp(email: authEmail, password: cleanPassword);
        if (auth.user == null && client.auth.currentUser == null) {
          await client.auth.signInWithPassword(email: authEmail, password: cleanPassword);
        }
        createdNewUser = true;
      }

      final user = client.auth.currentUser;
      if (user == null) throw Exception('User auth yaratilmadi. Supabase Auth sozlamasini tekshiring.');

      final existing = await client.from('profiles').select('id').eq('id', user.id).maybeSingle();
      if (existing == null) {
        if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
          throw Exception('Profil topilmadi. Birinchi kirishda ism va familiyani kiriting.');
        }
        await client.from('profiles').insert({
          'id': user.id,
          'company_id': companyId,
          'role': UserRole.user.dbValue,
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone': phone.trim(),
          'email': authEmail,
          'language': authLanguage.dbValue,
        });
      } else if (createdNewUser) {
        await client.from('profiles').update({
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone': phone.trim(),
          'language': authLanguage.dbValue,
        }).eq('id', user.id);
      }

      await _loadCurrentProfile();
    });
  }

  String _normalizePhone(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _userAuthEmail({required String companyId, required String phoneDigits}) {
    final cleanCompany = companyId.replaceAll('-', '');
    return 'user_${cleanCompany}_$phoneDigits@servicepro.local';
  }

  Future<void> _loadCurrentProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final data = await client.from('profiles').select().eq('id', user.id).maybeSingle();
    // A slow profile lookup must never restore a user who has signed out.
    if (client.auth.currentUser?.id != user.id) return;
    if (data == null) {
      clearSessionData();
      notifyListeners();
      return;
    }
    final accountChanged = currentProfile?.id != user.id;
    if (accountChanged) clearSessionData();
    currentProfile = Profile.fromMap(data);
    if (accountChanged) selectedIndex = 0;
    _startRealtime();
    _startAutoRefresh();
    _startSessionHeartbeat();
    unawaited(NotificationService.registerCurrentDevice());
    notifyListeners();
    // Do not block opening the main screen on tickets, chat and billing.
    // The account identity is ready; supplementary data can load in parallel.
    unawaited(_finishProfileLoad(user.id));
  }

  Future<void> _finishProfileLoad(String profileId) async {
    try {
      if (currentProfile?.role == UserRole.user) {
        try {
          final address = await client.from('resident_addresses')
              .select().eq('profile_id', profileId).maybeSingle();
          if (currentProfile?.id == profileId && address != null) {
            currentProfile!
              ..neighborhood = '${address['neighborhood'] ?? ''}'
              ..street = '${address['street'] ?? ''}'
              ..houseNumber = '${address['house_number'] ?? ''}';
            notifyListeners();
          }
        } catch (_) { /* Older databases need not have this table. */ }
      }
      if (currentProfile?.id != profileId) return;
      await _refreshStaticData();
      if (currentProfile?.id == profileId) notifyListeners();
    } catch (e) {
      if (currentProfile?.id == profileId) {
        errorMessage = _prettyError(e);
        notifyListeners();
      }
    }
  }

  Future<void> _refreshStaticData() async {
    final me = currentProfile;
    if (me == null) return;
    final isSuper = me.role == UserRole.superAdmin;

    final companyRows = isSuper
        ? await client.from('companies').select().order('created_at')
        : await client.from('companies').select().eq('id', me.companyId ?? '').order('created_at');
    if (currentProfile?.id != me.id) return;
    companies
      ..clear()
      ..addAll((companyRows as List).map((e) => Company.fromMap(Map<String, dynamic>.from(e))));

    final profileRows = isSuper
        ? await client.from('profiles').select().order('created_at')
        : await client.from('profiles').select().eq('company_id', me.companyId ?? '').order('created_at');
    if (currentProfile?.id != me.id) return;
    profiles
      ..clear()
      ..addAll((profileRows as List).map((e) => Profile.fromMap(Map<String, dynamic>.from(e))));

    final buildingRows = isSuper
        ? await client.from('buildings').select().order('street')
        : await client.from('buildings').select().eq('company_id', me.companyId ?? '').order('street');
    if (currentProfile?.id != me.id) return;
    buildings
      ..clear()
      ..addAll((buildingRows as List).map((e) => Building.fromMap(Map<String, dynamic>.from(e))));

    final ticketRows = isSuper
        ? await client.from('tickets').select().order('created_at', ascending: false)
        : me.role == UserRole.user
            ? await client.from('tickets').select().eq('created_by', me.id).order('created_at', ascending: false)
            : await client.from('tickets').select().eq('company_id', me.companyId ?? '').order('created_at', ascending: false);
    if (currentProfile?.id != me.id) return;
    tickets
      ..clear()
      ..addAll((ticketRows as List).map((e) => Ticket.fromMap(Map<String, dynamic>.from(e))));
    _sortTicketsNewestFirst();

    await refreshNotifications(notify: false);

    await refreshChatRooms(notify: false);
    await refreshBilling(notify: false);
    await refreshTeamStats();
    if (isSuper) {
      await refreshScheduledNotifications(notify: false);
    }
  }

  Future<void> refreshAllForSuperAdmin() async {
    await _run(() async {
      await _refreshStaticData();
      await refreshTickets(notify: false);
      await refreshNotifications(notify: false);
      await refreshChatRooms(notify: false);
      await refreshBilling(notify: false);
      await refreshScheduledNotifications(notify: false);
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _billingRefreshTimer?.cancel();
    if (!isConfigured || currentProfile == null) return;
    // Realtime is primary; a slower backup poll recovers missed events without
    // making several full-table requests every second.
    final role = currentProfile!.role;
    if (role == UserRole.director || role == UserRole.admin || role == UserRole.worker) {
      _billingRefreshTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => unawaited(refreshBillingStatus()));
    }
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_autoRefreshInProgress || currentProfile == null) return;
      _autoRefreshInProgress = true;
      final profileId = currentProfile!.id;
      try {
        await refreshTickets(notify: false);
        if (currentProfile?.id != profileId) return;
        await refreshNotifications(notify: false);
        if (currentProfile?.id != profileId) return;
        await refreshChatRooms(notify: false);
        if (currentProfile?.id != profileId) return;
        final roomId = activeChatRoomId;
        if (roomId != null) {
          await refreshChatMessages(roomId, notify: false);
          await refreshTyping(roomId, notify: false);
        }
        if (currentProfile?.id == profileId) notifyListeners();
      } catch (_) {
        // Realtime asosiy yo‘l. Auto refresh faqat zaxira, xato bo‘lsa app yiqilmasin.
      } finally {
        _autoRefreshInProgress = false;
      }
    });
  }

  void _startSessionHeartbeat() {
    _sessionHeartbeatTimer?.cancel();
    if (!isConfigured || currentProfile == null) return;
    final repository = SessionDevicesRepository(client);
    unawaited(repository.touchCurrent());
    _sessionHeartbeatTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) {
        if (currentProfile != null && client.auth.currentSession != null) {
          unawaited(repository.touchCurrent());
        }
      },
    );
  }

  void _startRealtime() {
    _billingSub?.cancel();
    _ticketSub?.cancel();
    _notificationSub?.cancel();
    _chatRoomsSub?.cancel();
    final me = currentProfile;
    if (me == null) return;

    if (me.role != UserRole.superAdmin && me.companyId != null) {
      _billingSub = client.from('subscriptions')
          .stream(primaryKey: ['id'])
          .eq('company_id', me.companyId!)
          .listen((rows) {
            if (currentProfile?.id != me.id || rows.isEmpty) return;
            _syncOwnBillingRow(Map<String, dynamic>.from(rows.first));
          }, onError: (_) => unawaited(refreshBillingStatus()));
    }

    dynamic ticketStream = client.from('tickets').stream(primaryKey: ['id']).order('created_at');
    if (me.role == UserRole.user) {
      ticketStream = ticketStream.eq('created_by', me.id);
    } else if (me.role != UserRole.superAdmin) {
      ticketStream = ticketStream.eq('company_id', me.companyId ?? '');
    }
    _ticketSub = ticketStream.listen((rows) async {
      if (currentProfile?.id != me.id) return;
      final incoming = rows.map((e) => Ticket.fromMap(Map<String, dynamic>.from(e))).toList();
      _knownTicketIds
        ..clear()
        ..addAll(incoming.map((t) => t.id));
      tickets
        ..clear()
        ..addAll(incoming);
      _sortTicketsNewestFirst();
      await _refreshProfilesAndBuildingsLight();
      notifyListeners();
    });

    _notificationSub = client.from('notifications').stream(primaryKey: ['id']).order('created_at').listen((rows) {
      if (currentProfile?.id != me.id) return;
      final visible = rows.where((e) {
        if (e['profile_id'] == me.id || e['sent_by'] == me.id) return true;
        if (e['notification_type'] != 'advertisement') return false;
        if (e['profile_id'] != null) return false;
        final audience = '${e['audience'] ?? 'direct'}';
        final companyId = e['company_id'] as String?;
        return audience != 'user' && (companyId == null || companyId == me.companyId || me.role == UserRole.superAdmin);
      });
      final incoming = visible.map((e) => ServiceNotification.fromMap(Map<String, dynamic>.from(e))).toList();
      _notifyOnNewInboxItems(incoming, me.id);
      notifications
        ..clear()
        ..addAll(incoming);
      _sortNotificationsNewestFirst();
      if(activeChatRoomId!=null && NotificationService.activeChatRoomId==activeChatRoomId) {
        for(final item in incoming.where((n)=>n.profileId==me.id && !n.isRead && n.chatRoomId==activeChatRoomId &&
          n.chatMessageId!=null && (_messageReadBy[n.chatMessageId]?.contains(me.id)??false))){
          unawaited(markNotificationRead(item));
        }
      }
      notifyListeners();
    }, onError: (_) async {
      await refreshNotifications();
    });

    dynamic chatRoomStream = client.from('chat_rooms').stream(primaryKey: ['id']).order('last_message_at');
    if (me.role != UserRole.superAdmin) {
      chatRoomStream = chatRoomStream.eq('company_id', me.companyId ?? '');
    }
    _chatRoomsSub = chatRoomStream.listen((rows) async {
      if (currentProfile?.id != me.id) return;
      chatRooms
        ..clear()
        ..addAll(rows.map((e) => ChatRoom.fromMap(Map<String, dynamic>.from(e))));
      _sortChatRoomsNewestFirst();
      notifyListeners();
    }, onError: (_) async {
      await refreshChatRooms();
    });
  }

  Future<void> _refreshProfilesAndBuildingsLight() async {
    final me = currentProfile;
    if (me == null) return;
    final isSuper = me.role == UserRole.superAdmin;
    final profileRows = isSuper
        ? await client.from('profiles').select().order('created_at')
        : await client.from('profiles').select().eq('company_id', me.companyId ?? '').order('created_at');
    if (currentProfile?.id != me.id) return;
    profiles
      ..clear()
      ..addAll((profileRows as List).map((e) => Profile.fromMap(Map<String, dynamic>.from(e))));
  }

  void _sortTicketsNewestFirst() {
    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Ticket> visibleTickets() => List<Ticket>.of(tickets);
  List<Profile> visibleProfiles() => List<Profile>.of(profiles);
  List<Company> visibleCompanies() => List<Company>.of(companies);

  int get unreadChatCount => notifications.where((n) => !n.isRead && n.notificationType == 'chat' && n.profileId == currentProfile?.id).length;

  int get unreadTicketCount => notifications.where((n) => !n.isRead && n.ticketId != null && n.profileId == currentProfile?.id).length;

  int get unreadNotificationCount => notifications.where((n) => !n.isRead && n.profileId == currentProfile?.id).length;

  int get unreadAdvertisementCount => notifications.where((n) => !n.isRead && n.notificationType == 'advertisement' && n.profileId == currentProfile?.id).length;

  Company? companyById(String? id) {
    if (id == null) return null;
    for (final company in companies) {
      if (company.id == id) return company;
    }
    return null;
  }

  Profile? profileById(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Building? buildingById(String? id) {
    if (id == null) return null;
    for (final building in buildings) {
      if (building.id == id) return building;
    }
    return null;
  }

  List<Building> availableBuildings() {
    final me = currentProfile;
    if (me == null) return [];
    if (me.role == UserRole.superAdmin) return buildings;
    return buildings.where((b) => b.companyId == me.companyId).toList();
  }

  static String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  Future<bool> createTicket({
    required String addressText,
    required String apartmentNumber,
    required String description,
    required List<PickedAttachment> attachments,
    String? requestId,
  }) async {
    final me = currentProfile;
    if (me == null || me.homeAddress.trim().isEmpty || me.phone.trim().isEmpty) {
      errorMessage = 'Profilingizdagi ism, telefon va yashash manzilini to‘ldiring.';
      notifyListeners(); return false;
    }
    if (description.trim().isEmpty) { errorMessage = tr('fill_ticket_required'); notifyListeners(); return false; }
    var success = false;
    await _run(() async {
      final row = await client.rpc('servicepro_create_profile_ticket', params: {
        'p_request_id': requestId ?? newRequestId(), 'p_description': description.trim(),
      }).single();
      var result = Map<String,dynamic>.from(row as Map);
      final ticketId = '${result['id']}';
      if(requestId!=null) _committedTicketRequests.add(requestId);
      _upsertTicket(Ticket.fromMap(result));
      if (attachments.isNotEmpty) {
        final urls = await _uploadAttachments(ticketId: ticketId, files: attachments, folder: 'request');
        final saved = await _setTicketAttachments(ticketId: ticketId, urls: urls);
        final stored = (saved?['attachments'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
        if (!urls.every(stored.contains)) throw Exception('Ariza saqlandi, media to‘liq biriktirilmadi. Shu sahifada qayta yuboring — ariza takrorlanmaydi.');
        result = saved!;
      }
      _upsertTicket(Ticket.fromMap(result));
      _ticketUploadCache.remove('$ticketId/request');
      setSelectedIndex(1);
      // Database triggers create durable notification jobs in the same transaction.
      success = true;
    });
    return success;
  }

  // Retained for recovery of partially submitted ticket requests.
  // ignore: unused_element
  Future<Map<String, dynamic>?> _findRecentlyCreatedTicket({
    required String companyId,
    required String createdBy,
    required String addressText,
    required String apartmentNumber,
    required String description,
  }) async {
    final row = await client
        .from('tickets')
        .select()
        .eq('company_id', companyId)
        .eq('created_by', createdBy)
        .eq('address_text', addressText)
        .eq('apartment_number', apartmentNumber)
        .eq('description', description)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>?> _fetchTicketById(String ticketId) async {
    final row = await client.from('tickets').select().eq('id', ticketId).maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>?> _setTicketAttachments({required String ticketId, required List<String> urls}) async {
    try {
      final row = await client
          .rpc('set_ticket_request_attachments', params: {
            'p_ticket_id': ticketId,
            'p_attachments': urls,
          })
          .select()
          .maybeSingle();

      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('set_ticket_request_attachments rpc skipped: $e');
    }

    try {
      final row = await client
          .from('tickets')
          .update({'attachments': urls})
          .eq('id', ticketId)
          .select()
          .maybeSingle();

      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('direct ticket attachment update skipped: $e');
    }

    return _fetchTicketById(ticketId);
  }

  Future<void> acceptTicket(Ticket ticket, {String? workerId}) async {
    final me = currentProfile;
    if (me == null) throw Exception('Avval tizimga kiring.');

    await _run(() async {
      final row = await client.rpc('servicepro_transition_ticket_worker', params: {
        'p_ticket_id': ticket.id, 'p_complete': false, 'p_worker_id': workerId,
        'p_description': '', 'p_media': <String>[],
      }).single();

      _upsertTicket(Ticket.fromMap(Map<String, dynamic>.from(row)));

      await refreshTickets(notify: false);
      await refreshNotifications(notify: false);
    });
  }

  Future<void> completeTicket({required Ticket ticket, required String description, required List<PickedAttachment> attachments, String? workerId}) async {
    final me = currentProfile;
    if (me == null) throw Exception('Avval tizimga kiring.');
    if (description.trim().isEmpty) throw Exception('Bajarilgan ish tavsifi majburiy.');
    if (attachments.isEmpty) throw Exception('Bajarildi qilish uchun rasm yoki video majburiy.');

    await _run(() async {
      final urls = await _uploadAttachments(ticketId: ticket.id, files: attachments, folder: 'completion');
      if (urls.isEmpty) throw Exception('Rasm/video yuklanmadi. Boshqa fayl tanlab ko‘ring.');

      final row = await client.rpc('servicepro_transition_ticket_worker', params: {
        'p_ticket_id': ticket.id, 'p_complete': true, 'p_worker_id': workerId,
        'p_description': description.trim(), 'p_media': urls,
      }).single();

      _upsertTicket(Ticket.fromMap(Map<String, dynamic>.from(row)));

      await refreshTickets(notify: false);
      await refreshNotifications(notify: false);
    });
  }

  Future<void> closeTicket(Ticket ticket) async {
    await _run(() async {
      final row = await client
          .from('tickets')
          .update({'status': TicketStatus.closed.dbValue})
          .eq('id', ticket.id)
          .select()
          .maybeSingle();

      final updatedMap = row == null ? await _fetchTicketById(ticket.id) : Map<String, dynamic>.from(row as Map);
      if (updatedMap != null) _upsertTicket(Ticket.fromMap(updatedMap));
      await refreshTickets(notify: false);
      await refreshNotifications(notify: false);
    });
  }

  Future<List<String>> _uploadAttachments({required String ticketId, required List<PickedAttachment> files, required String folder}) async {
    final urls = <String>[];
    final cache = _ticketUploadCache.putIfAbsent('$ticketId/$folder', () => {});
    if (files.length > 6 || files.fold<double>(0, (sum, f) => sum + f.sizeInMb) > 120) {
      throw Exception('Maksimal 6 fayl, jami 120 MB.');
    }
    uploadProgress.value = 0;
    try {
    for (final file in files) {
      if (cache.containsKey(file)) { urls.add(cache[file]!); continue; }
      if (file.bytes.isEmpty && file.localPath==null) throw Exception('Bo‘sh media fayli.');
      if (!file.isVideo && file.sizeInMb > 8) {
        throw Exception('${file.name} juda katta. Rasm maksimal 8 MB bo‘lsin.');
      }
      if (file.isVideo && file.sizeInMb > 60) {
        throw Exception('${file.name} juda katta. Video maksimal 60 MB bo‘lsin.');
      }
      final rawExt = file.name.contains('.') ? file.name.split('.').last : (file.isVideo ? 'mp4' : 'jpg');
      final safeExt = rawExt.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
      final ext = safeExt.isEmpty ? (file.isVideo ? 'mp4' : 'jpg') : safeExt;
      final path = '$ticketId/$folder/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}.$ext';
      await _uploadPickedFile(path,file,ext);
      final url = client.storage.from('ticket-files').getPublicUrl(path);
      cache[file] = url;
      urls.add(url);
      uploadProgress.value = urls.length / files.length;
    }
    return urls;
    } finally { uploadProgress.value = null; }
  }

  Future<void> _uploadPickedFile(String path,PickedAttachment file,String ext) async {
    final options=FileOptions(contentType:_contentType(ext,file.isVideo),upsert:false);
    if(file.isVideo && file.localPath!=null){
      await uploadStorageFileFromPath(client, 'ticket-files', path,
        file.localPath!, options);
    } else {
      await client.storage.from('ticket-files').uploadBinary(path,file.bytes,fileOptions:options);
    }
  }

  String _contentType(String ext, bool isVideo) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      case 'mp4':
        return 'video/mp4';
      default:
        return isVideo ? 'video/mp4' : 'image/jpeg';
    }
  }


  Future<void> refreshTickets({bool notify = true}) async {
    final me = currentProfile;
    if (me == null) return;
    final rows = me.role == UserRole.superAdmin
        ? await client.from('tickets').select().order('created_at', ascending: false)
        : me.role == UserRole.user
            ? await client.from('tickets').select().eq('created_by', me.id).order('created_at', ascending: false)
            : await client.from('tickets').select().eq('company_id', me.companyId ?? '').order('created_at', ascending: false);
    if (currentProfile?.id != me.id) return;
    tickets
      ..clear()
      ..addAll((rows as List).map((e) => Ticket.fromMap(Map<String, dynamic>.from(e))));
    _sortTicketsNewestFirst();
    _knownTicketIds
      ..clear()
      ..addAll(tickets.map((t) => t.id));
    if (notify) notifyListeners();
  }

  void _upsertTicket(Ticket ticket) {
    final index = tickets.indexWhere((item) => item.id == ticket.id);
    if (index == -1) {
      tickets.add(ticket);
    } else {
      tickets[index] = ticket;
    }
    _sortTicketsNewestFirst();
    notifyListeners();
  }

  Future<void> _loadAddressSuggestions() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList('servicepro_address_suggestions') ?? const <String>[];
    addressSuggestions
      ..clear()
      ..addAll(items.where((e) => e.trim().isNotEmpty));
    notifyListeners();
  }

  // Preserved for older locally stored address suggestions.
  // ignore: unused_element
  Future<void> _saveAddressSuggestion(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return;
    addressSuggestions.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    addressSuggestions.insert(0, clean);
    if (addressSuggestions.length > 12) {
      addressSuggestions.removeRange(12, addressSuggestions.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('servicepro_address_suggestions', addressSuggestions);
  }

  // Compatibility fallback when server-side notification triggers are absent.
  // ignore: unused_element
  Future<void> _notifyCompanyManagers({required String companyId, required String ticketId, required String title, required String body}) async {
    final me = currentProfile;
    final managers = await client
        .from('profiles')
        .select('id')
        .eq('company_id', companyId)
        .inFilter('role', [UserRole.director.dbValue, UserRole.admin.dbValue]);
    final ids = (managers as List)
        .map((e) => '${e['id']}')
        .where((id) => id.isNotEmpty && id != me?.id)
        .toSet()
        .toList();
    final rows = ids.map((id) => {
          'profile_id': id,
          'ticket_id': ticketId,
          'title': title,
          'body': body,
          'notification_type': 'ticket',
          'company_id': companyId,
        }).toList();
    if (rows.isNotEmpty) await client.from('notifications').insert(rows);
    await _sendPushToProfiles(
      profileIds: ids,
      title: title,
      body: body,
      type: 'ticket_created',
      ticketId: ticketId,
    );
  }

  Future<void> _sendPushToProfiles({
    required Iterable<String> profileIds,
    required String title,
    required String body,
    required String type,
    String? ticketId,
    String? chatRoomId,
    String? chatMessageId,
    String? adGroupId,
  }) async {
    // Push delivery belongs to notification-worker. Do not send a second copy.
  }


  void _sortNotificationsNewestFirst() {
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Shared by Realtime and the 15-second fallback poll: a temporary lost
  /// Realtime connection must not silently drop Windows desktop toasts.
  /// Initial inbox history is remembered without displaying old alerts.
  void _notifyOnNewInboxItems(List<ServiceNotification> incoming, String profileId) {
    for (final item in incoming) {
      final forMe = item.profileId == profileId ||
          (item.profileId == null &&
              item.notificationType == 'advertisement' &&
              item.sentBy != profileId);
      if (_notificationBaselineReady && forMe && !item.isRead &&
          !_knownNotificationIds.contains(item.id)) {
        unawaited(NotificationService.showPlainLocalNotification(
          title: item.title,
          body: item.body,
          data: {
            'type': item.notificationType,
            'notification_id': item.id,
            'profile_id': item.profileId ?? '',
            'ticket_id': item.ticketId ?? '',
            'chat_room_id': item.chatRoomId ?? '',
            'chat_message_id': item.chatMessageId ?? '',
            'ad_group_id': item.adGroupId ?? '',
          },
        ));
      }
      _knownNotificationIds.add(item.id);
    }
    _notificationBaselineReady = true;
    // Retain IDs across reconnects but bound the memory consumed by history.
    while (_knownNotificationIds.length > 10000) {
      _knownNotificationIds.remove(_knownNotificationIds.first);
    }
  }

  Future<void> refreshNotifications({bool notify = true}) async {
    final me = currentProfile;
    if (me == null) return;
    final merged = <String, ServiceNotification>{};

    Future<void> addRows(dynamic rows) async {
      for (final row in (rows as List)) {
        final item = ServiceNotification.fromMap(Map<String, dynamic>.from(row));
        merged[item.id] = item;
      }
    }

    if (me.role == UserRole.superAdmin) {
      await addRows(await client.from('notifications').select().order('created_at', ascending: false));
    } else {
      await addRows(await client.from('notifications').select().eq('profile_id', me.id).order('created_at', ascending: false));
      await addRows(await client.from('notifications').select().eq('sent_by', me.id).order('created_at', ascending: false));
      // Public advertisement rows are selected by RLS together with normal advertisement rows.
      try {
        final adRows = await client.from('notifications').select().eq('notification_type', 'advertisement').order('created_at', ascending: false);
        await addRows(adRows);
      } catch (_) {}
    }
    if (currentProfile?.id != me.id) return;

    _notifyOnNewInboxItems(merged.values.toList(), me.id);

    notifications
      ..clear()
      ..addAll(merged.values);
    _sortNotificationsNewestFirst();
    if (notify) notifyListeners();
  }

  List<ServiceNotification> advertisementThreads({bool sentOnly = false, bool receivedOnly = false}) {
    final me = currentProfile;
    if (me == null) return const [];
    final ads = notifications.where((n) {
      if (n.notificationType != 'advertisement') return false;
      if (sentOnly) return me.role == UserRole.superAdmin ? true : n.sentBy == me.id;
      final isPublicForMe = n.profileId == null && n.audience != 'user' && (n.companyId == null || n.companyId == me.companyId || me.role == UserRole.superAdmin);
      if (receivedOnly) return n.profileId == me.id || isPublicForMe;
      return n.sentBy == me.id || n.profileId == me.id || isPublicForMe;
    }).toList();
    final grouped = <String, ServiceNotification>{};
    for (final ad in ads) {
      final key = ad.adGroupId ?? ad.id;
      final old = grouped[key];
      if (old == null || ad.createdAt.isAfter(old.createdAt) || ad.sentBy == me.id) {
        grouped[key] = ad;
      }
    }
    final result = grouped.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<bool> editAdvertisement({
    required ServiceNotification advertisement,
    required String title,
    required String body,
    String? actionUrl,
    String actionLabel = 'Batafsil',
    required List<PickedAttachment> newAttachments,
    bool replaceMedia = false,
  }) async {
    final me = currentProfile;
    if (me == null) return false;
    if (advertisement.sentBy != me.id && me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat o‘zingiz yaratgan reklamani tahrirlaysiz.';
      notifyListeners();
      return false;
    }
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanBody.isEmpty) {
      errorMessage = 'Sarlavha va matn majburiy.';
      notifyListeners();
      return false;
    }
    final cleanUrl = actionUrl?.trim() ?? '';
    if (cleanUrl.isNotEmpty && !_validAdvertisementUrl(cleanUrl)) {
      errorMessage = 'Havola https:// yoki http:// bilan boshlanishi kerak (maksimal 2048 belgi).';
      notifyListeners();
      return false;
    }
    final cleanLabel = actionLabel.trim().isEmpty ? 'Batafsil' : actionLabel.trim();
    if (cleanLabel.length > 40) {
      errorMessage = 'Havola tugmasining nomi 40 belgidan oshmasin.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      var mediaUrls = List<String>.of(advertisement.mediaUrls);
      var mediaTypes = List<String>.of(advertisement.mediaTypes);
      if (replaceMedia) {
        mediaUrls = <String>[];
        mediaTypes = <String>[];
      }
      if (newAttachments.isNotEmpty) {
        final uploaded = await _uploadAdAttachments(files: newAttachments);
        final types = newAttachments.map((file) {
          if (file.isVideo) return 'video';
          final ext = _safeExtension(file.name, fallback: 'jpg');
          return ext == 'gif' ? 'gif' : 'image';
        }).toList();
        mediaUrls = [...mediaUrls, ...uploaded];
        mediaTypes = [...mediaTypes, ...types];
      }
      final groupId = advertisement.adGroupId ?? advertisement.id;
      await client
          .from('notifications')
          .update({
            'title': cleanTitle,
            'body': cleanBody,
            'media_urls': mediaUrls,
            'media_types': mediaTypes,
            'action_url': cleanUrl.isEmpty ? null : cleanUrl,
            'action_label': cleanLabel,
          })
          .eq('ad_group_id', groupId)
          .eq('sent_by', advertisement.sentBy ?? me.id);
      await refreshNotifications();
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<bool> deleteAdvertisement(ServiceNotification advertisement) async {
    final me = currentProfile;
    if (me == null) return false;
    if (advertisement.sentBy != me.id && me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat o‘zingiz yaratgan reklamani o‘chirasiz.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      final groupId = advertisement.adGroupId ?? advertisement.id;
      if (me.role == UserRole.superAdmin) {
        await client.from('notifications').delete().eq('ad_group_id', groupId);
      } else {
        await client
            .from('notifications')
            .delete()
            .eq('ad_group_id', groupId)
            .eq('sent_by', advertisement.sentBy ?? me.id);
      }
      notifications.removeWhere((n) => (n.adGroupId ?? n.id) == groupId);
      success = true;
    });
    notifyListeners();
    return success && errorMessage == null;
  }

  Future<void> markNotificationRead(ServiceNotification item) async {
    if (item.isRead) return;
    if (item.profileId == null) return; // public advertisement, read state is not user-specific
    await client.from('notifications').update({'is_read': true}).eq('id', item.id).eq('profile_id', item.profileId!);
    item.isRead = true;
    notifyListeners();
  }

  Future<void> markChatNotificationsRead() async {
    final me = currentProfile;
    if (me == null) return;
    final unread = notifications
        .where((n) => n.profileId == me.id && !n.isRead && n.notificationType == 'chat')
        .toList();
    if (unread.isEmpty) return;

    for (final item in unread) {
      item.isRead = true;
    }
    notifyListeners();

    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unread.map((n) => n.id).toList())
          .eq('profile_id', me.id);
    } catch (_) {
      // Local badge already cleared; next refresh will sync DB state.
    }
  }

  Future<void> markTicketNotificationsRead() async {
    final me = currentProfile;
    if (me == null) return;
    final unread = notifications
        .where((n) => n.profileId == me.id && !n.isRead && n.ticketId != null)
        .toList();
    if (unread.isEmpty) return;

    for (final item in unread) {
      item.isRead = true;
    }
    notifyListeners();

    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unread.map((n) => n.id).toList())
          .eq('profile_id', me.id);
    } catch (_) {
      // Local badge already cleared; next refresh will sync DB state.
    }
  }


  Future<void> markAdvertisementNotificationsRead() async {
    final me = currentProfile;
    if (me == null) return;
    final unread = notifications
        .where((n) => n.profileId == me.id && !n.isRead && n.notificationType == 'advertisement')
        .toList();
    if (unread.isEmpty) return;

    for (final item in unread) {
      item.isRead = true;
    }
    notifyListeners();

    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unread.map((n) => n.id).toList())
          .eq('profile_id', me.id);
    } catch (_) {
      // Local badge already cleared; next refresh will sync DB state.
    }
  }



  /// Only a manual Super Admin block locks the company's staff out.
  /// Residents and the Super Admin are deliberately excluded.
  bool get isBillingBlocked {
    final profile = currentProfile;
    if (profile == null ||
        (profile.role != UserRole.director &&
         profile.role != UserRole.admin &&
         profile.role != UserRole.worker)) {
      return false;
    }
    return subscriptionForCompany(profile.companyId)?.status == SubscriptionStatus.blocked;
  }

  /// Only the newest server-confirmed subscription can clear an existing block.
  /// Network errors never silently unlock a blocked organization.
  void _syncOwnBillingRow(Map<String, dynamic> row) {
    final me = currentProfile;
    if (me == null || me.role == UserRole.superAdmin ||
        row['company_id'] != me.companyId) {
      return;
    }
    final sub = CompanySubscription.fromMap(row);
    final old = subscriptionForCompany(me.companyId);
    if (old != null &&
        sub.updatedAt.isBefore(old.updatedAt)) {
      return;
    }
    if (old != null && old.status == sub.status &&
        old.updatedAt.isAtSameMomentAs(sub.updatedAt)) {
      return;
    }
    subscriptions.removeWhere((item) => item.companyId == sub.companyId);
    subscriptions.add(sub);
    notifyListeners();
  }

  /// Lightweight fallback when Realtime is unavailable or the app resumes.
  Future<void> refreshBillingStatus() async {
    final me = currentProfile;
    if (_billingRefreshInProgress || me == null ||
        me.role == UserRole.superAdmin || me.companyId == null) {
      return;
    }
    _billingRefreshInProgress = true;
    try {
      final row = await client.from('subscriptions')
          .select().eq('company_id', me.companyId!).maybeSingle();
      if (currentProfile?.id != me.id) return;
      // Missing rows and temporary permission errors must not clear a block.
      if (row != null) _syncOwnBillingRow(Map<String, dynamic>.from(row));
    } catch (_) {
      // Retain the last confirmed status if the server is unreachable.
    } finally {
      _billingRefreshInProgress = false;
    }
  }

  /// Atomic, audited server-side block/unblock. Only Super Admin can call it.
  Future<bool> setCompanyBillingBlocked({
    required String companyId,
    required bool blocked,
  }) async {
    if (currentProfile?.role != UserRole.superAdmin) {
      errorMessage = tr('only_super_admin');
      notifyListeners();
      return false;
    }
    var ok = false;
    await _run(() async {
      await client.rpc('set_company_billing_block', params: {
        'p_company_id': companyId,
        'p_blocked': blocked,
      });
      await refreshBilling(notify: false);
      ok = true;
    });
    return ok && errorMessage == null;
  }

  CompanySubscription? subscriptionForCompany(String? companyId) {
    if (companyId == null || companyId.isEmpty) return null;
    for (final item in subscriptions) {
      if (item.companyId == companyId) return item;
    }
    return null;
  }

  List<CompanyPayment> paymentsForCompany(String companyId) => payments
      .where((item) => item.companyId == companyId)
      .toList()
    ..sort((a, b) => (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt));

  int get totalPaidAmount => payments
      .where((item) => item.status == 'paid')
      .fold<int>(0, (sum, item) => sum + item.amount);

  int get activeSubscriptionCount => subscriptions.where((item) => item.isUsable).length;
  int get expiredSubscriptionCount => subscriptions.where((item) => !item.isUsable).length;

  int get globalMonthlyPrice {
    final raw = appSettings['global_monthly_price'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 499000;
    return 499000;
  }

  Future<void> refreshBilling({bool notify = true}) async {
    final me = currentProfile;
    if (me == null) return;
    try {
      try {
        final settingsRows = await client.from('app_settings').select('key,value');
        appSettings
          ..clear()
          ..addEntries(
            (settingsRows as List).map(
              (row) {
                final map = Map<String, dynamic>.from(row as Map);
                return MapEntry('${map['key']}', map['value']);
              },
            ),
          );
      } catch (_) {
        appSettings.putIfAbsent('global_monthly_price', () => 499000);
      }

      final subscriptionRows = me.role == UserRole.superAdmin
          ? await client.from('subscriptions').select().order('updated_at', ascending: false)
          : await client.from('subscriptions').select().eq('company_id', me.companyId ?? '').order('updated_at', ascending: false);
      final fetchedSubscriptions = (subscriptionRows as List)
          .map((e) => CompanySubscription.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      // A slower billing request must not overwrite a newer realtime block.
      if (me.role != UserRole.superAdmin) {
        for (var i = 0; i < fetchedSubscriptions.length; i++) {
          final old = subscriptionForCompany(fetchedSubscriptions[i].companyId);
          if (old != null && old.updatedAt.isAfter(fetchedSubscriptions[i].updatedAt)) {
            fetchedSubscriptions[i] = old;
          }
        }
        // Preserve a previously confirmed block if an intermittent read
        // returns no row. Only a newer server row can release the lock.
        if (fetchedSubscriptions.isEmpty) {
          final blocked = subscriptionForCompany(me.companyId);
          if (blocked?.status == SubscriptionStatus.blocked) {
            fetchedSubscriptions.add(blocked!);
          }
        }
      }
      subscriptions
        ..clear()
        ..addAll(fetchedSubscriptions);

      final paymentRows = me.role == UserRole.superAdmin
          ? await client.from('payments').select().order('created_at', ascending: false).limit(300)
          : await client.from('payments').select().eq('company_id', me.companyId ?? '').order('created_at', ascending: false).limit(100);
      payments
        ..clear()
        ..addAll((paymentRows as List).map((e) => CompanyPayment.fromMap(Map<String, dynamic>.from(e))));
      if (notify) notifyListeners();
    } catch (e) {
      errorMessage = _prettyError(e);
      if (notify) notifyListeners();
    }
  }

  Future<void> _ensureTrialSubscription(String companyId) async {
    try {
      await client.rpc('ensure_company_subscription', params: {'p_company_id': companyId});
    } catch (_) {
      // SQL yangilanmagan bo'lsa ham registratsiya buzilmasin.
    }
  }

  Future<void> ensureAllCompanySubscriptions() async {
    await _run(() async {
      for (final company in companies) {
        await _ensureTrialSubscription(company.id);
      }
      await refreshBilling(notify: false);
    });
  }

  Future<bool> saveGlobalMonthlyPrice(
    int price, {
    bool applyToAllCompanies = false,
  }) async {
    if (currentProfile?.role != UserRole.superAdmin) {
      errorMessage = tr('only_super_admin');
      notifyListeners();
      return false;
    }
    if (price <= 0) {
      errorMessage = tr('amount_required');
      notifyListeners();
      return false;
    }

    var ok = false;
    await _run(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      await client.from('app_settings').upsert({
        'key': 'global_monthly_price',
        'value': price,
        'updated_at': now,
      }, onConflict: 'key');

      appSettings['global_monthly_price'] = price;

      if (applyToAllCompanies) {
        await client
            .from('subscriptions')
            .update({
              'monthly_price': price,
              'updated_at': now,
            })
            .not('company_id', 'is', null);
        await refreshBilling(notify: false);
      }

      ok = true;
    });
    return ok && errorMessage == null;
  }

  Future<bool> saveSubscription({
    required String companyId,
    required int monthlyPrice,
    required int discountPercent,
    required int discountAmount,
    required SubscriptionStatus status,
    int? trialDays,
    int? activeDays,
    String? note,
  }) async {
    var ok = false;
    await _run(() async {
      final now = DateTime.now().toUtc();
      DateTime? trialEndsAt;
      DateTime? currentPeriodStart;
      DateTime? currentPeriodEnd;
      if (trialDays != null && trialDays > 0) {
        trialEndsAt = now.add(Duration(days: trialDays));
      }
      if (activeDays != null && activeDays > 0) {
        currentPeriodStart = now;
        currentPeriodEnd = now.add(Duration(days: activeDays));
      }
      final data = await client
          .from('subscriptions')
          .upsert({
            'company_id': companyId,
            'status': status.dbValue,
            'plan_name': 'monthly',
            'monthly_price': monthlyPrice,
            'discount_percent': discountPercent.clamp(0, 100),
            'discount_amount': discountAmount < 0 ? 0 : discountAmount,
            if (trialEndsAt != null) 'trial_ends_at': trialEndsAt.toIso8601String(),
            if (currentPeriodStart != null) 'current_period_start': currentPeriodStart.toIso8601String(),
            if (currentPeriodEnd != null) 'current_period_end': currentPeriodEnd.toIso8601String(),
            'note': note?.trim(),
            'updated_at': now.toIso8601String(),
          }, onConflict: 'company_id')
          .select()
          .single();
      final sub = CompanySubscription.fromMap(Map<String, dynamic>.from(data as Map));
      final index = subscriptions.indexWhere((item) => item.companyId == sub.companyId);
      if (index == -1) {
        subscriptions.add(sub);
      } else {
        subscriptions[index] = sub;
      }
      ok = true;
    });
    return ok && errorMessage == null;
  }

  Future<bool> addManualPayment({
    required String companyId,
    required int amount,
    required int periodDays,
    String provider = 'manual',
    String? note,
  }) async {
    if (amount <= 0) {
      errorMessage = tr('amount_required');
      notifyListeners();
      return false;
    }
    var ok = false;
    await _run(() async {
      final now = DateTime.now().toUtc();
      await client.from('payments').insert({
        'company_id': companyId,
        'provider': provider,
        'amount': amount,
        'currency': 'UZS',
        'status': 'paid',
        'period_days': periodDays <= 0 ? 30 : periodDays,
        'paid_at': now.toIso8601String(),
        'note': note?.trim(),
      });
      final current = subscriptionForCompany(companyId);
      final currentEnd = current?.currentPeriodEnd?.toUtc();
      final base = currentEnd != null && currentEnd.isAfter(now) ? currentEnd : now;
      final newEnd = base.add(Duration(days: periodDays <= 0 ? 30 : periodDays));
      await client
          .from('subscriptions')
          .upsert({
            'company_id': companyId,
            'status': current?.status == SubscriptionStatus.blocked
                ? SubscriptionStatus.blocked.dbValue
                : SubscriptionStatus.active.dbValue,
            'plan_name': 'monthly',
            'monthly_price': current?.monthlyPrice ?? globalMonthlyPrice,
            'discount_percent': current?.discountPercent ?? 0,
            'discount_amount': current?.discountAmount ?? 0,
            'current_period_start': now.toIso8601String(),
            'current_period_end': newEnd.toIso8601String(),
            'note': note?.trim(),
            'updated_at': now.toIso8601String(),
          }, onConflict: 'company_id');
      await refreshBilling(notify: false);
      ok = true;
    });
    return ok && errorMessage == null;
  }

  Future<void> refreshChatRooms({bool notify = true}) async {
    final me = currentProfile;
    if (me == null) return;
    try {
      final rows = me.role == UserRole.superAdmin
          ? await client.from('chat_rooms').select().order('last_message_at', ascending: false)
          : await client.from('chat_rooms').select().eq('company_id', me.companyId ?? '').order('last_message_at', ascending: false);
      if (currentProfile?.id != me.id) return;
      chatRooms
        ..clear()
        ..addAll((rows as List).map((e) => ChatRoom.fromMap(Map<String, dynamic>.from(e))));
      _sortChatRoomsNewestFirst();
      if (notify) notifyListeners();
    } catch (_) {
      if (notify) notifyListeners();
    }
  }

  void _sortChatRoomsNewestFirst() {
    chatRooms.sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
  }

  Future<ChatRoom?> ensureGroupChat() async {
    final me = currentProfile;
    if (me == null) return null;
    ChatRoom? room;
    await _run(() async {
      final data = await client.rpc('chat_ensure_group_room').single();
      room = ChatRoom.fromMap(Map<String, dynamic>.from(data as Map));
      _upsertChatRoom(room!);
    });
    return room;
  }

  Future<ChatRoom?> getOrCreateDirectChat(Profile other) async {
    final me = currentProfile;
    if (me == null || other.id == me.id) return null;
    ChatRoom? room;
    await _run(() async {
      final data = await client.rpc('chat_get_or_create_direct_room', params: {'p_other_profile_id': other.id}).single();
      room = ChatRoom.fromMap(Map<String, dynamic>.from(data as Map));
      _upsertChatRoom(room!);
    });
    return room;
  }

  void _upsertChatRoom(ChatRoom room) {
    final index = chatRooms.indexWhere((item) => item.id == room.id);
    if (index == -1) {
      chatRooms.add(room);
    } else {
      chatRooms[index] = room;
    }
    _sortChatRoomsNewestFirst();
    notifyListeners();
  }

  Future<void> watchChatRoom(ChatRoom room) async {
    final generation=++_chatWatchGeneration;
    final previous=_chatMessagesSub;
    _chatMessagesSub=null;
    activeChatRoomId=room.id;
    final cacheKey='${currentProfile?.id}:${room.id}';
    final cached=_recentChatMessages.remove(cacheKey);
    activeChatMessages
      ..clear()
      ..addAll(cached ?? <ChatMessage>[]);
    chatRevision++;notifyListeners();
    await previous?.cancel();
    if(generation!=_chatWatchGeneration) return;
    // Fetch only the newest page first. The realtime stream below hydrates
    // the entire history afterward without holding up the chat screen.
    await _loadRecentChatMessages(room.id);
    if(generation!=_chatWatchGeneration) return;
    _chatMessagesSub=client.from('chat_messages').stream(primaryKey:['id'])
      .eq('room_id',room.id).order('created_at').listen((rows) {
        if(generation!=_chatWatchGeneration || activeChatRoomId!=room.id) return;
        final incoming=rows.map((e)=>ChatMessage.fromMap(Map<String,dynamic>.from(e))).toList();
        _knownMessageIds..clear()..addAll(incoming.map((m)=>m.id));
        activeChatMessages..clear()..addAll(incoming);
        _rememberChatMessages(room.id);
        chatRevision++;notifyListeners();
      },onError:(_) {
        if(generation==_chatWatchGeneration) {
          unawaited(refreshChatMessages(room.id).catchError((_) {}));
        }
      });
    unawaited(_finishChatRoomWatch(room.id,generation));
  }

  Future<void> _finishChatRoomWatch(String roomId,int generation) async {
    try {
      await _startTypingWatch(roomId,generation);
      if(generation!=_chatWatchGeneration) return;
      await refreshChatReads(roomId,notify:false);
      if(generation!=_chatWatchGeneration) return;
      await markChatRoomAsRead(roomId);
      if(generation!=_chatWatchGeneration) return;
      await markChatNotificationsRead();
      if(generation==_chatWatchGeneration) notifyListeners();
    } catch (_) { /* Nonessential room metadata must not block chat. */ }
  }

  void _rememberChatMessages(String roomId) {
    final key='${currentProfile?.id}:$roomId';
    _recentChatMessages.remove(key);
    _recentChatMessages[key]=activeChatMessages.length>120
        ? activeChatMessages.sublist(activeChatMessages.length-120)
        : List<ChatMessage>.of(activeChatMessages);
    if(_recentChatMessages.length>5) _recentChatMessages.remove(_recentChatMessages.keys.first);
  }

  Future<void> _loadRecentChatMessages(String roomId) async {
    final rows=await client.from('chat_messages').select().eq('room_id',roomId)
        .order('created_at',ascending:false).limit(80);
    if(activeChatRoomId!=roomId) return;
    final recent=(rows as List)
        .map((row)=>ChatMessage.fromMap(Map<String,dynamic>.from(row))).toList()
      ..sort((a,b) {
        final byDate=a.createdAt.compareTo(b.createdAt);
        return byDate!=0?byDate:a.id.compareTo(b.id);
      });
    activeChatMessages..clear()..addAll(recent);
    _knownMessageIds..clear()..addAll(recent.map((message)=>message.id));
    _rememberChatMessages(roomId);
    chatRevision++;notifyListeners();
  }

  Future<void> stopWatchingChatRoom(String roomId) async {
    if(activeChatRoomId!=roomId) return;
    _rememberChatMessages(roomId);
    _chatWatchGeneration++;
    final messages=_chatMessagesSub,typing=_typingSub,reads=_chatReadsSub;
    _chatMessagesSub=null;_typingSub=null;_chatReadsSub=null;
    _readRefreshTimer?.cancel();
    activeChatRoomId=null;activeChatMessages.clear();chatRevision++;
    typingProfiles.clear();_messageReadBy.clear();
    await setChatTyping(roomId,false);
    await messages?.cancel();await typing?.cancel();await reads?.cancel();
  }

  Future<void> refreshChatMessages(String roomId, {bool notify = true}) async {
    final rows = await client.from('chat_messages').select().eq('room_id', roomId).order('created_at');
    if (activeChatRoomId == roomId) {
      activeChatRoomId = roomId;
      chatRevision++;
      activeChatMessages
        ..clear()
        ..addAll((rows as List).map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e))));
      _rememberChatMessages(roomId);
      _knownMessageIds
        ..clear()
        ..addAll(activeChatMessages.map((m) => m.id));
      if (notify) notifyListeners();
    }
  }

  Future<bool> sendChatMessage({required String roomId, required String text, required List<PickedAttachment> attachments, String? replyToMessageId}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty && attachments.isEmpty) {
      errorMessage = 'Xabar yoki fayl kiriting.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      final urls = attachments.isEmpty ? <String>[] : await _uploadChatAttachments(roomId: roomId, files: attachments);
      final data = await client.rpc('chat_send_message', params: {
        'p_room_id': roomId,
        'p_text': cleanText,
        'p_attachments': urls,
        'p_reply_to_message_id': replyToMessageId,
      }).single();
      final sent = ChatMessage.fromMap(Map<String, dynamic>.from(data as Map));
      _upsertChatMessage(sent);
      // Notifications are queued by the database message trigger.
      await refreshChatRooms();
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<void> editChatMessage({required ChatMessage message, required String newText}) async {
    final clean = newText.trim();
    if (clean.isEmpty) throw Exception('Xabar bo‘sh bo‘lmasin.');
    await _run(() async {
      final data = await client.rpc('chat_edit_message', params: {'p_message_id': message.id, 'p_text': clean}).single();
      _upsertChatMessage(ChatMessage.fromMap(Map<String, dynamic>.from(data as Map)));
      await refreshChatRooms();
    });
  }

  Future<void> deleteChatMessage(ChatMessage message) async {
    await _run(() async {
      final data = await client.rpc('chat_delete_message', params: {'p_message_id': message.id}).single();
      _upsertChatMessage(ChatMessage.fromMap(Map<String, dynamic>.from(data as Map)));
      await refreshChatRooms();
    });
  }

  void _upsertChatMessage(ChatMessage message) {
    final index = activeChatMessages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      activeChatMessages.add(message);
    } else {
      activeChatMessages[index] = message;
    }
    activeChatMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    chatRevision++;
    notifyListeners();
  }

  // Compatibility fallback; notifications are currently created by DB triggers.
  // ignore: unused_element
  Future<void> _notifyChatRecipients({required String roomId, required ChatMessage message}) async {
    final me = currentProfile;
    if (me == null) return;
    try {
      ChatRoom? room;
      for (final candidate in chatRooms) {
        if (candidate.id == roomId) {
          room = candidate;
          break;
        }
      }
      final ids = <String>{};
      if (room?.type == ChatRoomType.group) {
        ids.addAll(profiles.where((p) => p.companyId == me.companyId && p.id != me.id).map((p) => p.id));
      } else {
        final members = await client.from('chat_room_members').select('profile_id').eq('room_id', roomId);
        ids.addAll((members as List).map((e) => '${e['profile_id']}').where((id) => id != me.id));
      }
      if (ids.isEmpty) return;
      final body = message.text.trim().isEmpty ? 'Fayl yuborildi' : message.text.trim();
      final rows = ids.map((id) => {
            'profile_id': id,
            'title': '${me.fullName} yozdi',
            'body': body,
            'notification_type': 'chat',
            'sent_by': me.id,
            'company_id': me.companyId,
            'chat_room_id': roomId,
            'chat_message_id': message.id,
          }).toList();
      try {
        await client.from('notifications').insert(rows);
      } catch (_) {
        // Older databases may not have chat_room_id/chat_message_id yet.
        final fallbackRows = rows.map((row) {
          final copy = Map<String, dynamic>.from(row);
          copy.remove('chat_room_id');
          copy.remove('chat_message_id');
          return copy;
        }).toList();
        await client.from('notifications').insert(fallbackRows);
      }
      await _sendPushToProfiles(
        profileIds: ids,
        title: '${me.fullName} yozdi',
        body: body,
        type: 'chat_message',
        chatRoomId: roomId,
        chatMessageId: message.id,
      );
    } catch (_) {
      // Chat xabar yuborilishi notification xatosi sabab to‘xtamasin.
    }
  }

  Future<void> _startTypingWatch(String roomId,int generation) async {
    await _typingSub?.cancel();
    await _chatReadsSub?.cancel();
    if(generation!=_chatWatchGeneration) return;
    await refreshTyping(roomId, notify: false);
    if(generation!=_chatWatchGeneration) return;
    _typingSub = client
        .from('chat_typing')
        .stream(primaryKey: ['room_id', 'profile_id'])
        .eq('room_id', roomId)
        .listen((rows) {
      if(generation==_chatWatchGeneration) _applyTypingRows(rows, notify: true);
    }, onError: (_) async => refreshTyping(roomId));

    _chatReadsSub = client
        .from('chat_message_reads')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .listen((_) {
          _readRefreshTimer?.cancel();
          _readRefreshTimer=Timer(const Duration(milliseconds:250),()=>refreshChatReads(roomId));
        }, onError: (_) async => refreshChatReads(roomId));
  }

  Future<void> refreshTyping(String roomId, {bool notify = true}) async {
    try {
      final rows = await client.from('chat_typing').select().eq('room_id', roomId);
      if(activeChatRoomId==roomId) _applyTypingRows(rows as List, notify: notify);
    } catch (_) {}
  }

  void _applyTypingRows(List rows, {required bool notify}) {
    final me = currentProfile;
    if (me == null) return;
    final now = DateTime.now();
    final ids = rows
        .where((e) => e['profile_id'] != me.id)
        .where((e) => e['is_typing'] == true)
        .where((e) {
          final updated = DateTime.tryParse('${e['updated_at']}') ?? now;
          return now.difference(updated).inSeconds < 4;
        })
        .map((e) => '${e['profile_id']}')
        .toSet();
    typingProfiles
      ..clear()
      ..addAll(profiles.where((p) => ids.contains(p.id)));
    if (notify) notifyListeners();
  }


  Future<void> refreshChatReads(String roomId, {bool notify = true}) async {
    try {
      final rows = await client.from('chat_message_reads').select('message_id, profile_id').eq('room_id', roomId);
      if(activeChatRoomId!=roomId) return;
      _messageReadBy.clear();
      for (final row in rows as List) {
        final messageId = row['message_id']?.toString();
        final profileId = row['profile_id']?.toString();
        if (messageId == null || profileId == null) continue;
        _messageReadBy.putIfAbsent(messageId, () => <String>{}).add(profileId);
      }
      if (notify) notifyListeners();
    } catch (_) {}
  }

  Future<void> markChatRoomAsRead(String roomId) async {
    final me = currentProfile;
    if (me == null || _markingChatRead || activeChatRoomId != roomId) return;
    final unread = activeChatMessages.where((m) => m.roomId == roomId &&
      m.senderId != me.id && !m.isDeleted && !(_messageReadBy[m.id]?.contains(me.id) ?? false)).toList();
    final alerts=notifications.where((n)=>n.profileId==me.id && n.chatRoomId==roomId && !n.isRead).toList();
    if (unread.isEmpty && alerts.isEmpty) return;
    _markingChatRead = true;
    try {
      for (var start = 0; start < unread.length; start += 100) {
        final chunk = unread.skip(start).take(100).toList();
        await client.from('chat_message_reads').upsert(chunk.map((m) => {
          'message_id': m.id, 'room_id': roomId, 'profile_id': me.id,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        }).toList(), onConflict: 'message_id,profile_id');
        if (activeChatRoomId != roomId || currentProfile?.id != me.id) return;
        for (final m in chunk) { _messageReadBy.putIfAbsent(m.id, () => <String>{}).add(me.id); }
      }
      if(alerts.isNotEmpty){
        await client.from('notifications').update({'is_read':true}).eq('profile_id',me.id).inFilter('id',alerts.map((n)=>n.id).toList());
        for(final item in alerts){item.isRead=true;}
      }
      notifyListeners();
    } catch (_) { /* The next room event can retry the unacknowledged rows. */ }
    finally { _markingChatRead = false; }
  }

  Future<void> setChatTyping(String roomId, bool isTyping) async {
    final me = currentProfile;
    if (me == null) return;
    try {
      await client.from('chat_typing').upsert({
        'room_id': roomId,
        'profile_id': me.id,
        'company_id': me.companyId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_id,profile_id');
    } catch (_) {}
  }


  Future<bool> updateGroupChatRoom({
    required ChatRoom room,
    required String title,
    PickedAttachment? avatar,
  }) async {
    final me = currentProfile;
    if (me == null) return false;
    if (me.role != UserRole.director && me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat direktor, admin yoki super admin chat profilini tahrirlay oladi.';
      notifyListeners();
      return false;
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      errorMessage = 'Chat nomi majburiy.';
      notifyListeners();
      return false;
    }

    var success = false;
    await _run(() async {
      String? avatarUrl = room.avatarUrl;
      if (avatar != null && avatar.bytes.isNotEmpty) {
        if (avatar.sizeInMb > 8) throw Exception('Chat rasmi maksimal 8 MB bo‘lsin.');
        final rawExt = avatar.name.contains('.') ? avatar.name.split('.').last : 'jpg';
        final safeExt = rawExt.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
        final ext = safeExt.isEmpty ? 'jpg' : safeExt;
        final path = 'chat_rooms/${room.id}/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}.$ext';
        await client.storage.from('ticket-files').uploadBinary(
              path,
              avatar.bytes,
              fileOptions: FileOptions(contentType: _contentType(ext, false), upsert: false),
            );
        avatarUrl = client.storage.from('ticket-files').getPublicUrl(path);
      }

      final data = await client
          .from('chat_rooms')
          .update({
            'title': cleanTitle,
            'avatar_url': avatarUrl,
          })
          .eq('id', room.id)
          .select()
          .single();

      _upsertChatRoom(ChatRoom.fromMap(Map<String, dynamic>.from(data as Map)));
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<void> pinChatMessage({required ChatRoom room, required ChatMessage message}) async {
    final me = currentProfile;
    if (me == null) return;
    if (me.role != UserRole.director && me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat direktor, admin yoki super admin xabarni qadab qo‘ya oladi.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final data = await client
          .from('chat_rooms')
          .update({'pinned_message_id': message.id})
          .eq('id', room.id)
          .select()
          .single();
      _upsertChatRoom(ChatRoom.fromMap(Map<String, dynamic>.from(data as Map)));
    });
  }

  Future<void> unpinChatMessage(ChatRoom room) async {
    final me = currentProfile;
    if (me == null) return;
    if (me.role != UserRole.director && me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat direktor, admin yoki super admin qadangan xabarni olib tashlay oladi.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final data = await client
          .from('chat_rooms')
          .update({'pinned_message_id': null})
          .eq('id', room.id)
          .select()
          .single();
      _upsertChatRoom(ChatRoom.fromMap(Map<String, dynamic>.from(data as Map)));
    });
  }

  Future<List<String>> _uploadChatAttachments({required String roomId, required List<PickedAttachment> files}) async {
    if(files.length>6 || files.fold<double>(0,(sum,f)=>sum+f.sizeInMb)>120 ||
      files.any((f)=>f.sizeInMb<=0 || f.sizeInMb>(f.isVideo?60:8))) {
      throw StateError('media_limit');
    }
    final urls = <String>[];
    for (final file in files) {
      if (file.bytes.isEmpty) continue;
      if (!file.isVideo && file.sizeInMb > 8) throw Exception('${file.name} juda katta. Rasm maksimal 8 MB bo‘lsin.');
      if (file.isVideo && file.sizeInMb > 60) throw Exception('${file.name} juda katta. Video maksimal 60 MB bo‘lsin.');
      final rawExt = file.name.contains('.') ? file.name.split('.').last : (file.isVideo ? 'mp4' : 'jpg');
      final safeExt = rawExt.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
      final ext = safeExt.isEmpty ? (file.isVideo ? 'mp4' : 'jpg') : safeExt;
      final path = 'chat/$roomId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}.$ext';
      await _uploadPickedFile(path,file,ext);
      urls.add(client.storage.from('ticket-files').getPublicUrl(path));
    }
    return urls;
  }

  // Legacy provisioning helper; leave customer buildings untouched.
  // ignore: unused_element
  Future<void> _ensureDefaultBuildings(String companyId) async {
    final existing = await client.from('buildings').select('id').eq('company_id', companyId).limit(1);
    if ((existing as List).isNotEmpty) return;
    await client.from('buildings').insert([
      {'company_id': companyId, 'name': 'A. Navoiy 22', 'street': 'A. Navoiy', 'house_number': '22', 'latitude': 40.8442, 'longitude': 69.5981},
      {'company_id': companyId, 'name': 'A. Navoiy 30', 'street': 'A. Navoiy', 'house_number': '30', 'latitude': 40.8451, 'longitude': 69.5993},
      {'company_id': companyId, 'name': 'I. Yo‘li 44', 'street': 'I. Yo‘li', 'house_number': '44', 'latitude': 40.8463, 'longitude': 69.6007},
      {'company_id': companyId, 'name': 'Navqiron 45', 'street': 'Navqiron', 'house_number': '45', 'latitude': 40.8472, 'longitude': 69.6012},
    ]);
  }

  Future<void> updateProfileSettings({required AppLanguage language, required ThemeMode themeMode}) async {
    final me = currentProfile;
    if (me == null) return;
    await _run(() async {
      await client.from('profiles').update({'language': language.dbValue, 'theme_mode': themeMode.dbValue}).eq('id', me.id);
      currentProfile!.language = language;
      authLanguage = language;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_language', language.dbValue);
      currentProfile!.themeMode = themeMode;
    });
  }


  Future<void> updateProfile(Profile profile) async {
    await _run(() async {
      await client.from('profiles').update({
        'first_name': profile.firstName.trim(),
        'last_name': profile.lastName.trim(),
        'phone': profile.phone.trim(),
        'avatar_url': profile.avatarUrl,
        'language': profile.language.dbValue,
        'theme_mode': profile.themeMode.dbValue,
      }).eq('id', profile.id);
      if (currentProfile?.id == profile.id) currentProfile = profile;
    });
  }




  Future<bool> createCompanyBySuperAdmin({
    required String name,
    required String joinPassword,
  }) async {
    final me = currentProfile;
    if (me == null || me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat Super Admin tashkilot yaratishi mumkin.';
      notifyListeners();
      return false;
    }
    final cleanName = name.trim();
    final cleanPassword = joinPassword.trim();
    if (cleanName.isEmpty || cleanPassword.isEmpty) {
      errorMessage = 'Tashkilot nomi va kirish kodi majburiy.';
      notifyListeners();
      return false;
    }

    var success = false;
    await _run(() async {
      final row = await client
          .from('companies')
          .insert({
            'name': cleanName,
            'join_password': cleanPassword,
            'director_id': me.id,
          })
          .select()
          .maybeSingle();

      if (row != null) {
        final company = Company.fromMap(Map<String, dynamic>.from(row));
        companies.insert(0, company);

      }
      await _refreshStaticData();
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<bool> cleanupSelectedActivityDataForSuperAdmin({
    required bool tickets,
    required bool advertisements,
    required bool chatMessages,
    required bool notificationsOnly,
  }) async {
    final me = currentProfile;
    if (me == null || me.role != UserRole.superAdmin) {
      errorMessage = 'Faqat Super Admin database tozalashi mumkin.';
      notifyListeners();
      return false;
    }
    if (!tickets && !advertisements && !chatMessages && !notificationsOnly) {
      errorMessage = 'O‘chiriladigan ma’lumot turini tanlang.';
      notifyListeners();
      return false;
    }

    var success = false;
    await _run(() async {
      if (chatMessages) {
        await client
            .from('chat_rooms')
            .update({
              'last_message': null,
              'last_message_at': DateTime.now().toIso8601String(),
              'pinned_message_id': null,
            })
            .not('id', 'is', null);
        await client.from('chat_message_reads').delete().not('id', 'is', null);
        await client.from('chat_typing').delete().not('room_id', 'is', null);
        await client.from('chat_messages').delete().not('id', 'is', null);
        await client.from('notifications').delete().eq('notification_type', 'chat');
      }

      if (advertisements) {
        await client.from('notifications').delete().eq('notification_type', 'advertisement');
      }

      if (tickets) {
        await client
            .from('notifications')
            .delete()
            .inFilter('notification_type', ['ticket_created', 'ticket_accepted', 'ticket_completed', 'ticket_closed', 'ticket']);
        await client.from('tickets').delete().not('id', 'is', null);
      }

      if (notificationsOnly) {
        await client.from('notifications').delete().not('id', 'is', null);
      }

      if (tickets) this.tickets.clear();
      if (notificationsOnly) {
        notifications.clear();
      } else if (advertisements) {
        notifications.removeWhere((n) => n.notificationType == 'advertisement');
      }
      if (chatMessages) {
        activeChatMessages.clear();
    chatRevision++;
        _messageReadBy.clear();
        typingProfiles.clear();
        for (var i = 0; i < chatRooms.length; i++) {
          final old = chatRooms[i];
          chatRooms[i] = ChatRoom(
            id: old.id,
            companyId: old.companyId,
            type: old.type,
            title: old.title,
            createdAt: old.createdAt,
            createdBy: old.createdBy,
            lastMessage: null,
            lastMessageAt: old.lastMessageAt,
            avatarUrl: old.avatarUrl,
            pinnedMessageId: null,
          );
        }
      }
      await _refreshStaticData();
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<bool> updateCompany(Company company, {required String name, required String joinPassword}) async {
    final cleanName = name.trim();
    final cleanPassword = joinPassword.trim();
    if (cleanName.isEmpty || cleanPassword.isEmpty) {
      errorMessage = 'Kompaniya nomi va kodi majburiy.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      final updated = await client
          .from('companies')
          .update({'name': cleanName, 'join_password': cleanPassword})
          .eq('id', company.id)
          .select()
          .single();
      final idx = companies.indexWhere((item) => item.id == company.id);
      if (idx != -1) companies[idx] = Company.fromMap(Map<String, dynamic>.from(updated));
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<bool> updateProfileAdmin(Profile profile, {
    required UserRole role,
    required String firstName,
    required String lastName,
    required String phone,
    required String jobTitle,
  }) async {
    var success = false;
    await _run(() async {
      if (currentProfile?.role != UserRole.superAdmin || profile.role == UserRole.superAdmin) {
        throw StateError('Faqat super admin foydalanuvchi rolini o‘zgartira oladi.');
      }
      final updated = await client.from('profiles').update({
        'role': role.dbValue,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone': phone.trim(),
        'job_title': jobTitle.trim(),
      }).eq('id', profile.id).select('id').maybeSingle();
      if (updated == null) throw StateError('Profilni saqlashga ruxsat berilmadi.');
      await _refreshStaticData();
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<void> deleteCompany(Company company) async {
    await _run(() async {
      if (currentProfile?.role == UserRole.superAdmin) {
        await client.rpc('super_delete_company', params: {'p_company_id': company.id});
      } else {
        await client.from('companies').delete().eq('id', company.id);
      }
      companies.removeWhere((item) => item.id == company.id);
      profiles.removeWhere((item) => item.companyId == company.id);
      buildings.removeWhere((item) => item.companyId == company.id);
      tickets.removeWhere((item) => item.companyId == company.id);
      notifications.removeWhere((item) => item.companyId == company.id);
      chatRooms.removeWhere((item) => item.companyId == company.id);
      await _refreshStaticData();
    });
  }

  Future<void> deleteProfile(Profile profile) async {
    await _run(() async {
      if (currentProfile?.role == UserRole.superAdmin) {
        await client.rpc('super_delete_profile', params: {'p_profile_id': profile.id});
      } else {
        await client.from('profiles').delete().eq('id', profile.id);
      }
      profiles.removeWhere((item) => item.id == profile.id);
      notifications.removeWhere((item) => item.profileId == profile.id || item.sentBy == profile.id);
      activeChatMessages.removeWhere((item) => item.senderId == profile.id);
      chatRevision++;
      await _refreshStaticData();
    });
  }

  Future<void> deleteChatRoomHard(ChatRoom room) async {
    await _run(() async {
      if (currentProfile?.role == UserRole.superAdmin) {
        await client.rpc('super_delete_chat_room', params: {'p_room_id': room.id});
      } else {
        await client.rpc('delete_my_direct_chat_room', params: {'p_room_id': room.id});
      }
      chatRooms.removeWhere((item) => item.id == room.id);
      if (activeChatRoomId == room.id) {
        activeChatRoomId = null;
        activeChatMessages.clear();
    chatRevision++;
      }
      notifications.removeWhere((item) => item.chatRoomId == room.id);
      await refreshChatRooms(notify: false);
      await refreshNotifications(notify: false);
    });
  }

  Future<void> cleanupActivityDataForSuperAdmin() async {
    await _run(() async {
      if (currentProfile?.role != UserRole.superAdmin) {
        throw Exception('Faqat Super Admin database tozalashi mumkin.');
      }

      // PostgREST update/delete operations must always have a filter.
      // For this reason the cleanup is performed with explicit safe filters
      // instead of a filterless update/delete from Flutter. This prevents:
      // “UPDATE requires a WHERE clause”.
      await _superCleanupActivityDataSafely();

      tickets.clear();
      notifications.clear();
      chatRooms.clear();
      activeChatMessages.clear();
    chatRevision++;
      activeChatRoomId = null;
      _messageReadBy.clear();
      typingProfiles.clear();
      await _refreshStaticData();
    });
  }

  Future<void> _superCleanupActivityDataSafely() async {
    // Clear references before deleting the messages they may point to.
    await client
        .from('chat_rooms')
        .update({
          'last_message': null,
          'last_message_at': DateTime.now().toIso8601String(),
          'pinned_message_id': null,
        })
        .not('id', 'is', null);

    await client.from('chat_message_reads').delete().not('id', 'is', null);
    await client.from('chat_typing').delete().not('room_id', 'is', null);
    await client.from('notifications').delete().not('id', 'is', null);
    await client.from('chat_messages').delete().not('id', 'is', null);
    await client.from('chat_room_members').delete().not('id', 'is', null);
    await client.from('chat_rooms').delete().not('id', 'is', null);
    await client.from('tickets').delete().not('id', 'is', null);
  }

  int companyTicketCount(String companyId) => tickets.where((ticket) => ticket.companyId == companyId).length;
  int companyAdvertisementCount(String companyId) => notifications
      .where((notification) => notification.notificationType == 'advertisement' && notification.companyId == companyId)
      .map((notification) => notification.adGroupId ?? notification.id)
      .toSet()
      .length;
  int companyChatRoomCount(String companyId) => chatRooms.where((room) => room.companyId == companyId).length;
  List<ChatRoom> companyGroupRooms(String companyId) => chatRooms
      .where((room) => room.companyId == companyId && room.type == ChatRoomType.group)
      .toList()
    ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));


  Future<bool> uploadProfileAvatar(PickedAttachment file) async {
    final me = currentProfile;
    if (me == null) return false;
    if (file.bytes.isEmpty) {
      errorMessage = 'Rasm tanlanmadi.';
      notifyListeners();
      return false;
    }
    if (file.isVideo) {
      errorMessage = 'Profil rasmi uchun faqat rasm yoki GIF tanlang.';
      notifyListeners();
      return false;
    }
    if (file.sizeInMb > 8) {
      errorMessage = 'Profil rasmi maksimal 8 MB bo‘lsin.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      final ext = _safeExtension(file.name, fallback: 'jpg');
      final path = 'avatars/${me.id}/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}.$ext';
      await client.storage.from('ticket-files').uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(contentType: _contentType(ext, false), upsert: true),
          );
      final url = client.storage.from('ticket-files').getPublicUrl(path);
      await client.from('profiles').update({'avatar_url': url}).eq('id', me.id);
      currentProfile!.avatarUrl = url;
      final idx = profiles.indexWhere((item) => item.id == me.id);
      if (idx != -1) profiles[idx].avatarUrl = url;
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<List<String>> _uploadAdAttachments({required List<PickedAttachment> files}) async {
    final me = currentProfile;
    if (me == null) throw Exception('Profil topilmadi.');
    final urls = <String>[];
    for (final file in files) {
      if (file.bytes.isEmpty && file.localPath == null) {
        throw FormatException('${file.name}: media fayli topilmadi. Qayta tanlang.');
      }
      if (!file.isVideo && file.sizeInMb > 10) throw Exception('${file.name} juda katta. Rasm/GIF maksimal 10 MB bo‘lsin.');
      if (file.isVideo && file.sizeInMb > 80) throw Exception('${file.name} juda katta. Video maksimal 80 MB bo‘lsin.');
      final ext = _safeExtension(file.name, fallback: file.isVideo ? 'mp4' : 'jpg');
      final path = 'ads/${me.id}/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}.$ext';
      await _uploadPickedFile(path, file, ext);
      urls.add(client.storage.from('ticket-files').getPublicUrl(path));
    }
    return urls;
  }

  String _safeExtension(String name, {required String fallback}) {
    final rawExt = name.contains('.') ? name.split('.').last : fallback;
    final safeExt = rawExt.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
    return safeExt.isEmpty ? fallback : safeExt;
  }

  Future<bool> sendAdvertisement({
    required String title,
    required String body,
    String? actionUrl,
    String actionLabel = 'Batafsil',
    required String targetMode,
    String? targetCompanyId,
    String? targetProfileId,
    required List<PickedAttachment> attachments,
  }) async {
    final me = currentProfile;
    if (me == null) return false;
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanBody.isEmpty) {
      errorMessage = 'Reklama sarlavhasi va matni majburiy.';
      notifyListeners();
      return false;
    }
    final cleanUrl = actionUrl?.trim() ?? '';
    if (cleanUrl.isNotEmpty && !_validAdvertisementUrl(cleanUrl)) {
      errorMessage = 'Havola https:// yoki http:// bilan boshlanishi kerak (maksimal 2048 belgi).';
      notifyListeners();
      return false;
    }
    final cleanLabel = actionLabel.trim().isEmpty ? 'Batafsil' : actionLabel.trim();
    if (cleanLabel.length > 40) {
      errorMessage = 'Havola tugmasining nomi 40 belgidan oshmasin.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      final recipientIds = <String>{};
      String? companyForAd;
      String audience = 'all';

      if (me.role == UserRole.superAdmin) {
        if (targetMode == 'all') {
          audience = 'all';
          companyForAd = null;
          recipientIds.addAll(profiles.where((p) => p.id != me.id).map((p) => p.id));
        } else if (targetMode == 'company') {
          if (targetCompanyId == null || targetCompanyId.isEmpty) throw Exception('Tashkilot tanlanmagan.');
          audience = 'company';
          companyForAd = targetCompanyId;
          recipientIds.addAll(profiles.where((p) => p.companyId == targetCompanyId && p.id != me.id).map((p) => p.id));
        } else if (targetMode == 'user') {
          if (targetProfileId == null || targetProfileId.isEmpty) throw Exception('User tanlanmagan.');
          audience = 'user';
          companyForAd = profileById(targetProfileId)?.companyId;
          recipientIds.add(targetProfileId);
        } else {
          throw Exception('Reklama target noto‘g‘ri.');
        }
      } else if (me.role == UserRole.director || me.role == UserRole.admin) {
        final companyId = me.companyId;
        if (companyId == null || companyId.isEmpty) throw Exception('Kompaniya topilmadi.');
        audience = 'company_users';
        companyForAd = companyId;
        recipientIds.addAll(profiles.where((p) => p.companyId == companyId && p.role == UserRole.user).map((p) => p.id));
      } else {
        throw Exception('Reklama yuborish uchun ruxsat yo‘q.');
      }

      recipientIds.remove(me.id);
      final mediaUrls = attachments.isEmpty ? <String>[] : await _uploadAdAttachments(files: attachments);
      final mediaTypes = attachments.map((file) {
        if (file.isVideo) return 'video';
        final ext = _safeExtension(file.name, fallback: 'jpg');
        return ext == 'gif' ? 'gif' : 'image';
      }).toList();
      final adGroupId = 'ad_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';

      final rows = <Map<String, dynamic>>[];
      // A public/master advertisement row is always inserted. This makes the ad visible even when no users exist yet.
      rows.add({
        'profile_id': null,
        'title': cleanTitle,
        'body': cleanBody,
        'notification_type': 'advertisement',
        'sent_by': me.id,
        'company_id': companyForAd,
        'ad_group_id': adGroupId,
        'audience': audience,
        'media_urls': mediaUrls,
        'media_types': mediaTypes,
        'action_url': cleanUrl.isEmpty ? null : cleanUrl,
        'action_label': cleanLabel,
      });
      for (final id in recipientIds) {
        rows.add({
          'profile_id': id,
          'title': cleanTitle,
          'body': cleanBody,
          'notification_type': 'advertisement',
          'sent_by': me.id,
          'company_id': companyForAd,
          'ad_group_id': adGroupId,
          'audience': audience,
          'media_urls': mediaUrls,
          'media_types': mediaTypes,
          'action_url': cleanUrl.isEmpty ? null : cleanUrl,
          'action_label': cleanLabel,
        });
      }
      await client.from('notifications').insert(rows);
      await _sendPushToProfiles(
        profileIds: recipientIds,
        title: cleanTitle,
        body: cleanBody,
        type: 'advertisement',
        adGroupId: adGroupId,
      );
      await refreshNotifications();
      success = true;
    });
    return success && errorMessage == null;
  }


  Future<void> refreshScheduledNotifications({bool notify = true}) async {
    final me = currentProfile;
    if (me == null || me.role != UserRole.superAdmin) return;
    try {
      final rows = await client
          .from('scheduled_notifications')
          .select()
          .order('created_at', ascending: false);
      scheduledNotifications
        ..clear()
        ..addAll((rows as List).map((e) => ScheduledNotification.fromMap(Map<String, dynamic>.from(e))));
      if (notify) notifyListeners();
    } catch (e) {
      errorMessage = _prettyError(e);
      if (notify) notifyListeners();
    }
  }

  Future<bool> saveScheduledNotification({
    String? id,
    required String title,
    required String body,
    required String sendTime,
    required List<int> weekdays,
    DateTime? specificDate,
    required bool isActive,
  }) async {
    final me = currentProfile;
    if (me == null || me.role != UserRole.superAdmin) {
      errorMessage = tr('only_super_admin');
      notifyListeners();
      return false;
    }

    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final cleanWeekdays = weekdays.toSet().where((day) => day >= 1 && day <= 7).toList()..sort();

    if (cleanTitle.isEmpty || cleanBody.isEmpty) {
      errorMessage = tr('scheduled_fill_required');
      notifyListeners();
      return false;
    }
    if (!_isValidTime(sendTime)) {
      errorMessage = tr('scheduled_invalid_time');
      notifyListeners();
      return false;
    }
    if (specificDate == null && cleanWeekdays.isEmpty) {
      errorMessage = tr('scheduled_days_required');
      notifyListeners();
      return false;
    }

    var ok = false;
    await _run(() async {
      final data = {
        'title': cleanTitle,
        'body': cleanBody,
        'send_time': sendTime,
        'weekdays': specificDate == null ? cleanWeekdays : <int>[],
        'specific_date': specificDate == null
            ? null
            : '${specificDate.year.toString().padLeft(4, '0')}-${specificDate.month.toString().padLeft(2, '0')}-${specificDate.day.toString().padLeft(2, '0')}',
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (id == null) 'created_by': me.id,
      };
      if (id == null) {
        await client.from('scheduled_notifications').insert(data);
      } else {
        await client.from('scheduled_notifications').update(data).eq('id', id);
      }
      await refreshScheduledNotifications(notify: false);
      ok = true;
    });
    return ok && errorMessage == null;
  }

  Future<bool> deleteScheduledNotification(String id) async {
    if (currentProfile?.role != UserRole.superAdmin) {
      errorMessage = tr('only_super_admin');
      notifyListeners();
      return false;
    }
    var ok = false;
    await _run(() async {
      await client.from('scheduled_notifications').delete().eq('id', id);
      scheduledNotifications.removeWhere((item) => item.id == id);
      ok = true;
    });
    return ok && errorMessage == null;
  }

  Future<bool> sendScheduledNotificationNow(ScheduledNotification item) async {
    if (currentProfile?.role != UserRole.superAdmin) {
      errorMessage = tr('only_super_admin');
      notifyListeners();
      return false;
    }
    var ok = false;
    await _run(() async {
      final recipientIds = profiles
          .where((p) => p.role != UserRole.superAdmin)
          .map((p) => p.id)
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
      if (recipientIds.isNotEmpty) {
        final groupId = 'scheduled_${item.id}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
        await client.from('notifications').insert(
              recipientIds
                  .map(
                    (id) => {
                      'profile_id': id,
                      'title': item.title,
                      'body': item.body,
                      'notification_type': 'scheduled',
                      'sent_by': currentProfile?.id,
                      'audience': 'all',
                      'ad_group_id': groupId,
                    },
                  )
                  .toList(),
            );
      }
      await refreshNotifications(notify: false);
      ok = true;
    });
    return ok && errorMessage == null;
  }

  bool _isValidTime(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    return match != null;
  }

  Future<bool> sendPasswordReset() async {
    final me = currentProfile;
    if (me == null || me.email.trim().isEmpty || me.email.contains('@servicepro.local')) {
      errorMessage = 'Bu profil uchun email orqali parol tiklash mavjud emas.';
      notifyListeners();
      return false;
    }
    var success = false;
    await _run(() async {
      await client.auth.resetPasswordForEmail(me.email.trim());
      success = true;
    });
    return success && errorMessage == null;
  }

  Future<String?> exportTicketsCsv() async {
    String? path;
    await _run(() async {
      await refreshTickets();
      if (tickets.isEmpty) {
        throw Exception(tr('tickets_empty'));
      }
      final buffer = StringBuffer();
      buffer.writeln('"Raqam","Status","Manzil","Xonadon","Muammo","Kim yaratdi","Telefon","Qabul qilgan","Bajargan","Bajarilgan tavsif","Yaratilgan vaqt"');
      for (final ticket in tickets) {
        final creator = profileById(ticket.createdBy);
        final accepted = ticket.acceptedBy == null ? null : profileById(ticket.acceptedBy!);
        final completed = ticket.completedBy == null ? null : profileById(ticket.completedBy!);
        buffer.writeln([
          ticket.number,
          ticket.status.label,
          ticket.addressLabel(buildingById(ticket.buildingId)),
          ticket.apartmentNumber,
          ticket.description,
          creator?.fullName ?? ticket.createdBy,
          creator?.phone ?? '',
          accepted?.fullName ?? '',
          completed?.fullName ?? '',
          ticket.completionDescription ?? '',
          ticket.createdAt.toIso8601String(),
        ].map(_csvCell).join(','));
      }
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/servicepro_tickets_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString('\ufeff${buffer.toString()}');
      path = file.path;
    });
    return path;
  }

  String _csvCell(String value) {
    var clean = value.replaceAll('"', '""').replaceAll('\n', ' ').replaceAll('\r', ' ');
    // Treat user-entered formulas and +998 phone numbers as text in Excel.
    if (RegExp(r'^\s*[=+@-]').hasMatch(clean)) clean = "'$clean";
    return '"$clean"';
  }


  String tr(String key) {
    final lang = currentProfile?.language ?? authLanguage;
    return AppStrings.translate(key, lang);
  }

  /// Permanently deletes the authenticated resident's Auth account and its
  /// cascading profile data. The server derives the ID from the JWT.
  Future<bool> deleteMyAccount() async {
    final me = currentProfile;
    final session = client.auth.currentSession;
    if (me == null || session == null || client.auth.currentUser?.id != me.id) {
      errorMessage = tr('delete_account_sign_in');
      notifyListeners();
      return false;
    }
    if (me.role != UserRole.user) {
      errorMessage = tr('delete_account_organization');
      notifyListeners();
      return false;
    }

    errorMessage = null;
    try {
      final response = await client.functions.invoke(
        'delete-my-account',
        body: const {'confirm': true},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ).timeout(const Duration(seconds: 45));
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw StateError('account_delete_failed');
      }
      NotificationService.clearAccount(clearPending: true);
      try { await client.auth.signOut(); } catch (_) { /* Auth user is already deleted. */ }
      clearSessionData();
      notifyListeners();
      return true;
    } catch (_) {
      errorMessage = tr('delete_account_failed');
      notifyListeners();
      return false;
    }
  }

  /// `allDevices` is intended for incident response. The default preserves
  /// other devices for ordinary staff; the super admin can revoke all sessions.
  Future<void> logout({bool allDevices = false}) async {
    _sessionHeartbeatTimer?.cancel();
    _billingRefreshTimer?.cancel();
    await _billingSub?.cancel();
    await _ticketSub?.cancel();
    await _notificationSub?.cancel();
    await _chatRoomsSub?.cancel();
    await _chatMessagesSub?.cancel();
    await _typingSub?.cancel();
    await _chatReadsSub?.cancel();
    _autoRefreshTimer?.cancel();
    await NotificationService.unregisterCurrentDevice();
    NotificationService.clearAccount(clearPending:true);
    await client.auth.signOut(
      scope: allDevices ? SignOutScope.global : SignOutScope.local,
    );
    clearSessionData();
    notifyListeners();
  }

  void clearSessionData() {
    _sessionHeartbeatTimer?.cancel();
    _chatWatchGeneration++;
    _typingStopTimer?.cancel();
    _readRefreshTimer?.cancel();
    _billingRefreshTimer?.cancel();
    _billingSub?.cancel();
    _autoRefreshTimer?.cancel();
    _ticketSub?.cancel();
    _notificationSub?.cancel();
    _chatRoomsSub?.cancel();
    _chatMessagesSub?.cancel();
    _typingSub?.cancel();
    _chatReadsSub?.cancel();
    currentProfile = null;
    profiles.clear();
    companies.clear();
    buildings.clear();
    subscriptions.clear();
    payments.clear();
    scheduledNotifications.clear();
    appSettings.clear();
    teamStats.clear();
    teamStatsError = null;
    _knownTicketIds.clear();
    _knownMessageIds.clear();
    _recentChatMessages.clear();
    _knownNotificationIds.clear();
    _notificationBaselineReady = false;
    _ticketUploadCache.clear();
    _committedTicketRequests.clear();
    chatRevision++;
    NotificationService.clearAccount();
    tickets.clear();
    notifications.clear();
    chatRooms.clear();
    activeChatMessages.clear();
    chatRevision++;
    typingProfiles.clear();
    _messageReadBy.clear();
    activeChatRoomId = null;
    selectedIndex = 0;
  }

  void setSelectedIndex(int index) {
    if (selectedIndex == index) return;
    selectedIndex = index;
    notifyListeners();
  }
}

class AppStrings {
  static const Map<String, Map<AppLanguage, String>> _values = {
 'smartcall_reports': {AppLanguage.uz: 'SmartCall hisobotlari', AppLanguage.ru: 'Отчёты SmartCall', AppLanguage.en: 'SmartCall reports'},
"company_code_invalid": {AppLanguage.uz: "Tashkilot kodi noto‘g‘ri yoki tashkilot faol emas.", AppLanguage.ru: "Неверный код или организация неактивна.", AppLanguage.en: "The code is incorrect or the organization is inactive."},
"personal_password": {AppLanguage.uz: "Shaxsiy parol", AppLanguage.ru: "Личный пароль", AppLanguage.en: "Personal password"},
"shared_company_code": {AppLanguage.uz: "Tashkilotning umumiy kirish kodi", AppLanguage.ru: "Общий код организации", AppLanguage.en: "Shared organization access code"},
 'theme_light': {AppLanguage.uz: 'Yorug‘',AppLanguage.ru: 'Светлая',AppLanguage.en: 'Light'},
 'theme_dark': {AppLanguage.uz: 'Qorong‘i',AppLanguage.ru: 'Тёмная',AppLanguage.en: 'Dark'},
'choose_worker': {AppLanguage.uz:'Ishchini tanlang.',AppLanguage.ru:'Выберите сотрудника.',AppLanguage.en:'Select a worker.'},
'only_own_workers': {AppLanguage.uz:'Faqat o‘z tashkilotingiz ishchisini boshqarishingiz mumkin.',AppLanguage.ru:'Доступны только сотрудники вашей организации.',AppLanguage.en:'Only your organization’s workers are available.'},
 'team': {AppLanguage.uz: 'Ishchilar', AppLanguage.ru: 'Сотрудники', AppLanguage.en: 'Workers'},
 'work_activity': {AppLanguage.uz: 'Vazifalar va hisobotlar', AppLanguage.ru: 'Задачи и отчёты', AppLanguage.en: 'Tasks & reports'},
'ratings': {AppLanguage.uz: 'Reytinglar', AppLanguage.ru: 'Рейтинги', AppLanguage.en: 'Rankings'},
'rating_failed': {AppLanguage.uz: 'Baho saqlanmadi yoki avval baholangan.', AppLanguage.ru: 'Оценка не сохранена или уже была выставлена.', AppLanguage.en: 'Rating was not saved or this work was already rated.'},
"super_admin": {AppLanguage.uz: "Superadmin", AppLanguage.ru: "Суперадминистратор", AppLanguage.en: "Super admin"},
"user": {AppLanguage.uz: "Aholi", AppLanguage.ru: "Житель", AppLanguage.en: "Resident"},
"export_excel": {AppLanguage.uz: "Excel hisobot", AppLanguage.ru: "Отчёт Excel", AppLanguage.en: "Excel report"},
"ticket_closed": {AppLanguage.uz: "Yopilgan", AppLanguage.ru: "Закрыты", AppLanguage.en: "Closed"},
"ticket_completed": {AppLanguage.uz: "Bajarilgan", AppLanguage.ru: "Выполнены", AppLanguage.en: "Completed"},
"ticket_in_progress": {AppLanguage.uz: "Jarayonda", AppLanguage.ru: "В работе", AppLanguage.en: "In progress"},
"ticket_new": {AppLanguage.uz: "Yangi", AppLanguage.ru: "Новые", AppLanguage.en: "New"},
    "organization_access": {AppLanguage.uz: "Tashkilot bo‘limiga o‘tish", AppLanguage.ru: "Вход для организаций", AppLanguage.en: "Organization access"},
    "resident_profile": {AppLanguage.uz: "Aholi profili", AppLanguage.ru: "Профиль жителя", AppLanguage.en: "Resident profile"},
    "resident_help": {AppLanguage.uz: "Ariza yuborish uchun ma’lumotlaringizni bir marta saqlang. Keyingi kirishda qayta so‘ralmaydi.", AppLanguage.ru: "Сохраните данные один раз, чтобы отправлять заявки. При следующем входе повторно заполнять их не нужно.", AppLanguage.en: "Save your details once to send requests. You will not need to enter them again."},
    "staff_help": {AppLanguage.uz: "Direktor, admin va ishchi uchun tashkilot kodi bir xil. Birinchi kirishda o‘zingizga shaxsiy parol yarating; keyin shu parol bilan kirasiz.", AppLanguage.ru: "Код организации общий для директора, администратора и сотрудников. При первом входе создайте личный пароль и используйте его в дальнейшем.", AppLanguage.en: "Directors, admins and workers share the organization code. Create your own password on first access and use it afterwards."},
    "legacy_help": {AppLanguage.uz: "Mavjud akkauntingizga avvalgi email va parol bilan kiring.", AppLanguage.ru: "Войдите в существующий аккаунт с прежним email и паролем.", AppLanguage.en: "Sign in to your existing account with your original email and password."},
    "legacy_login": {AppLanguage.uz: "Eski akkaunt / Superadmin", AppLanguage.ru: "Существующий аккаунт / Суперадминистратор", AppLanguage.en: "Existing account / Super admin"},
    "first_access": {AppLanguage.uz: "Birinchi kirish", AppLanguage.ru: "Первый вход", AppLanguage.en: "First access"},
    "staff_access_code": {AppLanguage.uz: "Shaxsiy kirish kodi", AppLanguage.ru: "Персональный код доступа", AppLanguage.en: "Personal access code"},
    "save_continue": {AppLanguage.uz: "Saqlash va davom etish", AppLanguage.ru: "Сохранить и продолжить", AppLanguage.en: "Save and continue"},
    "phone_format": {AppLanguage.uz: "Telefonni +998 bilan to‘liq kiriting.", AppLanguage.ru: "Введите полный номер с +998.", AppLanguage.en: "Enter the full phone number with +998."},
    "password_min": {AppLanguage.uz: "Parol kamida 8 belgidan iborat bo‘lsin.", AppLanguage.ru: "Пароль должен содержать не менее 8 символов.", AppLanguage.en: "Use a password with at least 8 characters."},
    "fill_required": {AppLanguage.uz: "Barcha majburiy maydonlarni to‘ldiring.", AppLanguage.ru: "Заполните все обязательные поля.", AppLanguage.en: "Fill in all required fields."},
    "registration_unavailable": {AppLanguage.uz: "Ro‘yxatdan o‘tish yakunlanmadi. Yordam uchun tashkilotingizga murojaat qiling.", AppLanguage.ru: "Регистрация не завершена. Обратитесь в вашу организацию.", AppLanguage.en: "Registration could not be completed. Contact your organization."},
    "account_mismatch": {AppLanguage.uz: "Akkaunt, tashkilot yoki rol mos kelmadi.", AppLanguage.ru: "Аккаунт, организация или роль не совпадают.", AppLanguage.en: "Account, organization or role does not match."},
    "directory_failed": {AppLanguage.uz: "Tashkilotlar yuklanmadi. Qayta urinib ko‘ring.", AppLanguage.ru: "Не удалось загрузить организации. Повторите попытку.", AppLanguage.en: "Could not load organizations. Please retry."},
    "neighborhood": {AppLanguage.uz: "Mahalla nomi", AppLanguage.ru: "Махалля", AppLanguage.en: "Neighborhood"},
    "street_name": {AppLanguage.uz: "Ko‘cha nomi", AppLanguage.ru: "Улица", AppLanguage.en: "Street"},
    "house_number": {AppLanguage.uz: "Uy raqami", AppLanguage.ru: "Номер дома", AppLanguage.en: "House number"},
    "job_title": {AppLanguage.uz: "Lavozim (slesar, elektrik…)", AppLanguage.ru: "Должность (слесарь, электрик…)", AppLanguage.en: "Job title (plumber, electrician…)"},
    "worker": {AppLanguage.uz: "Ishchi", AppLanguage.ru: "Сотрудник", AppLanguage.en: "Worker"},
    "guest_welcome": {AppLanguage.uz: "Uyingiz uchun g‘amxo‘rlik", AppLanguage.ru: "Забота о вашем доме", AppLanguage.en: "Care for your home"},
    "guest_intro": {AppLanguage.uz: "ServicePro’ga xush kelibsiz. Bo‘limlar bilan tanishing va uy muammolari haqida ariza yuboring.", AppLanguage.ru: "Добро пожаловать в ServicePro. Знакомьтесь с разделами и отправляйте заявки о проблемах в доме.", AppLanguage.en: "Welcome to ServicePro. Explore the app and report problems in your home."},
    "guest_support": {AppLanguage.uz: "Tashkilotingiz bilan aloqa", AppLanguage.ru: "Связь с вашей организацией", AppLanguage.en: "Contact your organization"},
    "guest_support_help": {AppLanguage.uz: "Tashkilot guruhiga va mutaxassislarga yozing.", AppLanguage.ru: "Пишите в группу организации и специалистам.", AppLanguage.en: "Message your organization and its specialists."},
    "first_ticket": {AppLanguage.uz: "Birinchi arizangizni yuboring", AppLanguage.ru: "Отправьте первую заявку", AppLanguage.en: "Send your first request"},
    "company_chat": {AppLanguage.uz: "Tashkilot suhbati", AppLanguage.ru: "Чат организации", AppLanguage.en: "Organization chat"},
    "guest_chat_help": {AppLanguage.uz: "Profilingizni saqlagach, tanlangan tashkilotingiz guruhi va ishchilari bilan suhbat ochiladi.", AppLanguage.ru: "После сохранения профиля появятся группа выбранной организации и чаты с сотрудниками.", AppLanguage.en: "Save your profile to access your organization group and worker chats."},
    "complete_profile": {AppLanguage.uz: "Ma’lumotlarni to‘ldirish", AppLanguage.ru: "Заполнить данные", AppLanguage.en: "Complete your profile"},
    "retry": {AppLanguage.uz: "Qayta urinish", AppLanguage.ru: "Повторить", AppLanguage.en: "Retry"},
    "back": {AppLanguage.uz: "Orqaga", AppLanguage.ru: "Назад", AppLanguage.en: "Back"},
    "role": {AppLanguage.uz: "Rol", AppLanguage.ru: "Роль", AppLanguage.en: "Role"},
    "theme_system": {AppLanguage.uz: "Tizimga mos", AppLanguage.ru: "Как в системе", AppLanguage.en: "System"},
    "our_team": {AppLanguage.uz: "Bizning mutaxassislar", AppLanguage.ru: "Наши специалисты", AppLanguage.en: "Our specialists"},
    "worker_jobs": {AppLanguage.uz: "Bajargan ishlar", AppLanguage.ru: "Выполненные работы", AppLanguage.en: "Completed jobs"},
    "worker_rating": {AppLanguage.uz: "Reyting", AppLanguage.ru: "Рейтинг", AppLanguage.en: "Rating"},
    "no_rating": {AppLanguage.uz: "Hali baholanmagan", AppLanguage.ru: "Пока нет оценок", AppLanguage.en: "Not rated yet"},
    "worker_salary": {AppLanguage.uz: "Oylik maosh", AppLanguage.ru: "Месячная зарплата", AppLanguage.en: "Monthly salary"},
    "not_set": {AppLanguage.uz: "Belgilanmagan", AppLanguage.ru: "Не задано", AppLanguage.en: "Not set"},
    "worker_available": {AppLanguage.uz: "Bo‘sh", AppLanguage.ru: "Свободен", AppLanguage.en: "Available"},
    "worker_busy": {AppLanguage.uz: "Ish jarayonida", AppLanguage.ru: "В работе", AppLanguage.en: "Working"},
    "invite_staff": {AppLanguage.uz: "Xodimga kirish berish", AppLanguage.ru: "Выдать доступ сотруднику", AppLanguage.en: "Invite staff"},
    "invite_created": {AppLanguage.uz: "Kodni faqat shu xodimga bering. Birinchi kirish uchun 7 kun amal qiladi.", AppLanguage.ru: "Передайте код только этому сотруднику. Для первого входа он действителен 7 дней.", AppLanguage.en: "Give this code only to this staff member. Valid for first access for 7 days."},
    "worker_settings": {AppLanguage.uz: "Ishchi sozlamalari", AppLanguage.ru: "Настройки сотрудника", AppLanguage.en: "Worker settings"},
    "rate_work": {AppLanguage.uz: "Ishni baholash", AppLanguage.ru: "Оценить работу", AppLanguage.en: "Rate this work"},
    "rating_saved": {AppLanguage.uz: "Baho saqlandi", AppLanguage.ru: "Оценка сохранена", AppLanguage.en: "Rating saved"},
    "chat_workers": {AppLanguage.uz: "Ishchilar bilan suhbat", AppLanguage.ru: "Чаты с сотрудниками", AppLanguage.en: "Worker chats"},
    "no_workers": {AppLanguage.uz: "Hozircha ishchilar qo‘shilmagan", AppLanguage.ru: "Сотрудники пока не добавлены", AppLanguage.en: "No workers added yet"},


    'app_tagline': {AppLanguage.uz: 'Boshqaruv servis kompaniyalari uchun real-time ariza tizimi', AppLanguage.ru: 'Real-time система заявок для сервисных управляющих компаний', AppLanguage.en: 'Real-time request system for service management companies'},
    'user_login': {AppLanguage.uz: 'User kirish', AppLanguage.ru: 'Вход пользователя', AppLanguage.en: 'User login'},
    'user_login_subtitle': {AppLanguage.uz: 'Telefon raqam, parol va kompaniya kodi orqali', AppLanguage.ru: 'По телефону, паролю и коду компании', AppLanguage.en: 'By phone, password and company code'},
    'director': {AppLanguage.uz: 'Direktor', AppLanguage.ru: 'Директор', AppLanguage.en: 'Director'},
    'admin': {AppLanguage.uz: 'Admin', AppLanguage.ru: 'Админ', AppLanguage.en: 'Admin'},
    'login': {AppLanguage.uz: 'Login', AppLanguage.ru: 'Вход', AppLanguage.en: 'Login'},
    'director_register_title': {AppLanguage.uz: 'Direktor ro‘yxatdan o‘tadi va kompaniya yaratadi', AppLanguage.ru: 'Директор регистрируется и создаёт компанию', AppLanguage.en: 'Director registers and creates a company'},
    'admin_join_title': {AppLanguage.uz: 'Admin kompaniya kodi orqali qo‘shiladi', AppLanguage.ru: 'Админ подключается по коду компании', AppLanguage.en: 'Admin joins using company code'},
    'user_form_title': {AppLanguage.uz: 'User kirishi', AppLanguage.ru: 'Вход пользователя', AppLanguage.en: 'User login'},
    'user_form_help': {AppLanguage.uz: 'Birinchi kirishda ism-familiya, telefon, parol va kompaniya kodini kiriting. Keyingi safar telefon, parol va kompaniya kodi bilan eski profilingizga kirasiz.', AppLanguage.ru: 'При первом входе введите имя, фамилию, телефон, пароль и код компании. Потом входите в свой профиль по телефону, паролю и коду компании.', AppLanguage.en: 'On first login enter your name, phone, password and company code. Next time use phone, password and company code to open the same profile.'},
    'director_admin_login': {AppLanguage.uz: 'Direktor/Admin/Super Admin login', AppLanguage.ru: 'Вход директора/админа/супер админа', AppLanguage.en: 'Director/Admin/Super Admin login'},
    'email': {AppLanguage.uz: 'Email', AppLanguage.ru: 'Email', AppLanguage.en: 'Email'},
    'password': {AppLanguage.uz: 'Parol', AppLanguage.ru: 'Пароль', AppLanguage.en: 'Password'},
    'login_password': {AppLanguage.uz: 'Login parol', AppLanguage.ru: 'Пароль для входа', AppLanguage.en: 'Login password'},
    'company_name': {AppLanguage.uz: 'Kompaniya nomi', AppLanguage.ru: 'Название компании', AppLanguage.en: 'Company name'},
    'company_code': {AppLanguage.uz: 'Kompaniya kodi', AppLanguage.ru: 'Код компании', AppLanguage.en: 'Company code'},
    'company_code_for_users': {AppLanguage.uz: 'Admin/Userlar uchun kompaniya kodi', AppLanguage.ru: 'Код компании для админов/пользователей', AppLanguage.en: 'Company code for admins/users'},
    'create_company_and_login': {AppLanguage.uz: 'Kompaniya yaratish va kirish', AppLanguage.ru: 'Создать компанию и войти', AppLanguage.en: 'Create company and login'},
    'join_as_admin': {AppLanguage.uz: 'Admin sifatida qo‘shilish', AppLanguage.ru: 'Подключиться как админ', AppLanguage.en: 'Join as admin'},
    'login_as_user': {AppLanguage.uz: 'User sifatida kirish', AppLanguage.ru: 'Войти как пользователь', AppLanguage.en: 'Login as user'},
    'role_menu_director_subtitle': {AppLanguage.uz: 'Yangi kompaniya yaratish', AppLanguage.ru: 'Создать новую компанию', AppLanguage.en: 'Create a new company'},
    'role_menu_admin_subtitle': {AppLanguage.uz: 'Mavjud kompaniyaga admin bo‘lib qo‘shilish', AppLanguage.ru: 'Подключиться к компании как админ', AppLanguage.en: 'Join an existing company as admin'},
    'role_menu_login_subtitle': {AppLanguage.uz: 'Email va parol orqali kirish', AppLanguage.ru: 'Войти по email и паролю', AppLanguage.en: 'Login with email and password'},
    'user_login_note': {AppLanguage.uz: 'Userlar telefon raqam va parol orqali kiradi. Direktor/Admin email-parol orqali kiradi.', AppLanguage.ru: 'Пользователи входят по телефону и паролю. Директор/Админ входят по email и паролю.', AppLanguage.en: 'Users login with phone and password. Director/Admin login with email and password.'},
    'dashboard': {AppLanguage.uz: 'Dashboard', AppLanguage.ru: 'Панель', AppLanguage.en: 'Dashboard'},
    'create': {AppLanguage.uz: 'Yaratish', AppLanguage.ru: 'Создать', AppLanguage.en: 'Create'},
    'tickets': {AppLanguage.uz: 'Arizalar', AppLanguage.ru: 'Заявки', AppLanguage.en: 'Tickets'},
    'chat': {AppLanguage.uz: 'Chat', AppLanguage.ru: 'Чат', AppLanguage.en: 'Chat'},
    'ads': {AppLanguage.uz: 'Reklama', AppLanguage.ru: 'Реклама', AppLanguage.en: 'Ads'},
    'profile': {AppLanguage.uz: 'Profil', AppLanguage.ru: 'Профиль', AppLanguage.en: 'Profile'},
    'companies': {AppLanguage.uz: 'Tashkilotlar', AppLanguage.ru: 'Организации', AppLanguage.en: 'Companies'},
    'users': {AppLanguage.uz: 'Userlar', AppLanguage.ru: 'Пользователи', AppLanguage.en: 'Users'},
    'notifications': {AppLanguage.uz: 'Bildirishnomalar', AppLanguage.ru: 'Уведомления', AppLanguage.en: 'Notifications'},
    'no_notifications': {AppLanguage.uz: 'Hozircha bildirishnoma yo‘q.', AppLanguage.ru: 'Пока уведомлений нет.', AppLanguage.en: 'No notifications yet.'},
    'welcome': {AppLanguage.uz: 'Xush kelibsiz', AppLanguage.ru: 'Добро пожаловать', AppLanguage.en: 'Welcome'},
    'settings': {AppLanguage.uz: 'Sozlanmalar', AppLanguage.ru: 'Настройки', AppLanguage.en: 'Settings'},
    'information': {AppLanguage.uz: 'Axborot', AppLanguage.ru: 'информация', AppLanguage.en: 'Information'},
    'language': {AppLanguage.uz: 'Til', AppLanguage.ru: 'Язык', AppLanguage.en: 'Language'},
    'theme': {AppLanguage.uz: 'Mode rejim', AppLanguage.ru: 'Тема', AppLanguage.en: 'Theme'},
    'save': {AppLanguage.uz: 'Saqlash', AppLanguage.ru: 'Сохранить', AppLanguage.en: 'Save'},
    'logout': {AppLanguage.uz: 'Ilovani tark etish', AppLanguage.ru: 'Выйти', AppLanguage.en: 'Logout'},
    'delete_account': {AppLanguage.uz: 'Profilni o‘chirish', AppLanguage.ru: 'Удалить профиль', AppLanguage.en: 'Delete profile'},
    'delete_account_title': {AppLanguage.uz: 'Profilni butunlay o‘chirish', AppLanguage.ru: 'Удалить профиль навсегда', AppLanguage.en: 'Permanently delete profile'},
    'delete_account_warning': {AppLanguage.uz: 'Profilingiz, siz yaratgan arizalar va chat xabarlaringiz bazadan butunlay o‘chadi. Bu amalni ortga qaytarib bo‘lmaydi.', AppLanguage.ru: 'Ваш профиль, созданные обращения и сообщения чата будут удалены без возможности восстановления.', AppLanguage.en: 'Your profile, submitted requests and chat messages will be permanently deleted. This cannot be undone.'},
    'delete_account_agree': {AppLanguage.uz: 'O‘chirish oqibatlarini tushundim', AppLanguage.ru: 'Я понимаю последствия удаления', AppLanguage.en: 'I understand the consequences'},
    'delete_account_organization': {AppLanguage.uz: 'Direktor, administrator, ishchi va Super Admin akkauntlari tashkilot ma’lumotlari bilan bog‘langan. Bunday profilni o‘chirish uchun avval tashkilot rahbari yoki Super Admin orqali vazifalarni o‘tkazish kerak.', AppLanguage.ru: 'Аккаунты сотрудников и руководителей связаны с организацией. Сначала передайте обязанности через руководителя или Super Admin.', AppLanguage.en: 'Staff and owner accounts are linked to organizational data. Transfer responsibilities with a director or Super Admin first.'},
    'delete_account_sign_in': {AppLanguage.uz: 'Sessiya topilmadi. Qayta kiring.', AppLanguage.ru: 'Сеанс не найден. Войдите снова.', AppLanguage.en: 'Session not found. Sign in again.'},
    'delete_account_failed': {AppLanguage.uz: 'Profil o‘chirilmadi. Internet aloqasi va Supabase delete-my-account funksiyasi sozlamalarini tekshiring.', AppLanguage.ru: 'Не удалось удалить профиль. Проверьте сеть и серверную функцию delete-my-account.', AppLanguage.en: 'Profile was not deleted. Check your connection and the delete-my-account server function.'},
    'profile_saved': {AppLanguage.uz: 'Profil saqlandi.', AppLanguage.ru: 'Профиль сохранён.', AppLanguage.en: 'Profile saved.'},
    'first_name': {AppLanguage.uz: 'Ism', AppLanguage.ru: 'Имя', AppLanguage.en: 'First name'},
    'last_name': {AppLanguage.uz: 'Familiya', AppLanguage.ru: 'Фамилия', AppLanguage.en: 'Last name'},
    'phone': {AppLanguage.uz: 'Telefon', AppLanguage.ru: 'Телефон', AppLanguage.en: 'Phone'},
    'create_ticket': {AppLanguage.uz: 'Ariza yaratish', AppLanguage.ru: 'Создать заявку', AppLanguage.en: 'Create ticket'},
    'search_chat': {AppLanguage.uz: 'Chat yoki odam qidirish', AppLanguage.ru: 'Поиск чата или человека', AppLanguage.en: 'Search chat or person'},
    'start_direct_chat': {AppLanguage.uz: 'Shaxsiy chat boshlash', AppLanguage.ru: 'Начать личный чат', AppLanguage.en: 'Start direct chat'},
    'no_people_found': {AppLanguage.uz: 'Hozircha chat boshlash uchun odam topilmadi.', AppLanguage.ru: 'Пока нет людей для чата.', AppLanguage.en: 'No people found for chat yet.'},
    'recent_chats': {AppLanguage.uz: 'Oxirgi chatlar', AppLanguage.ru: 'Последние чаты', AppLanguage.en: 'Recent chats'},
    'no_direct_chats': {AppLanguage.uz: 'Hozircha shaxsiy chat yo‘q. Yuqoridan odam tanlang.', AppLanguage.ru: 'Личных чатов пока нет. Выберите человека сверху.', AppLanguage.en: 'No direct chats yet. Choose a person above.'},
    'chat_subtitle': {AppLanguage.uz: 'Real-time, reply, edit, delete, rasm/video.', AppLanguage.ru: 'Real-time, ответ, редактирование, удаление, фото/видео.', AppLanguage.en: 'Real-time, reply, edit, delete, photo/video.'},
    'offline_title': {AppLanguage.uz: 'Siz offline siz', AppLanguage.ru: 'Вы офлайн', AppLanguage.en: 'You are offline'},
    'offline_subtitle': {AppLanguage.uz: 'Ilova ishlashi uchun internetni yoqing. Internet qaytsa, ilova avtomatik davom etadi.', AppLanguage.ru: 'Включите интернет для работы приложения. Когда связь вернётся, приложение продолжит работу автоматически.', AppLanguage.en: 'Turn on internet to use the app. When connection returns, the app will continue automatically.'},
    'checking_connection': {AppLanguage.uz: 'Internet tekshirilmoqda...', AppLanguage.ru: 'Проверяем интернет...', AppLanguage.en: 'Checking connection...'},
    'try_again': {AppLanguage.uz: 'Qayta tekshirish', AppLanguage.ru: 'Проверить снова', AppLanguage.en: 'Try again'},
    'all_companies': {AppLanguage.uz: 'Barcha kompaniyalar', AppLanguage.ru: 'Все компании', AppLanguage.en: 'All companies'},
    'video_attached': {AppLanguage.uz: 'Video biriktirilgan', AppLanguage.ru: 'Видео прикреплено', AppLanguage.en: 'Video attached'},
    'media_failed': {AppLanguage.uz: 'Media ochilmadi', AppLanguage.ru: 'Медиа не открылось', AppLanguage.en: 'Media failed to open'},
    'system': {AppLanguage.uz: 'Sistema', AppLanguage.ru: 'Система', AppLanguage.en: 'System'},
    'light': {AppLanguage.uz: 'Yorug‘', AppLanguage.ru: 'Светлая', AppLanguage.en: 'Light'},
    'dark': {AppLanguage.uz: 'Qorong‘i', AppLanguage.ru: 'Тёмная', AppLanguage.en: 'Dark'},
    'reset_password': {AppLanguage.uz: 'Parolni tiklash havolasini yuborish', AppLanguage.ru: 'Отправить ссылку восстановления пароля', AppLanguage.en: 'Send password reset link'},
    'logout_title': {AppLanguage.uz: 'Ilovadan chiqish', AppLanguage.ru: 'Выйти из приложения', AppLanguage.en: 'Logout'},
    'logout_confirm': {AppLanguage.uz: 'Haqiqatan ham ilovadan chiqmoqchimisiz?', AppLanguage.ru: 'Вы действительно хотите выйти?', AppLanguage.en: 'Do you really want to logout?'},
    'no': {AppLanguage.uz: 'Yo‘q', AppLanguage.ru: 'Нет', AppLanguage.en: 'No'},
    'yes': {AppLanguage.uz: 'Ha', AppLanguage.ru: 'Да', AppLanguage.en: 'Yes'},
    'cancel': {AppLanguage.uz: 'Bekor', AppLanguage.ru: 'Отмена', AppLanguage.en: 'Cancel'},
    'close': {AppLanguage.uz: 'Yopish', AppLanguage.ru: 'Закрыть', AppLanguage.en: 'Close'},
    'download': {AppLanguage.uz: 'Yuklab olish', AppLanguage.ru: 'Скачать', AppLanguage.en: 'Download'},
    'send': {AppLanguage.uz: 'Jo‘natish', AppLanguage.ru: 'Отправить', AppLanguage.en: 'Send'},
    'sending': {AppLanguage.uz: 'Yuborilmoqda...', AppLanguage.ru: 'Отправляется...', AppLanguage.en: 'Sending...'},
    'create_ticket_title': {AppLanguage.uz: 'Ariza yaratish', AppLanguage.ru: 'Создать заявку', AppLanguage.en: 'Create ticket'},
    'address_info': {AppLanguage.uz: 'Manzil ma’lumotlari', AppLanguage.ru: 'Данные адреса', AppLanguage.en: 'Address details'},
    'address_info_subtitle': {AppLanguage.uz: 'Manzil va xonadon raqamini aniq kiriting.', AppLanguage.ru: 'Введите точный адрес и номер квартиры.', AppLanguage.en: 'Enter the exact address and apartment number.'},
    'address': {AppLanguage.uz: 'Manzil', AppLanguage.ru: 'Адрес', AppLanguage.en: 'Address'},
    'apartment_number': {AppLanguage.uz: 'Xonadon raqami', AppLanguage.ru: 'Номер квартиры', AppLanguage.en: 'Apartment number'},
    'problem_description': {AppLanguage.uz: 'Muammo tavsifi', AppLanguage.ru: 'Описание проблемы', AppLanguage.en: 'Problem description'},
    'problem_description_subtitle': {AppLanguage.uz: 'Muammoni tushunarli yozing.', AppLanguage.ru: 'Опишите проблему понятно.', AppLanguage.en: 'Describe the problem clearly.'},
    'old_addresses': {AppLanguage.uz: 'Oldingi manzillar', AppLanguage.ru: 'Предыдущие адреса', AppLanguage.en: 'Previous addresses'},
    'image': {AppLanguage.uz: 'Rasm', AppLanguage.ru: 'Фото', AppLanguage.en: 'Image'},
    'video': {AppLanguage.uz: 'Video', AppLanguage.ru: 'Видео', AppLanguage.en: 'Video'},
    'image_video': {AppLanguage.uz: 'Rasm/video', AppLanguage.ru: 'Фото/видео', AppLanguage.en: 'Image/video'},
    'media_subtitle': {AppLanguage.uz: 'Muammoni aniq ko‘rsatish uchun fayl qo‘shing.', AppLanguage.ru: 'Добавьте файл, чтобы точнее показать проблему.', AppLanguage.en: 'Add a file to show the problem clearly.'},
    'media_limit': {AppLanguage.uz: 'Limit: rasm 8 MB gacha, video 60 MB gacha.', AppLanguage.ru: 'Лимит: фото до 8 МБ, видео до 60 МБ.', AppLanguage.en: 'Limit: image up to 8 MB, video up to 60 MB.'},
    'submit_ticket': {AppLanguage.uz: 'Arizani jo‘natish', AppLanguage.ru: 'Отправить заявку', AppLanguage.en: 'Submit ticket'},
    'ticket_created': {AppLanguage.uz: 'Ariza yaratildi va admin/direktorga yuborildi.', AppLanguage.ru: 'Заявка создана и отправлена админу/директору.', AppLanguage.en: 'Ticket created and sent to admin/director.'},
    'fill_ticket_required': {AppLanguage.uz: 'Manzil, xonadon raqami va muammo tavsifini kiriting.', AppLanguage.ru: 'Введите адрес, номер квартиры и описание проблемы.', AppLanguage.en: 'Enter address, apartment number and problem description.'},
    'ticket_create_failed': {AppLanguage.uz: 'Ariza yaratilmadi. Qayta urinib ko‘ring.', AppLanguage.ru: 'Заявка не создана. Попробуйте снова.', AppLanguage.en: 'Ticket was not created. Try again.'},
    'tickets_empty': {AppLanguage.uz: 'Arizalar yo‘q', AppLanguage.ru: 'Заявок нет', AppLanguage.en: 'No tickets'},
    'tickets_empty_subtitle': {AppLanguage.uz: 'Pastdagi tugma orqali yangi ariza yarating. Real-time arizalar shu yerda ko‘rinadi.', AppLanguage.ru: 'Создайте заявку кнопкой ниже. Real-time заявки появятся здесь.', AppLanguage.en: 'Create a new ticket using the button below. Real-time tickets will appear here.'},
    'view_full': {AppLanguage.uz: 'To‘liq ko‘rish', AppLanguage.ru: 'Подробнее', AppLanguage.en: 'View full'},
    'accept': {AppLanguage.uz: 'Qabul qilish', AppLanguage.ru: 'Принять', AppLanguage.en: 'Accept'},
    'complete': {AppLanguage.uz: 'Bajarildi qilish', AppLanguage.ru: 'Завершить', AppLanguage.en: 'Mark completed'},
    'media_count': {AppLanguage.uz: 'ta rasm/video bor', AppLanguage.ru: 'фото/видео', AppLanguage.en: 'media files'},
    'requester': {AppLanguage.uz: 'Ariza qoldirgan', AppLanguage.ru: 'Заявитель', AppLanguage.en: 'Requester'},
    'created_at': {AppLanguage.uz: 'Yaratilgan vaqt', AppLanguage.ru: 'Создано', AppLanguage.en: 'Created at'},
    'accepted_by': {AppLanguage.uz: 'Qabul qilgan', AppLanguage.ru: 'Принял', AppLanguage.en: 'Accepted by'},
    'completed_by': {AppLanguage.uz: 'Bajargan', AppLanguage.ru: 'Выполнил', AppLanguage.en: 'Completed by'},
    'request_media': {AppLanguage.uz: 'Muammo rasm/video', AppLanguage.ru: 'Фото/видео проблемы', AppLanguage.en: 'Problem image/video'},
    'completion_desc': {AppLanguage.uz: 'Bajarilgan ish tavsifi', AppLanguage.ru: 'Описание выполненной работы', AppLanguage.en: 'Completed work description'},
    'completion_media': {AppLanguage.uz: 'Bajarilgan ish rasm/video', AppLanguage.ru: 'Фото/видео выполненной работы', AppLanguage.en: 'Completed work image/video'},
    'complete_ticket_title': {AppLanguage.uz: 'Arizani bajarildi qilish', AppLanguage.ru: 'Завершить заявку', AppLanguage.en: 'Complete ticket'},
    'required_completion_media': {AppLanguage.uz: 'Rasm/video majburiy', AppLanguage.ru: 'Фото/видео обязательно', AppLanguage.en: 'Image/video required'},
    'file_open_failed': {AppLanguage.uz: 'Faylni ochib bo‘lmadi.', AppLanguage.ru: 'Не удалось открыть файл.', AppLanguage.en: 'Could not open file.'},
    'play_video': {AppLanguage.uz: 'Videoni o‘ynatish', AppLanguage.ru: 'Воспроизвести видео', AppLanguage.en: 'Play video'},
    'today_work_hint': {AppLanguage.uz: 'Bugungi ish jarayonlarini shu yerdan kuzating.', AppLanguage.ru: 'Следите за сегодняшними процессами здесь.', AppLanguage.en: 'Track today’s work processes here.'},
    'quick_status': {AppLanguage.uz: 'Tezkor holat', AppLanguage.ru: 'Быстрый статус', AppLanguage.en: 'Quick status'},
    'new': {AppLanguage.uz: 'Yangi', AppLanguage.ru: 'Новая', AppLanguage.en: 'New'},
    'in_progress': {AppLanguage.uz: 'Jarayonda', AppLanguage.ru: 'В процессе', AppLanguage.en: 'In progress'},
    'completed': {AppLanguage.uz: 'Bajarilgan', AppLanguage.ru: 'Выполнено', AppLanguage.en: 'Completed'},
    'total_tickets': {AppLanguage.uz: 'Jami arizalar', AppLanguage.ru: 'Всего заявок', AppLanguage.en: 'Total tickets'},
    'members': {AppLanguage.uz: 'A’zolar', AppLanguage.ru: 'Участники', AppLanguage.en: 'Members'},
    'latest_tickets': {AppLanguage.uz: 'Oxirgi arizalar', AppLanguage.ru: 'Последние заявки', AppLanguage.en: 'Latest tickets'},
    'all': {AppLanguage.uz: 'Barchasi', AppLanguage.ru: 'Все', AppLanguage.en: 'All'},
    'no_tickets_yet': {AppLanguage.uz: 'Hozircha ariza yo‘q.', AppLanguage.ru: 'Пока заявок нет.', AppLanguage.en: 'No tickets yet.'},
    'ads_title': {AppLanguage.uz: 'E’lonlar', AppLanguage.ru: 'Объявления', AppLanguage.en: 'Announcements'},
    'excel_report': {AppLanguage.uz: 'Excel hisobot', AppLanguage.ru: 'Excel отчёт', AppLanguage.en: 'Excel report'},
    'profile_global_panel': {AppLanguage.uz: 'Super Admin global panel', AppLanguage.ru: 'Глобальная панель Super Admin', AppLanguage.en: 'Super Admin global panel'},
    'avatar_updated': {AppLanguage.uz: 'Profil rasmi yangilandi.', AppLanguage.ru: 'Фото профиля обновлено.', AppLanguage.en: 'Profile photo updated.'},
    'avatar_failed': {AppLanguage.uz: 'Rasm yuklanmadi.', AppLanguage.ru: 'Фото не загрузилось.', AppLanguage.en: 'Image was not uploaded.'},
    'reset_sent': {AppLanguage.uz: 'Parol tiklash havolasi emailingizga yuborildi.', AppLanguage.ru: 'Ссылка для восстановления пароля отправлена на email.', AppLanguage.en: 'Password reset link was sent to your email.'},
    'reset_failed': {AppLanguage.uz: 'Parol tiklash ishlamadi.', AppLanguage.ru: 'Восстановление пароля не сработало.', AppLanguage.en: 'Password reset failed.'},
    'super_admin_panel': {AppLanguage.uz: 'Super Admin boshqaruv paneli', AppLanguage.ru: 'Панель управления Super Admin', AppLanguage.en: 'Super Admin control panel'},
    'super_admin_panel_subtitle': {AppLanguage.uz: 'Barcha tashkilotlar, arizalar, reklamalar va umumiy chatlar shu yerdan boshqariladi.', AppLanguage.ru: 'Все организации, заявки, реклама и общие чаты управляются здесь.', AppLanguage.en: 'All companies, tickets, ads and group chats are managed here.'},
    'refresh_all': {AppLanguage.uz: 'Hammasini yangilash', AppLanguage.ru: 'Обновить всё', AppLanguage.en: 'Refresh all'},
    'cleanup_old_data': {AppLanguage.uz: 'Eski ma’lumotlarni tozalash', AppLanguage.ru: 'Очистить старые данные', AppLanguage.en: 'Clean old data'},
    'delete': {AppLanguage.uz: 'O‘chirish', AppLanguage.ru: 'Удалить', AppLanguage.en: 'Delete'},
    'edit': {AppLanguage.uz: 'Tahrirlash', AppLanguage.ru: 'Редактировать', AppLanguage.en: 'Edit'},
    'reply': {AppLanguage.uz: 'Javob yozish', AppLanguage.ru: 'Ответить', AppLanguage.en: 'Reply'},
    'ads_center': {AppLanguage.uz: 'Reklama / E’lon markazi', AppLanguage.ru: 'Центр рекламы / объявлений', AppLanguage.en: 'Ads / announcements center'},
    'refresh': {AppLanguage.uz: 'Yangilash', AppLanguage.ru: 'Обновить', AppLanguage.en: 'Refresh'},
    'ads_refreshed': {AppLanguage.uz: 'Reklamalar yangilandi.', AppLanguage.ru: 'Реклама обновлена.', AppLanguage.en: 'Ads refreshed.'},
    'new_ad': {AppLanguage.uz: 'Yangi reklama', AppLanguage.ru: 'Новая реклама', AppLanguage.en: 'New ad'},
    'title': {AppLanguage.uz: 'Sarlavha', AppLanguage.ru: 'Заголовок', AppLanguage.en: 'Title'},
    'text': {AppLanguage.uz: 'Matn', AppLanguage.ru: 'Текст', AppLanguage.en: 'Text'},
    'send_ad': {AppLanguage.uz: 'Reklamani yuborish', AppLanguage.ru: 'Отправить рекламу', AppLanguage.en: 'Send ad'},
    'sent_ads': {AppLanguage.uz: 'Men yuborgan reklamalar', AppLanguage.ru: 'Отправленная мной реклама', AppLanguage.en: 'Ads I sent'},
    'received_ads': {AppLanguage.uz: 'Menga kelgan reklamalar', AppLanguage.ru: 'Полученная реклама', AppLanguage.en: 'Ads I received'},
    'no_sent_ads': {AppLanguage.uz: 'Hozircha yuborilgan reklama yo‘q.', AppLanguage.ru: 'Пока отправленной рекламы нет.', AppLanguage.en: 'No sent ads yet.'},
    'no_received_ads': {AppLanguage.uz: 'Hozircha kelgan reklama yo‘q.', AppLanguage.ru: 'Пока полученной рекламы нет.', AppLanguage.en: 'No received ads yet.'},
    'clear_media': {AppLanguage.uz: 'Media tozalash', AppLanguage.ru: 'Очистить медиа', AppLanguage.en: 'Clear media'},
    'image_gif': {AppLanguage.uz: 'Rasm/GIF', AppLanguage.ru: 'Фото/GIF', AppLanguage.en: 'Image/GIF'},
    'no_companies_yet': {AppLanguage.uz: 'Hozircha kompaniya yo‘q.', AppLanguage.ru: 'Пока компаний нет.', AppLanguage.en: 'No companies yet.'},
    'cleanup_old_data_subtitle': {AppLanguage.uz: 'Bu tugma hamma eski arizalar, reklamalar, chat xabarlari va chat roomlarni databasedan butunlay o‘chiradi. Kompaniyalar va user profillari qoladi.', AppLanguage.ru: 'Эта кнопка полностью удалит старые заявки, рекламу, сообщения и чаты из базы. Компании и профили останутся.', AppLanguage.en: 'This button permanently deletes old tickets, ads, chat messages and chat rooms from the database. Companies and user profiles remain.'},
    'cleanup_activity_button': {AppLanguage.uz: 'Ariza / reklama / chatlarni tozalash', AppLanguage.ru: 'Очистить заявки / рекламу / чаты', AppLanguage.en: 'Clean tickets / ads / chats'},
    'cleanup_confirm_title': {AppLanguage.uz: 'Database tozalansinmi?', AppLanguage.ru: 'Очистить базу данных?', AppLanguage.en: 'Clean database?'},
    'cleanup_confirm_body': {AppLanguage.uz: 'Arizalar, reklamalar, chatlar va yozishmalar butunlay o‘chadi. Kompaniyalar va userlar qoladi. Davom etasizmi?', AppLanguage.ru: 'Заявки, реклама, чаты и переписки будут удалены полностью. Компании и пользователи останутся. Продолжить?', AppLanguage.en: 'Tickets, ads, chats and messages will be permanently deleted. Companies and users remain. Continue?'},
    'yes_cleanup': {AppLanguage.uz: 'Ha, tozalash', AppLanguage.ru: 'Да, очистить', AppLanguage.en: 'Yes, clean'},
    'cleanup_done': {AppLanguage.uz: 'Eski ariza, reklama va chatlar tozalandi.', AppLanguage.ru: 'Старые заявки, реклама и чаты очищены.', AppLanguage.en: 'Old tickets, ads and chats were cleaned.'},

    'billing': {AppLanguage.uz: 'Billing', AppLanguage.ru: 'Биллинг', AppLanguage.en: 'Billing'},
    'subscribers': {AppLanguage.uz: 'Abonentlar', AppLanguage.ru: 'Абоненты', AppLanguage.en: 'Subscribers'},
    'billing_imports': {AppLanguage.uz: 'Excel importlari', AppLanguage.ru: 'Импорт Excel', AppLanguage.en: 'Excel imports'},
    'my_account': {AppLanguage.uz: 'Mening hisobim', AppLanguage.ru: 'Мой счёт', AppLanguage.en: 'My account'},
    'billing_title': {AppLanguage.uz: 'Obuna va to‘lovlar', AppLanguage.ru: 'Подписка и платежи', AppLanguage.en: 'Subscription and payments'},
    'billing_subtitle': {AppLanguage.uz: 'Oylik obuna, chegirma va to‘lovlarni boshqarish.', AppLanguage.ru: 'Управление месячной подпиской, скидками и платежами.', AppLanguage.en: 'Manage monthly subscription, discounts and payments.'},
    'monthly_price': {AppLanguage.uz: 'Oylik narx', AppLanguage.ru: 'Месячная цена', AppLanguage.en: 'Monthly price'},
    'discount_percent': {AppLanguage.uz: 'Chegirma foiz', AppLanguage.ru: 'Скидка %', AppLanguage.en: 'Discount %'},
    'discount_amount': {AppLanguage.uz: 'Chegirma summa', AppLanguage.ru: 'Сумма скидки', AppLanguage.en: 'Discount amount'},
    'payable_amount': {AppLanguage.uz: 'To‘lanadigan summa', AppLanguage.ru: 'Сумма к оплате', AppLanguage.en: 'Payable amount'},
    'subscription_status': {AppLanguage.uz: 'Obuna holati', AppLanguage.ru: 'Статус подписки', AppLanguage.en: 'Subscription status'},
    'add_payment': {AppLanguage.uz: 'To‘lov qo‘shish', AppLanguage.ru: 'Добавить платёж', AppLanguage.en: 'Add payment'},
    'payment_history': {AppLanguage.uz: 'To‘lovlar tarixi', AppLanguage.ru: 'История платежей', AppLanguage.en: 'Payment history'},
    'period_days': {AppLanguage.uz: 'Kun', AppLanguage.ru: 'Дни', AppLanguage.en: 'Days'},
    'amount_required': {AppLanguage.uz: 'To‘lov summasini to‘g‘ri kiriting.', AppLanguage.ru: 'Введите корректную сумму платежа.', AppLanguage.en: 'Enter a valid payment amount.'},
    'only_super_admin': {AppLanguage.uz: 'Bu amal faqat Super Admin uchun.', AppLanguage.ru: 'Это действие доступно только Super Admin.', AppLanguage.en: 'This action is only available to Super Admin.'},
    'billing_saved': {AppLanguage.uz: 'Billing ma’lumotlari saqlandi.', AppLanguage.ru: 'Данные биллинга сохранены.', AppLanguage.en: 'Billing data saved.'},
    'payment_added': {AppLanguage.uz: 'To‘lov qo‘shildi va obuna uzaytirildi.', AppLanguage.ru: 'Платёж добавлен, подписка продлена.', AppLanguage.en: 'Payment added and subscription extended.'},
    'billing_sql_missing': {AppLanguage.uz: 'Billing SQL yangilanmagan. supabase/servicepro_schema.sql faylini SQL Editor’da qayta run qiling.', AppLanguage.ru: 'SQL биллинга не обновлён. Запустите supabase/servicepro_schema.sql в SQL Editor.', AppLanguage.en: 'Billing SQL is not updated. Run supabase/servicepro_schema.sql in SQL Editor.'},
    'error_network': {AppLanguage.uz: 'Internet aloqasi uzildi. Internetni tekshirib qayta urinib ko‘ring.', AppLanguage.ru: 'Соединение потеряно. Проверьте интернет и попробуйте снова.', AppLanguage.en: 'Connection lost. Check internet and try again.'},
    'error_permission': {AppLanguage.uz: 'Bu amal uchun ruxsat yo‘q. Admin huquqini tekshiring.', AppLanguage.ru: 'Нет доступа для этого действия. Проверьте права администратора.', AppLanguage.en: 'You do not have permission for this action.'},
    'error_duplicate': {AppLanguage.uz: 'Bu ma’lumot oldin kiritilgan. Boshqa qiymat kiriting.', AppLanguage.ru: 'Эти данные уже существуют. Введите другое значение.', AppLanguage.en: 'This data already exists. Enter another value.'},
    'error_not_found': {AppLanguage.uz: 'Ma’lumot topilmadi. Yangilab qayta urinib ko‘ring.', AppLanguage.ru: 'Данные не найдены. Обновите и попробуйте снова.', AppLanguage.en: 'Data not found. Refresh and try again.'},
    'error_unknown': {AppLanguage.uz: 'Noma’lum xatolik. Qayta urinib ko‘ring.', AppLanguage.ru: 'Неизвестная ошибка. Попробуйте снова.', AppLanguage.en: 'Unknown error. Try again.'},
    'continue_with_google': {AppLanguage.uz: 'Google orqali kirish', AppLanguage.ru: 'Войти через Google', AppLanguage.en: 'Continue with Google'},
    'google_login_note': {AppLanguage.uz: 'Google kirish Super Admin yoki oldindan profil ochilgan email uchun ishlaydi.', AppLanguage.ru: 'Вход через Google работает для Super Admin или заранее созданного профиля.', AppLanguage.en: 'Google login works for Super Admin or an email with an existing profile.'},
    'ai_assistant': {AppLanguage.uz: 'AI yordamchi', AppLanguage.ru: 'AI помощник', AppLanguage.en: 'AI assistant'},
    'open_ai_assistant': {AppLanguage.uz: 'AI yordamchini ochish', AppLanguage.ru: 'Открыть AI помощника', AppLanguage.en: 'Open AI assistant'},
    'video_loading': {AppLanguage.uz: 'Video yuklanmoqda...', AppLanguage.ru: 'Видео загружается...', AppLanguage.en: 'Loading video...'},
    'video_open_failed': {AppLanguage.uz: 'Videoni ilova ichida ochib bo‘lmadi. Fayl formatini tekshiring.', AppLanguage.ru: 'Не удалось открыть видео внутри приложения. Проверьте формат файла.', AppLanguage.en: 'Could not open video in the app. Check the file format.'},
    'show_password': {AppLanguage.uz: 'Parolni ko‘rsatish', AppLanguage.ru: 'Показать пароль', AppLanguage.en: 'Show password'},
    'hide_password': {AppLanguage.uz: 'Parolni yashirish', AppLanguage.ru: 'Скрыть пароль', AppLanguage.en: 'Hide password'},
    'delete_chat': {AppLanguage.uz: 'Chatni o‘chirish', AppLanguage.ru: 'Удалить чат', AppLanguage.en: 'Delete chat'},
    'delete_chat_confirm': {AppLanguage.uz: 'Bu shaxsiy chat va yozishmalari butunlay o‘chadi. Davom etasizmi?', AppLanguage.ru: 'Этот личный чат и переписка будут удалены. Продолжить?', AppLanguage.en: 'This direct chat and messages will be deleted. Continue?'},
    'private_chats': {AppLanguage.uz: 'Shaxsiy chatlar', AppLanguage.ru: 'Личные чаты', AppLanguage.en: 'Private chats'},

    'scheduled_notifications': {AppLanguage.uz: 'Rejali bildirishnomalar', AppLanguage.ru: 'Плановые уведомления', AppLanguage.en: 'Scheduled notifications'},
    'scheduled_notifications_subtitle': {AppLanguage.uz: 'Super Admin barcha foydalanuvchilarga avtomatik notification yuborishni boshqaradi.', AppLanguage.ru: 'Super Admin управляет автоматическими уведомлениями всем пользователям.', AppLanguage.en: 'Super Admin manages automatic notifications for all users.'},
    'new_schedule': {AppLanguage.uz: 'Yangi reja', AppLanguage.ru: 'Новый график', AppLanguage.en: 'New schedule'},
    'scheduled_fill_required': {AppLanguage.uz: 'Sarlavha va matnni kiriting.', AppLanguage.ru: 'Введите заголовок и текст.', AppLanguage.en: 'Enter title and message.'},
    'scheduled_invalid_time': {AppLanguage.uz: 'Vaqtni HH:mm formatda tanlang.', AppLanguage.ru: 'Выберите время в формате HH:mm.', AppLanguage.en: 'Select time in HH:mm format.'},
    'scheduled_days_required': {AppLanguage.uz: 'Kamida bitta hafta kuni yoki aniq sana tanlang.', AppLanguage.ru: 'Выберите хотя бы один день недели или конкретную дату.', AppLanguage.en: 'Select at least one weekday or a specific date.'},
    'scheduled_saved': {AppLanguage.uz: 'Rejali bildirishnoma saqlandi.', AppLanguage.ru: 'Плановое уведомление сохранено.', AppLanguage.en: 'Scheduled notification saved.'},
    'scheduled_deleted': {AppLanguage.uz: 'Rejali bildirishnoma o‘chirildi.', AppLanguage.ru: 'Плановое уведомление удалено.', AppLanguage.en: 'Scheduled notification deleted.'},
    'send_now': {AppLanguage.uz: 'Hozir yuborish', AppLanguage.ru: 'Отправить сейчас', AppLanguage.en: 'Send now'},
    'sent_now': {AppLanguage.uz: 'Bildirishnoma hozir yuborildi.', AppLanguage.ru: 'Уведомление отправлено сейчас.', AppLanguage.en: 'Notification sent now.'},
    'every_day': {AppLanguage.uz: 'Har kuni', AppLanguage.ru: 'Каждый день', AppLanguage.en: 'Every day'},
    'specific_date': {AppLanguage.uz: 'Aniq sana', AppLanguage.ru: 'Конкретная дата', AppLanguage.en: 'Specific date'},
    'week_days': {AppLanguage.uz: 'Hafta kunlari', AppLanguage.ru: 'Дни недели', AppLanguage.en: 'Weekdays'},
    'active': {AppLanguage.uz: 'Active', AppLanguage.ru: 'Активно', AppLanguage.en: 'Active'},
    'inactive': {AppLanguage.uz: 'O‘chirilgan', AppLanguage.ru: 'Выключено', AppLanguage.en: 'Inactive'},

  };

  static String translate(String key, AppLanguage lang) => _values[key]?[lang] ?? _values[key]?[AppLanguage.uz] ?? key;
}
