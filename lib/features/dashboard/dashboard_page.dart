import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/export/servicepro_excel_export.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../team/team_section.dart';
import '../tickets/ticket_create_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.appState});
  final AppState appState;
  String t(String key) => appState.tr(key);
  @override
  Widget build(BuildContext context) {
    final me = appState.currentProfile!;
    final colors = Theme.of(context).colorScheme;
    final tickets = appState.visibleTickets();
    final ads = appState.advertisementThreads(receivedOnly: true);
    final done = tickets.where((t) => t.status == TicketStatus.completed || t.status == TicketStatus.closed).length;
    final manager = [UserRole.director, UserRole.admin, UserRole.superAdmin].contains(me.role);
    return RefreshIndicator(
      onRefresh: () async { await appState.refreshTickets(); await appState.refreshTeamStats(); await appState.refreshNotifications(); },
      child: ListView(
        // Keep the last card reachable when the phone's glass bar overlays it.
        padding: EdgeInsets.fromLTRB(18, 16, 18, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.primaryContainer, colors.secondaryContainer]), borderRadius: BorderRadius.circular(28)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(appState.companyById(me.companyId)?.name ?? 'ServicePro', style: Theme.of(context).textTheme.labelLarge)), ProfileAvatar(profile: me, radius: 23)]),
            const SizedBox(height: 18),
            Text(me.fullName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(t(me.role.dbValue), style: TextStyle(color: colors.onPrimaryContainer)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketCreatePage(appState: appState))), icon: const Icon(Icons.add), label: Text(t('create_ticket'))),
          ])),
        const SizedBox(height: 22),
        Row(children: [Expanded(child: Text(t('tickets'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), Text('$done / ${tickets.length}', style: Theme.of(context).textTheme.titleMedium)]),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: tickets.isEmpty ? 0 : done / tickets.length), duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 550), builder: (_, value, __) => LinearProgressIndicator(value: value, minHeight: 8, borderRadius: BorderRadius.circular(9))),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 930 ? 4 : (constraints.maxWidth < 310 ? 1 : 2);
          return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final status in TicketStatus.values)
            SizedBox(width: (constraints.maxWidth - (columns - 1) * 10) / columns, child: Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_icon(status), color: status.color(colors)), const SizedBox(height: 10),
              Text('${tickets.where((v) => v.status == status).length}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(t('ticket_${status.dbValue}')),
            ])))),
        ]);
        }),
        if (manager && me.role != UserRole.director) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: () => _export(context), icon: const Icon(Icons.download_outlined), label: Text(t('export_excel'))),
        ],
        if (ads.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(children: [const Icon(Icons.campaign_outlined), const SizedBox(width: 8), Text(t('ads'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 12),
          for (final ad in ads.take(5))
            TweenAnimationBuilder<double>(key: ValueKey(ad.id), tween: Tween(begin: 0, end: 1), duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400), builder: (context, value, child) => Opacity(opacity: value, child: child), child: Card(clipBehavior: Clip.antiAlias, child: InkWell(
              onTap: () => showDialog<void>(context: context, builder: (_) => MediaViewerDialog(title: ad.title, body: ad.body, mediaUrls: ad.mediaUrls, mediaTypes: ad.mediaTypes, actionUrl: ad.actionUrl, actionLabel: ad.actionLabel)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ad.mediaUrls.isNotEmpty && (ad.mediaTypes.isEmpty || ad.mediaTypes.first != 'video'))
                  Image.network(ad.mediaUrls.first, width: double.infinity, height: 170, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: Icon(Icons.image_outlined)))),
                Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(ad.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (ad.actionUrl != null && ad.actionUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () => openAdvertisementLink(context, ad.actionUrl!),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(ad.actionLabel.trim().isEmpty ? 'Batafsil' : ad.actionLabel,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ])),
              ]),
            ))),
        ],
        const SizedBox(height: 24), TeamSection(appState: appState),
      ]),
    );
  }
  IconData _icon(TicketStatus status) => switch(status) {
    TicketStatus.newTicket => Icons.fiber_new_outlined,
    TicketStatus.inProgress => Icons.pending_actions,
    TicketStatus.completed => Icons.task_alt,
    TicketStatus.closed => Icons.done_all,
  };
  Future<void> _export(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      final exportedFile = await ServiceProExcelExport.tickets(appState);
      if (!context.mounted) return;
      await Share.shareXFiles([exportedFile],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    }
    catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('error_unknown')))); }
  }
}
