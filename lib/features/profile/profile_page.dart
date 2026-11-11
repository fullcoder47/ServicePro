import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../onboarding/access_page.dart';
import 'devices_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Telegram havolalarini shu yerga o'zingiz kiritasiz.
  static const String _telegramChannelUrl = 'https://t.me/AppServicePro';
  static const String _telegramBotUrl = '@svssvsxcvsfbot';

  late final TextEditingController firstNameController;
  late final TextEditingController lastNameController;
  late final TextEditingController phoneController;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.appState.currentProfile!;
    firstNameController = TextEditingController(text: profile.firstName);
    lastNameController = TextEditingController(text: profile.lastName);
    phoneController = TextEditingController(text: profile.phone);
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.appState.currentProfile!;
    final company = widget.appState.companyById(profile.companyId);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (profile.role == UserRole.user)
          Card(child: ListTile(
            leading: const Icon(Icons.apartment_rounded),
            title: Text(widget.appState.tr('organization_access')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccessPage(appState: widget.appState, organization: true))),
          )),
        SectionCard(
          child: Row(
            children: [
              Stack(
                children: [
                  ProfileAvatar(profile: profile, radius: 34),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _pickAvatar,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle),
                        child: Icon(Icons.camera_alt_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(widget.appState.tr(profile.role.dbValue)),
                    Text(company?.name ?? widget.appState.tr('profile_global_panel')),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.appState.tr('profile'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                  controller: firstNameController,
                  decoration: InputDecoration(
                      labelText: widget.appState.tr('first_name'),
                      prefixIcon: Icon(Icons.person_rounded))),
              const SizedBox(height: 12),
              TextField(
                  controller: lastNameController,
                  decoration: InputDecoration(
                      labelText: widget.appState.tr('last_name'),
                      prefixIcon: Icon(Icons.badge_rounded))),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                      labelText: widget.appState.tr('phone'),
                      prefixIcon: Icon(Icons.phone_rounded))),
              const SizedBox(height: 12),
              TextField(
                  enabled: false,
                  decoration: InputDecoration(
                      labelText: 'Email/Login',
                      prefixIcon: const Icon(Icons.email_rounded),
                      hintText: profile.email)),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(widget.appState.tr('save'))),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.appState.tr('settings'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppLanguage>(
                initialValue: profile.language,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.language_rounded),
                    labelText: widget.appState.tr('language')),
                items: AppLanguage.values
                    .map((item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => profile.language = value);
                  widget.appState.updateProfile(profile);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemeMode>(
                initialValue: profile.themeMode,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.dark_mode_rounded),
                    labelText: widget.appState.tr('theme')),
                items: [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: Text(widget.appState.tr('system'))),
                  DropdownMenuItem(
                      value: ThemeMode.light, child: Text(widget.appState.tr('light'))),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text(widget.appState.tr('dark'))),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => profile.themeMode = value);
                  widget.appState.updateProfile(profile);
                },
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DevicesPage(appState: widget.appState)),
                ),
                icon: const Icon(Icons.devices_rounded),
                label: const Text('Kirilgan qurilmalar va xavfsizlik'),
              ),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.appState.tr('information'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _telegramButton(
                icon: Icons.send_rounded,
                label: 'Telegram kanalimizga o‘tish',
                url: _telegramChannelUrl,
              ),
              const SizedBox(height: 12),
              _telegramButton(
                icon: Icons.login_rounded,
                label: 'Telegram botimizga o‘tish',
                url: _telegramBotUrl,
              ),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                  onPressed: _resetPassword,
                  icon: const Icon(Icons.lock_reset_rounded),
                  label: Text(widget.appState.tr('reset_password'))),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded),
                label: Text(widget.appState.tr('logout')),
              ),
              if (profile.role == UserRole.superAdmin) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _confirmGlobalLogout,
                  icon: const Icon(Icons.phonelink_erase_rounded),
                  label: const Text('Barcha qurilmalardan chiqish'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _deletingAccount ? null : _confirmDeleteAccount,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: _deletingAccount
                    ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_forever_rounded),
                label: Text(widget.appState.tr('delete_account')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _telegramButton({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return FilledButton.icon(
      onPressed: () => _openTelegramLink(url),
      icon: Icon(icon, size: 25),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFD2B9FA),
        foregroundColor: const Color(0xFF302342),
        minimumSize: const Size.fromHeight(64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }

  Future<void> _openTelegramLink(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme != 'https' || uri.host != 't.me') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Telegram havolasini avval kodga kiriting.'),
      ));
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Telegram havolasini ochib bo‘lmadi.'),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Telegram havolasini ochib bo‘lmadi.'),
      ));
    }
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final picked = PickedAttachment(
        name: file.name, bytes: await file.readAsBytes(), isVideo: false);
    final ok = await widget.appState.uploadProfileAvatar(picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? widget.appState.tr('avatar_updated')
              : (widget.appState.errorMessage ?? widget.appState.tr('avatar_failed')))),
    );
    if (ok) setState(() {});
  }

  Future<void> _save() async {
    final profile = widget.appState.currentProfile!;
    profile.firstName = firstNameController.text.trim();
    profile.lastName = lastNameController.text.trim();
    profile.phone = phoneController.text.trim();
    await widget.appState.updateProfile(profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.appState.errorMessage ?? widget.appState.tr('profile_saved'),
        ),
      ),
    );
  }

  Future<void> _resetPassword() async {
    final ok = await widget.appState.sendPasswordReset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? widget.appState.tr('reset_sent')
              : (widget.appState.errorMessage ?? widget.appState.tr('reset_failed')))),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.appState.tr('logout_title')),
        content: Text(widget.appState.tr('logout_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.appState.tr('no'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.appState.tr('yes'))),
        ],
      ),
    );
    if (result == true) widget.appState.logout();
  }

  Future<void> _confirmGlobalLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Barcha qurilmalardan chiqish'),
        content: const Text(
          'Super admin hisobi barcha telefon va kompyuterlardan chiqariladi. '
              'Qayta kirish uchun parol kerak bo‘ladi. Davom etasizmi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Barcha sessiyalarni tugatish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.appState.logout(allDevices: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Sessiyalarni tugatib bo‘lmadi. Internetni tekshirib, qayta urinib ko‘ring.',
        )),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final profile = widget.appState.currentProfile;
    if (profile == null || _deletingAccount) return;
    if (profile.role != UserRole.user) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(widget.appState.tr('delete_account_title')),
          content: Text(widget.appState.tr('delete_account_organization')),
          actions: [TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(widget.appState.tr('close')),
          )],
        ),
      );
      return;
    }

    var understood = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, updateDialog) => AlertDialog(
          title: Text(widget.appState.tr('delete_account_title')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.appState.tr('delete_account_warning')),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: understood,
              onChanged: (value) => updateDialog(() => understood = value ?? false),
              title: Text(widget.appState.tr('delete_account_agree')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(widget.appState.tr('cancel')),
            ),
            FilledButton.icon(
              onPressed: understood ? () => Navigator.pop(dialog, true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialog).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(widget.appState.tr('delete_account')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    final deleted = await widget.appState.deleteMyAccount();
    if (!mounted) return;
    setState(() => _deletingAccount = false);
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.appState.errorMessage ?? widget.appState.tr('delete_account_failed')),
      ));
    }
  }
}