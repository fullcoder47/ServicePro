import 'company_cleanup.dart';
import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_route.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../chat/chat_page.dart';

class SuperAdminCompaniesPage extends StatelessWidget {
  const SuperAdminCompaniesPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final companies = List<Company>.of(appState.companies)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return RefreshIndicator(
      onRefresh: () => appState.refreshAllForSuperAdmin(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _SuperHero(appState: appState),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.apartment_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tashkilotlar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: appState.loading ? null : () => _showCreateCompany(context),
                  icon: const Icon(Icons.add_business_rounded),
                  label: const LocalizedText('Yaratish'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (companies.isEmpty)
            SectionCard(child: Text(appState.tr('no_companies_yet')))
          else
            ...companies.map((company) => _CompanyListTile(appState: appState, company: company)),
        ],
      ),
    );
  }

  Future<void> _showCreateCompany(BuildContext context) async {
    final draft = await showDialog<({String name, String joinPassword})>(
      context: context,
      builder: (_) => _CreateCompanyDialog(appState: appState),
    );
    if (draft == null || !context.mounted) return;
    final success = await appState.createCompanyBySuperAdmin(
      name: draft.name,
      joinPassword: draft.joinPassword,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Tashkilot yaratildi.' : (appState.errorMessage ?? 'Tashkilot yaratilmadi.'))),
      );
    }
  }
}

class _CreateCompanyDialog extends StatefulWidget {
  const _CreateCompanyDialog({required this.appState});

  final AppState appState;

  @override
  State<_CreateCompanyDialog> createState() => _CreateCompanyDialogState();
}

class _CreateCompanyDialogState extends State<_CreateCompanyDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _closing = false;

  // A popped dialog stays mounted until its reverse transition finishes.
  // Its State owns these controllers for that entire lifetime.
  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _save() {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    if (_form.currentState?.validate() != true) return;
    _closing = true;
    Navigator.of(context).pop((
      name: _name.text.trim(),
      joinPassword: _code.text.trim(),
    ));
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? widget.appState.tr('fill_required')
      : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LocalizedText('Yangi tashkilot yaratish'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              validator: _required,
              decoration: InputDecoration(
                labelText: LocalizedText.translate(context, 'Tashkilot nomi'),
                prefixIcon: const Icon(Icons.apartment_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _code,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator: _required,
              decoration: InputDecoration(
                labelText: LocalizedText.translate(context, 'Kirish kodi'),
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
          _closing = true;
          Navigator.of(context).pop();
        },
        child: Text(widget.appState.tr('cancel')),
      ),
      FilledButton(onPressed: _save, child: const LocalizedText('Yaratish')),
    ],
  );
}

class _SuperHero extends StatelessWidget {
  const _SuperHero({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final adCount = appState.notifications
        .where((n) => n.notificationType == 'advertisement')
        .map((n) => n.adGroupId ?? n.id)
        .toSet()
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            const Color(0xFFFFD36A).withValues(alpha: .34),
            colors.surfaceContainerHighest,
          ],
        ),
        border: Border.all(color: const Color(0xFFE0B04B).withValues(alpha: .45)),
        boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: .08), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD36A).withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appState.tr('super_admin_panel'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(appState.tr('super_admin_panel_subtitle')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GoldChip(label: 'Tashkilot', value: '${appState.companies.length}'),
              _GoldChip(label: 'Userlar', value: '${appState.profiles.where((p) => p.role != UserRole.superAdmin).length}'),
              _GoldChip(label: 'Arizalar', value: '${appState.tickets.length}'),
              _GoldChip(label: 'Chatlar', value: '${appState.chatRooms.length}'),
              _GoldChip(label: 'Reklama', value: '$adCount'),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: appState.loading ? null : () => appState.refreshAllForSuperAdmin(),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(appState.tr('refresh_all')),
          ),
        ],
      ),
    );
  }
}

class _CompanyListTile extends StatelessWidget {
  const _CompanyListTile({required this.appState, required this.company});

