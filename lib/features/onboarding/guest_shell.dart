import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../tickets/ticket_create_page.dart';
import 'access_page.dart';

class GuestShell extends StatefulWidget {
  const GuestShell({super.key, required this.appState});
  final AppState appState;
  @override
  State<GuestShell> createState() => _GuestShellState();
}
class _GuestShellState extends State<GuestShell> {
  int index = 0;
  String t(String key) => widget.appState.tr(key);
  Future<void> access({bool organization = false, bool ticket = false}) async {
    // Capture navigator/state before authentication replaces this guest shell.
    final navigator = Navigator.of(context);
    final state = widget.appState;
    final result = await navigator.push<bool>(MaterialPageRoute(builder: (_) => AccessPage(appState: state, organization: organization)));
    if (result == true && ticket && navigator.mounted && state.currentProfile != null) {
      state.setSelectedIndex(1);
      await navigator.push(MaterialPageRoute(builder: (_) => TicketCreatePage(appState: state)));
    }
  }
  Widget card(IconData icon, String title, String detail, String button, VoidCallback action) {
    final colors = Theme.of(context).colorScheme;
    return Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 30, backgroundColor: colors.primaryContainer, child: Icon(icon, size: 30, color: colors.onPrimaryContainer)),
      const SizedBox(height: 20), Text(t(title), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10), Text(t(detail)), const SizedBox(height: 20),
      FilledButton.icon(onPressed: action, icon: const Icon(Icons.arrow_forward_rounded), label: Text(t(button))),
    ])));
  }
  @override
  Widget build(BuildContext context) {
    final state = widget.appState;
    final labels = ['dashboard', 'tickets', 'chat', 'profile'];
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      appBar: AppBar(title: Text(index == 0 ? 'ServicePro' : t(labels[index]))),
      body: Row(children: [
        if (desktop) _GuestSidebar(
          selectedIndex: index,
          labels: labels,
          translate: t,
          onSelect: (value) => setState(() => index = value),
        ),
        Expanded(child: Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 840 : double.infinity),
          child: ListView(padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 16, vertical: 16), children: [
        if (index == 0) ...[
          card(Icons.home_work_outlined, 'guest_welcome', 'guest_intro', 'create_ticket', () => access(ticket: true)),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.support_agent), title: Text(t('guest_support')), subtitle: Text(t('guest_support_help')),
            onTap: () => setState(() => index = 2)),
        ],
        if (index == 1) card(Icons.assignment_outlined, 'first_ticket', 'resident_help', 'create_ticket', () => access(ticket: true)),
        if (index == 2) ...[
          TextField(readOnly: true, onTap: () => access(), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('search_chat'))),
          const SizedBox(height: 16),
          card(Icons.forum_outlined, 'company_chat', 'guest_chat_help', 'complete_profile', () => access()),
        ],
        if (index == 3) ...[
          card(Icons.person_outline, 'resident_profile', 'resident_help', 'complete_profile', () => access()),
          Card(child: ListTile(leading: const Icon(Icons.apartment_rounded), title: Text(t('organization_access')), trailing: const Icon(Icons.chevron_right), onTap: () => access(organization: true))),
          const SizedBox(height: 16),
          DropdownButtonFormField<AppLanguage>(initialValue: state.authLanguage,
            decoration: InputDecoration(labelText: t('language'), prefixIcon: const Icon(Icons.language)),
            items: AppLanguage.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(),
            onChanged: (v) { if (v != null) state.setAuthLanguage(v); }),
          const SizedBox(height: 16),
          DropdownButtonFormField<ThemeMode>(initialValue: state.guestThemeMode,
            decoration: InputDecoration(labelText: t('theme'), prefixIcon: const Icon(Icons.brightness_6)),
            items: ThemeMode.values.map((v) => DropdownMenuItem(value: v, child: Text(t('theme_${v.name}')))).toList(),
            onChanged: (v) { if (v != null) state.setGuestTheme(v); }),
        ],
      ]),
        ))),
      ]),
      bottomNavigationBar: desktop ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: [
        NavigationDestination(icon: const Icon(Icons.home_outlined), label: t('dashboard')),
        NavigationDestination(icon: const Icon(Icons.assignment_outlined), label: t('tickets')),
        NavigationDestination(icon: const Icon(Icons.forum_outlined), label: t('chat')),
        NavigationDestination(icon: const Icon(Icons.person_outline), label: t('profile')),
      ]),
    );
  }
}


/// Tablet/laptop navigation; the original phone bottom bar stays untouched.
class _GuestSidebar extends StatelessWidget {
  const _GuestSidebar({required this.selectedIndex, required this.labels,
      required this.translate, required this.onSelect});
  final int selectedIndex;
  final List<String> labels;
  final String Function(String) translate;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const icons = [Icons.dashboard_rounded, Icons.assignment_rounded,
      Icons.forum_rounded, Icons.person_rounded];
    return SizedBox(
      width: 230,
      child: Material(
      color: colors.surfaceContainerLow,
      child: DecoratedBox(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
          child: Row(children: [
            Icon(Icons.home_work_rounded, color: colors.primary, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('ServicePro', maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19))),
          ]),
        ),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: labels.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: i == selectedIndex ? colors.primaryContainer : null,
              leading: Icon(icons[i], color: i == selectedIndex ? colors.onPrimaryContainer : null),
              title: Text(translate(labels[i]), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: i == selectedIndex ? FontWeight.w800 : FontWeight.w500)),
              onTap: () => onSelect(i),
            ),
          ),
        )),
      ])))),
    );
  }
}
