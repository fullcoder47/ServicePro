import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks an Android-only public minimum build number without touching
/// authentication, billing, navigation or Windows releases.
class MandatoryUpdateGate extends StatefulWidget {
  const MandatoryUpdateGate({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate>
    with WidgetsBindingObserver {
  static const _cacheKey = 'servicepro_android_min_build_v1';
  static final _playStoreUrl = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.fullcoder.servicepro',
  );

  bool _blocked = false;
  bool _checking = false;
  int _installedBuild = 0;
  int _minimumBuild = 0;
  DateTime? _lastCheck;

  bool get _isAndroid => widget.enabled && !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkVersion());
    });
  }

  @override
  void didUpdateWidget(covariant MandatoryUpdateGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) unawaited(_checkVersion());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkVersion());
  }

  Future<void> _checkVersion() async {
    if (!_isAndroid || _checking) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(seconds: 15)) return;
    _lastCheck = now;
    _checking = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber);
      if (installed == null) return;

      // Keep enforcing a known minimum when the network is temporarily down.
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(_cacheKey) ?? 0;
      _applyMinimum(cached, installed);

      final row = await Supabase.instance.client
          .from('servicepro_update_policy')
          .select('min_build')
          .eq('platform', 'android')
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (!mounted || row == null) return;

      final minimum = (row['min_build'] as num?)?.toInt();
      if (minimum == null || minimum < 0) return;
      _applyMinimum(minimum, installed);
      await prefs.setInt(_cacheKey, minimum);
    } catch (_) {
      // If the table has not been created or the server is down, the cached
      // policy remains in effect; an ordinary app launch must not crash.
    } finally {
      _checking = false;
    }
  }

  void _applyMinimum(int minimum, int installed) {
    if (!mounted) return;
    final blocked = installed < minimum;
    if (_blocked == blocked && _installedBuild == installed &&
        _minimumBuild == minimum) {
      return;
    }
    setState(() {
      _blocked = blocked;
      _installedBuild = installed;
      _minimumBuild = minimum;
    });
  }

  Future<void> _openPlayStore() async {
    try {
      if (await launchUrl(_playStoreUrl, mode: LaunchMode.externalApplication)) return;
    } catch (_) { /* The user can still open Google Play manually. */ }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Google Play ochilmadi. ServicePro ilovasini Play Marketdan yangilang.')),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked || !_isAndroid) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: true, child: widget.child),
      Material(
        color: scheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 92, height: 92,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.system_update_rounded, size: 48, color: scheme.primary),
                  ),
                  const SizedBox(height: 28),
                  Text('ServicePro yangilanishi kerak',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Text(
                    'Ilovadan foydalanishni davom ettirish uchun yangi versiyani Play Marketdan o‘rnating.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text('O‘rnatilgan: $_installedBuild  •  Talab etiladi: $_minimumBuild',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  const SizedBox(height: 28),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: _openPlayStore,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Play Marketda yangilash'),
                  )),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () {
                      _lastCheck = null;
                      unawaited(_checkVersion());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Qayta tekshirish'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