  final AppState appState;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = appState.profiles.where((p) => p.companyId == company.id).length;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(smoothRoute<void>(_CompanyDetailsPage(appState: appState, company: company))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: colors.primaryContainer, child: Icon(Icons.apartment_rounded, color: colors.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text('Kod: ${company.joinPassword} • $count ta a’zo'),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyDetailsPage extends StatelessWidget {
  const _CompanyDetailsPage({required this.appState, required this.company});
  final AppState appState;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final companyProfiles = appState.profiles.where((p) => p.companyId == company.id).toList();
    final groupRooms = appState.companyGroupRooms(company.id);
    return Scaffold(
      appBar: AppBar(title: Text(company.name), actions: [
        IconButton(onPressed: () => _editCompany(context), icon: const Icon(Icons.edit_rounded)),
        IconButton(onPressed: () => _confirmDeleteCompany(context), icon: const Icon(Icons.delete_forever_rounded)),
      ]),
      body: RefreshIndicator(
        onRefresh: () => appState.refreshAllForSuperAdmin(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CompanyCleanupPanel(state:appState,company:company),
            const SizedBox(height:12),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocalizedText('Tashkilot ma’lumotlari', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _InfoRow(label: 'Nomi', value: company.name),
                _InfoRow(label: 'Kirish kodi', value: company.joinPassword),
                _InfoRow(label: 'Userlar', value: '${companyProfiles.length}'),
                _InfoRow(label: 'Arizalar', value: '${appState.companyTicketCount(company.id)}'),
                _InfoRow(label: 'Reklamalar', value: '${appState.companyAdvertisementCount(company.id)}'),
                _InfoRow(label: 'Chatlar', value: '${appState.companyChatRoomCount(company.id)}'),
              ]),
            ),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arizalar raqamlash', style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Eski arizalar va ularning raqamlari saqlanadi. '
                  'Yangi raqamlash davri alohida belgiga ega bo‘ladi va 1 dan boshlanadi.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _restartTicketNumbering(context),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Raqamlashni qayta boshlash'),
                ),
              ],
            )),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocalizedText('A’zolar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (companyProfiles.isEmpty) const LocalizedText('Hali a’zo yo‘q.') else ...companyProfiles.map((p) => _MemberTile(appState: appState, profile: p)),
              ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocalizedText('Umumiy chatlar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (groupRooms.isEmpty) const LocalizedText('Bu tashkilotda umumiy chat topilmadi.') else ...groupRooms.map((r) => _CompanyChatTile(appState: appState, room: r, companyName: company.name)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restartTicketNumbering(BuildContext context) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yangi raqamlash davri'),
        content: Text('“${company.name}” tashkilotining yangi arizalari '
          '1 dan raqamlanadi. Eski arizalar o‘chirilmaydi, '
          'eski raqamlar o‘zgarmaydi. Davom etasizmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tasdiqlash')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final nextNumber = await appState.client.rpc(
        'servicepro_reset_company_ticket_numbering',
        params: {'p_company_id': company.id});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Yangi davr boshlandi. Keyingi ariza: $nextNumber'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Raqamlashni qayta boshlash amalga oshmadi: '
          '${appState.friendlyError('$e')}'),
      ));
    }
  }

  Future<void> _editCompany(BuildContext context) async {
    final name = TextEditingController(text: company.name);
    final code = TextEditingController(text: company.joinPassword);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Kompaniyani tahrirlash'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Kompaniya nomi'))),
          const SizedBox(height: 10),
          TextField(controller: code, decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Kirish kodi'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('Saqlash')),
        ],
      ),
    );
    if (ok == true) {
      final success = await appState.updateCompany(company, name: name.text, joinPassword: code.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Kompaniya yangilandi.' : (appState.errorMessage ?? 'Yangilanmadi.'))));
      }
    }
    name.dispose();
    code.dispose();
  }

  Future<void> _confirmDeleteCompany(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Kompaniyani butunlay o‘chirish'),
        content: Text('${company.name} va unga bog‘langan user, ariza, reklama, chatlar databasedan o‘chadi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('Butunlay o‘chirish')),
        ],
      ),
    );
    if (ok != true) return;
    await appState.deleteCompany(company);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appState.errorMessage ?? 'Kompaniya o‘chirildi.')));
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.appState, required this.profile});
  final AppState appState;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ProfileAvatar(profile: profile),
      title: Text(profile.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${appState.tr(profile.role.dbValue)} • ${profile.phone.isEmpty ? 'Telefon yo‘q' : profile.phone}'),
      trailing: profile.role == UserRole.superAdmin ? null : IconButton(onPressed: () => _confirmDelete(context), icon: const Icon(Icons.delete_forever_rounded)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('User o‘chirilsinmi?'),
        content: Text('${profile.fullName} profili o‘chiriladi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('O‘chirish')),
        ],
      ),
    );
    if (ok == true) await appState.deleteProfile(profile);
  }
}

