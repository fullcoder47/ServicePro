import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_web_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Notification payload is displayed by Android/iOS. Do not display it twice.
}

class NotificationService {
  NotificationService._();
  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static const _windowsChannel = MethodChannel('servicepro/windows_window');
  static bool get webPushConfigured => kIsWeb && FirebaseWebConfig.canRegisterPush;
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _localReady=false, _firebaseReady=false;
  static Future<void>? _initializing;
  static Future<void>? _registering;
  static Timer? _retry;
  static bool _observing = false;
  static int _accountGeneration = 0;
  static final _lifecycle = _NotificationLifecycle();
  static String? _profileId;
  static String? activeChatRoomId;
  static final pendingOpen=ValueNotifier<Map<String,String>?>(null);
  static final _seen=<String,DateTime>{};
  static final _muted=<String,DateTime>{};
  static const _channel=AndroidNotificationChannel('servicepro_alerts_v2','ServicePro bildirishnomalari',
    description:'Ariza, chat va reklama bildirishnomalari',importance:Importance.high,
    playSound:true,sound:RawResourceAndroidNotificationSound('servicepro_sound'));

  static Future<void> initialize() => _initializing ??= _initialize().catchError((Object e) { debugPrint('Notification initialization unavailable: $e'); }).whenComplete(()=>_initializing=null);
  static Future<void> _initialize() async {
    // Web Push is opt-in: initialize Firebase here but request browser
    // permission ONLY from a user tap (required by iOS Home Screen apps).
    if (kIsWeb) {
      if (_firebaseReady || !FirebaseWebConfig.canRegisterPush) return;
      try {
        await Firebase.initializeApp(options: FirebaseWebConfig.options!);
        FirebaseMessaging.onMessage.listen((message) {
          // Supabase Realtime already updates the in-app inbox. Avoid a
          // duplicate foreground OS notification from the same event.
          final data = message.data;
          if (data['notification_id'] == null) return;
        });
        FirebaseMessaging.instance.onTokenRefresh.listen(_upsertToken);
        _firebaseReady = true;
      } catch (e) {
        debugPrint('Web push initialization unavailable: $e');
      }
      return;
    }
    // Windows uses the existing Supabase notifications stream and native toast
    // notifications. Firebase Messaging does not provide Windows FCM tokens.
    if (!_isAndroid && !_isIOS && !_isWindows) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(_lifecycle);
      _observing = true;
    }
    if(!_localReady) {
      await _local.initialize(settings: const InitializationSettings(
        android:AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:DarwinInitializationSettings(requestAlertPermission:false,requestBadgePermission:false,requestSoundPermission:false),
        windows:WindowsInitializationSettings(
          appName:'ServicePro',
          appUserModelId:'fullcoder47.ServicePro',
          guid:'10e407c0-c655-465d-a470-9201087f70b8',
        )),
        onDidReceiveNotificationResponse:(response)=>_openPayload(response.payload));
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
      final launch=await _local.getNotificationAppLaunchDetails();
      if(launch?.didNotificationLaunchApp==true) _openPayload(launch?.notificationResponse?.payload);
      _localReady=true;
    }
    if (_isWindows) return;
    if(_firebaseReady) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert:false,badge:true,sound:false);
      FirebaseMessaging.onMessage.listen(showLocalNotification);
      FirebaseMessaging.onMessageOpenedApp.listen((message)=>openData(message.data));
      FirebaseMessaging.instance.onTokenRefresh.listen((token)=>_upsertToken(token));
      _firebaseReady=true;
      final initial=await FirebaseMessaging.instance.getInitialMessage();
      if(initial!=null) openData(initial.data);
    } catch(e) { debugPrint('Push initialization unavailable: $e'); }
  }
  static void _openPayload(String? payload) {
    if(payload==null) return;
    try { final data=jsonDecode(payload); if(data is Map) openData(data); } catch(_) {}
  }
  static void openData(Map data) {
    pendingOpen.value=data.map((key,value)=>MapEntry('$key','$value'));
    // Bring a tray-hidden desktop window back before the notification router
    // navigates to the selected chat, ticket or announcement.
    if (_isWindows) {
      unawaited(_windowsChannel.invokeMethod<void>('restore').catchError((Object e) {
        debugPrint('Windows notification window restore unavailable: $e');
      }));
    }
  }
  static void setRoomMute(String roomId,DateTime? until) {
    if(until==null) { _muted.remove(roomId); } else { _muted[roomId]=until; }
  }
  static void clearAccount({bool clearPending=false}) {
    _accountGeneration++;
    _retry?.cancel(); _retry = null;
    _profileId=null;_muted.clear();_seen.clear();activeChatRoomId=null;if(clearPending) pendingOpen.value=null;
    if (_localReady) unawaited(_cancelLocalNotifications());
  }
  static Future<void> _cancelLocalNotifications() async {
    try {
      await _local.cancelAll();
    } catch (e) {
      // Account cleanup must complete even if the native plugin is unavailable.
      debugPrint('Local notification cleanup unavailable: $e');
    }
  }
  static Future<void> registerCurrentDevice() => _registering ??=
      _registerDevice().whenComplete(() => _registering = null);

  /// Called directly by the user pressing the notification permission button.
  /// Never show the permission prompt automatically on iOS or web.
  static Future<bool> enableWebPush() async {
    if (!webPushConfigured || !_firebaseReady) return false;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      // Keep this as the first await: Safari requires a direct user gesture.
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (!_permissionGranted(settings.authorizationStatus)) return false;
      final token = await _getToken();
      if (token == null || client.auth.currentUser?.id != userId) return false;
      await client.rpc('servicepro_register_device', params: {
        'p_token': token, 'p_platform': 'web',
      });
      _profileId = userId;
      _retry?.cancel();
      _retry = null;
      return true;
    } catch (e) {
      debugPrint('Web push permission/registration unavailable: $e');
      return false;
    }
  }

  static bool _permissionGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  static Future<String?> _getToken() => kIsWeb
      ? FirebaseMessaging.instance.getToken(vapidKey: FirebaseWebConfig.vapidKey)
      : FirebaseMessaging.instance.getToken();

  static Future<void> _registerDevice() async {
    if (_isWindows) {
      // Desktop notifications are delivered by the authenticated Supabase
      // stream, not by Firebase device-token registration.
      final client = Supabase.instance.client;
      final id = client.auth.currentUser?.id;
      _profileId = id;
      await initialize();
      if (id != null) {
        try {
          final prefs = await client.from('chat_preferences')
              .select('room_id,muted_until').eq('profile_id', id);
          if (client.auth.currentUser?.id != id) return;
          _muted.clear();
          for (final row in prefs) {
            setRoomMute('${row['room_id']}', DateTime.tryParse('${row['muted_until']}'));
          }
        } catch (_) { /* Optional preferences must not block desktop alerts. */ }
      }
      return;
    }
    if (!_isAndroid && !_isIOS && !kIsWeb) return;
    if (kIsWeb && !webPushConfigured) return;
    final generation = _accountGeneration;
    try {
      final client = Supabase.instance.client;
      final id = client.auth.currentUser?.id;
      _profileId = id;
      if (id == null) return;
      await initialize();
      if (!_firebaseReady) throw StateError('push_not_initialized');
      if (kIsWeb) {
        // Never ask permission in a background profile-loading task.
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (!_permissionGranted(settings.authorizationStatus)) return;
      }
      if (_isIOS && await FirebaseMessaging.instance.getAPNSToken() == null) {
        throw StateError('apns_not_ready');
      }
      final token = await _getToken();
      if (generation != _accountGeneration || client.auth.currentUser?.id != id) return;
      if (token == null) throw StateError('token_not_ready');
      // Registration is independent of optional chat settings loading.
      await client.rpc('servicepro_register_device', params: {
        'p_token': token, 'p_platform': kIsWeb ? 'web' : (_isIOS ? 'ios' : 'android'),
      });
      _retry?.cancel(); _retry = null;
      try {
        final prefs = await client.from('chat_preferences').select('room_id,muted_until').eq('profile_id', id);
        if (generation != _accountGeneration || client.auth.currentUser?.id != id) return;
        _muted.clear();
        for (final row in prefs) {
          setRoomMute('${row['room_id']}', DateTime.tryParse('${row['muted_until']}'));
        }
      } catch (_) { /* Settings failure must not prevent token registration. */ }
    } catch (e) {
      debugPrint('Device registration unavailable: $e');
      if (generation == _accountGeneration) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 30), () {
          if (_profileId != null) unawaited(registerCurrentDevice());
        });
      }
    }
  }
  static Future<void> unregisterCurrentDevice() async {
    try {
      final client=Supabase.instance.client;
      final id=client.auth.currentUser?.id;
      final token=_firebaseReady?await _getToken():null;
      if(id!=null && token!=null) await client.from('device_tokens').update({'is_active':false}).eq('profile_id',id).eq('token',token);
    } catch(_) {}
  }
  static Future<void> _upsertToken(String token) async {
    try {
      final client=Supabase.instance.client;
      if(client.auth.currentUser==null) return;
      await client.rpc('servicepro_register_device',params:{'p_token':token,'p_platform':kIsWeb?'web':(_isIOS?'ios':'android')});
    } catch(e) { debugPrint('Token registration unavailable: $e'); }
  }
  static Future<void> showLocalNotification(RemoteMessage message) async {
    final data=message.data.map((key,value)=>MapEntry(key,'$value'));
    await showPlainLocalNotification(title:message.notification?.title??data['title']??'ServicePro',
      body:message.notification?.body??data['body']??'',data:data);
  }
  static Future<void> showPlainLocalNotification({required String title,required String body,Map<String,String>? data}) async {
    if (!_isAndroid && !_isIOS && !_isWindows) return;
    // Android/iOS background pushes are displayed by the OS. Windows still
    // needs to show local toasts while the window is hidden in the tray.
    if (!_isWindows && WidgetsBinding.instance.lifecycleState!=AppLifecycleState.resumed) return;
    final payload=data??<String,String>{};
    final recipient=payload['profile_id'];
    if(recipient!=null && recipient.isNotEmpty && recipient!=_profileId) return;
    final room=payload['chat_room_id'];
    if(room!=null && room.isNotEmpty && (_muted[room]?.isAfter(DateTime.now())??false)) return;
    final key=(payload['notification_id']?.isNotEmpty == true ? payload['notification_id'] : null) ?? '${payload['type']}:${payload['chat_message_id']??payload['ticket_id']??''}:$title:$body';
    _seen.removeWhere((_,time)=>DateTime.now().difference(time)>const Duration(hours:12));
    if(_seen.containsKey(key)) return;
    _seen[key]=DateTime.now();
    try {
      if(!_localReady) await initialize();
      var id=0;
      for(final unit in key.codeUnits) { id=(id*31+unit)&0x7fffffff; }
      await _local.show(id: id, title: title, body: body,
        notificationDetails: const NotificationDetails(
        android:AndroidNotificationDetails('servicepro_alerts_v2','ServicePro bildirishnomalari',
          icon:'ic_notification',
          importance:Importance.high,priority:Priority.high,playSound:true,
          sound:RawResourceAndroidNotificationSound('servicepro_sound')),
        iOS:DarwinNotificationDetails(presentAlert:true,presentSound:true,presentBadge:true),
        windows:WindowsNotificationDetails()),payload:jsonEncode(payload));
    } catch(e) { _seen.remove(key);debugPrint('Local notification unavailable: $e'); }
  }
}

class _NotificationLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && NotificationService._profileId != null) {
      unawaited(NotificationService.registerCurrentDevice());
    }
  }
}
