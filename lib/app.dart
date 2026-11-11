import 'core/notifications/notification_router.dart';
import 'core/widgets/localized_text.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/app_state.dart';
import 'data/models.dart';
import 'features/onboarding/guest_shell.dart';
import 'features/auth/splash_page.dart';
import 'features/offline/offline_page.dart';
import 'features/shell/home_shell.dart';
import 'features/billing/billing_page.dart';
import 'core/updates/mandatory_update_gate.dart';

class ServiceProApp extends StatefulWidget {
  const ServiceProApp({super.key}) : _providedAppState = null;

  /// Allows widget tests to use inert state without starting backend services.
  const ServiceProApp.forTesting({super.key, required AppState appState})
      : _providedAppState = appState;

  final AppState? _providedAppState;

  @override
  State<ServiceProApp> createState() => _ServiceProAppState();
}

class _ServiceProAppState extends State<ServiceProApp> {
  late final AppState appState;
  // One navigator for this app instance, independent of theme and account.
  final _navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'servicepro-root-navigator',
  );
  UserRole? _themeRole;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  @override
  void initState() {
    super.initState();
    appState = widget._providedAppState ?? AppState();
  }

  @override
  void dispose() {
    if (widget._providedAppState == null) appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final role = appState.currentProfile?.role;
        // Chat/read updates also notify this builder. Reuse both palettes until
        // the role changes instead of generating ColorSchemes on every event.
        if (_lightTheme == null || _themeRole != role) {
          _themeRole = role;
          _lightTheme = AppTheme.forRole(role, Brightness.light);
          _darkTheme = AppTheme.forRole(role, Brightness.dark);
        }
        return AppLanguageScope(
          language: appState.currentProfile?.language ?? appState.authLanguage,
          child: MaterialApp(
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'ServicePro',
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: appState.themeMode,
            // Block all routes, dialogs, desktop sidebar and bottom navigation.
            // Only the billing feature and Super Admin control this lock.
            builder: (context, child) => MandatoryUpdateGate(
              enabled: widget._providedAppState == null && appState.isConfigured,
              child: BillingAccessGate(
                appState: appState,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: !appState.isConfigured
                ? const _SupabaseSetupPage()
                : (!appState.isOnline && appState.networkChecked)
                    ? OfflinePage(appState: appState)
                    : !appState.appReady
                        ? const SplashPage()
                        : appState.currentProfile == null
                            ? GuestShell(appState: appState)
                            : NotificationRouter(
                                key: ValueKey((appState.currentProfile!.id, role)),
                                appState: appState,
                                child: HomeShell(appState: appState),
                              ),
          ),
        );
      },
    );
  }
}

class _SupabaseSetupPage extends StatelessWidget {
  const _SupabaseSetupPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText('Supabase sozlash kerak', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text('Backend real ishlashi uchun Supabase URL va ANON KEY ni dart-define orqali yuboring.'),
                  const SizedBox(height: 12),
                  SelectableText(
                    'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  const Text('SQL fayl: supabase/servicepro_schema.sql ni Supabase SQL Editor’da ishga tushiring.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