class _CompanyChatTile extends StatelessWidget {
  const _CompanyChatTile({required this.appState, required this.room, required this.companyName});
  final AppState appState;
  final ChatRoom room;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
        title: Text(room.title.isEmpty ? 'Umumiy chat' : room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${room.lastMessage ?? 'Xabar yo‘q'} • $companyName', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(spacing: 4, children: [
          IconButton.filledTonal(
            tooltip: LocalizedText.translate(context, 'Chatni ko‘rish'),
            onPressed: () => Navigator.of(context).push(smoothRoute<void>(ChatRoomPage(appState: appState, room: room, title: room.title.isEmpty ? '$companyName umumiy chat' : room.title))),
            icon: const Icon(Icons.visibility_rounded),
          ),
          IconButton.filledTonal(tooltip: LocalizedText.translate(context, 'Chatni o‘chirish'), onPressed: () => _confirmDelete(context), icon: const Icon(Icons.delete_forever_rounded)),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Umumiy chat o‘chirilsinmi?'),
        content: Text('$companyName umumiy chati va yozishmalari databasedan o‘chadi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('O‘chirish')),
        ],
      ),
    );
    if (ok != true) return;
    await appState.deleteChatRoomHard(room);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appState.errorMessage ?? 'Chat o‘chirildi.')));
  }
}

class SuperAdminUsersPage extends StatefulWidget {
  const SuperAdminUsersPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<SuperAdminUsersPage> createState() => _SuperAdminUsersPageState();
}

class _SuperAdminUsersPageState extends State<SuperAdminUsersPage> {
  String _companyFilter = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final companies = List<Company>.of(appState.companies)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selectedCompany = companies.any((company) => company.id == _companyFilter)
        ? _companyFilter : '';
    final query = _query.trim().toLowerCase();
    final users = appState.profiles.where((profile) {
      if (selectedCompany.isNotEmpty && profile.companyId != selectedCompany) return false;
      if (query.isEmpty) return true;
      final searchable = [
        profile.fullName,
        profile.email,
        profile.phone,
        profile.jobTitle,
        appState.companyById(profile.companyId)?.name ?? '',
        profile.role.label,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false)
      ..sort((a, b) {
        final companyA = appState.companyById(a.companyId)?.name ?? '';
        final companyB = appState.companyById(b.companyId)?.name ?? '';
        final byCompany = companyA.compareTo(companyB);
        return byCompany != 0 ? byCompany : a.fullName.compareTo(b.fullName);
      });
    return RefreshIndicator(
      onRefresh: () => appState.refreshAllForSuperAdmin(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: users.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tashkilotlardagi foydalanuvchilar (${users.length})',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Tashkilotni tanlang, foydalanuvchini toping va rol yoki lavozimini belgilang.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(selectedCompany),
                initialValue: selectedCompany,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tashkilot'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Barcha tashkilotlar')),
                  for (final company in companies)
                    DropdownMenuItem(value: company.id, child: Text(company.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _companyFilter = value ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Ism, telefon yoki lavozim bo‘yicha qidirish',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: appState.loading ? null : () => appState.refreshAllForSuperAdmin(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yangilash'),
              ),
            ]));
          }
          if (index == 1) {
            return users.isEmpty
                ? const SectionCard(child: Text('Tanlangan shartlarga mos foydalanuvchi yo‘q.'))
                : const SizedBox(height: 8);
          }
          return _UserAdminTile(appState: appState, profile: users[index - 2]);
        },
      ),
    );
  }
}

