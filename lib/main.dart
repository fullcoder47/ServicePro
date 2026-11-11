import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:servicepro/core/notifications/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    await NotificationService.initialize();
  }

  // The background web worker reopens the installed PWA with these safe
  // notification identifiers; the existing NotificationRouter handles them.
  if (kIsWeb && Uri.base.queryParameters['servicepro_push'] == '1') {
    final params = Uri.base.queryParameters;
    NotificationService.openData({
      for (final key in const [
        'notification_id', 'profile_id', 'type', 'ticket_id',
        'chat_room_id', 'chat_message_id', 'ad_group_id',
      ]) key: params[key] ?? '',
    });
  }
  runApp(const ServiceProApp());
}