class _UserAdminTile extends StatelessWidget {
  const _UserAdminTile({required this.appState, required this.profile});
  final AppState appState;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final company = appState.companyById(profile.companyId);
    return SectionCard(
      child: ListTile(
        leading: ProfileAvatar(profile: profile),
        title: Text(profile.fullName.isEmpty ? profile.email : profile.fullName, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${appState.tr(profile.role.dbValue)} • ${company?.name ?? 'Global'}\n'
            '${profile.jobTitle.isEmpty ? 'Lavozim belgilanmagan' : profile.jobTitle} • '
            '${profile.phone.isEmpty ? 'Telefon yo‘q' : profile.phone}'),
        trailing: Wrap(spacing: 4, children: [
          if (profile.role != UserRole.superAdmin) IconButton.filledTonal(onPressed: () => _editProfile(context), icon: const Icon(Icons.edit_rounded)),
          if (profile.role == UserRole.superAdmin) const Icon(Icons.verified_user_rounded) else IconButton.filledTonal(onPressed: () => _confirmDeleteProfile(context), icon: const Icon(Icons.delete_forever_rounded)),
        ]),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final first = TextEditingController(text: profile.firstName);
    final last = TextEditingController(text: profile.lastName);
    final phone = TextEditingController(text: profile.phone);
    final jobTitle = TextEditingController(text: profile.jobTitle);
    var role = profile.role;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const LocalizedText('Profilni tahrirlash'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Tashkilot: ${appState.companyById(profile.companyId)?.name ?? 'Global'}'),
          const SizedBox(height: 10),
          TextField(controller: first, decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Ism'))),
          const SizedBox(height: 10),
          TextField(controller: last, decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Familiya'))),
          const SizedBox(height: 10),
          TextField(controller: phone, decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Telefon'))),
          const SizedBox(height: 10),
          TextField(
            controller: jobTitle,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Lavozimi',
              hintText: 'Masalan: Elektrik, Slesar, Menejer',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<UserRole>(
            initialValue: role,
            decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Rol')),
            items: const [UserRole.director, UserRole.admin, UserRole.worker, UserRole.user].map((r) => DropdownMenuItem(value: r, child: Text(appState.tr(r.dbValue)))).toList(),
            onChanged: (v) => setDialogState(() => role = v ?? role),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('Saqlash')),
        ],
      )),
    );
    if (ok == true) {
      final success = await appState.updateProfileAdmin(
        profile,
        role: role,
        firstName: first.text,
        lastName: last.text,
        phone: phone.text,
        jobTitle: jobTitle.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Foydalanuvchining roli va lavozimi saqlandi.'
              : (appState.errorMessage ?? 'O‘zgarishlarni saqlab bo‘lmadi.')),
        ));
      }
    }
    first.dispose();
    last.dispose();
    phone.dispose();
    jobTitle.dispose();
  }

  Future<void> _confirmDeleteProfile(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Userni butunlay o‘chirish'),
        content: Text('${profile.fullName} profili o‘chiriladi. Davom etasizmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(appState.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('O‘chirish')),
        ],
      ),
    );
    if (ok != true) return;
    await appState.deleteProfile(profile);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appState.errorMessage ?? 'User o‘chirildi.')));
  }
}

class _GoldChip extends StatelessWidget {
  const _GoldChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'), visualDensity: VisualDensity.compact);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: Text(value)),
        ]),
      );
}
