import '../../core/notifications/notification_inbox.dart';
import '../team/team_page.dart';
import '../../core/widgets/localized_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/export/servicepro_excel_export.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../ads/advertisement_page.dart';
import '../billing/billing_page.dart';
import '../chat/chat_page.dart';
import '../dashboard/dashboard_page.dart';
import '../profile/profile_page.dart';
import '../super_admin/super_admin_page.dart';
import '../super_admin/scheduled_notifications_page.dart';
import '../subscribers/subscribers_page.dart';
import '../subscribers/my_account_page.dart';
import '../subscribers/billing_imports_page.dart';
import '../smartcall/smartcall_reports_page.dart';
import '../tickets/tickets_page.dart';
import '../work_activity/work_activity_page.dart';
import 'package:share_plus/share_plus.dart';


class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.appState});

  static bool _exportInProgress = false;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final profile = appState.currentProfile!;
    final allItems = _itemsFor(profile.role);
    final navItems = _bottomItemsFor(profile.role);
    final pages = _pagesFor(profile.role);
    final index = appState.selectedIndex.clamp(0, pages.length - 1);
    final currentLabel = allItems[index].label;
    final navIndexRaw = navItems.indexWhere((item) => item.label == currentLabel);
    final navIndex = navIndexRaw < 0 ? 0 : navIndexRaw;
    final drawerItems = allItems
        .where((item) => navItems.every((bottom) => bottom.label != item.label))
        .toList(growable: false);
    // Width-based, rather than platform-based: Windows snapped to a narrow
    // window continues to use the same navigation as an Android phone.
    final isDesktop = MediaQuery.sizeOf(context).width >= 980;
    final platform = Theme.of(context).platform;
    final isPhone = !isDesktop &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS) &&
        MediaQuery.sizeOf(context).shortestSide < 600;

    void selectPage(String label) {
      final pageIndex = allItems.indexWhere((item) => item.label == label);
      appState.setSelectedIndex(pageIndex < 0 ? 0 : pageIndex);
      if (label == 'dashboard' || label == 'ads') {
        unawaited(appState.markAdvertisementNotificationsRead());
      }
      if (label == 'tickets') {
        unawaited(appState.markTicketNotificationsRead());
      }
    }

    // Nested horizontal lists (filters, media galleries, chat replies) win
    // their own gestures; otherwise a quick horizontal swipe changes tabs.
    Widget withSwipeNavigation(Widget child) => isDesktop
        ? child
        : GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (navIndexRaw < 0 || velocity.abs() < 420) return;
              final next = navIndex + (velocity < 0 ? 1 : -1);
              if (next >= 0 && next < navItems.length) {
                selectPage(navItems[next].label);
              }
            },
            child: child,
          );

    return Scaffold(
      extendBody: isPhone,
      endDrawer: isDesktop || drawerItems.isEmpty
          ? null
          : _SideMenu(appState: appState, items: allItems, drawerItems: drawerItems),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appState.tr(allItems[index].label), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${appState.tr(profile.role.dbValue)} • ${appState.companyById(profile.companyId)?.name ?? appState.tr('all_companies')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if ((currentLabel == 'tickets' || currentLabel == 'work_activity') &&
              (profile.role == UserRole.superAdmin ||
                  profile.role == UserRole.director ||
                  profile.role == UserRole.admin))
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: appState.tr('export_excel'),
                onPressed: appState.loading
                    ? null
                    : () => _exportExcel(buttonContext,
                        isWork: currentLabel == 'work_activity'),
                icon: const Icon(Icons.download_rounded),
              ),
            ),
          IconButton(
            tooltip: appState.tr('notifications'),
            onPressed: () => _showNotifications(context),
            icon: Badge(
              isLabelVisible: appState.unreadNotificationCount>0,
              label:Text(appState.unreadNotificationCount>99?'99+':'${appState.unreadNotificationCount}'),
              child: const Icon(Icons.notifications_rounded),
            ),
          ),
          if (!isDesktop && drawerItems.isNotEmpty)
            Builder(
              builder: (context) => IconButton(
                tooltip: LocalizedText.translate(context, 'Menyu'),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
        ],
      ),
      body: SafeArea(
        // Let phone content paint beneath the floating, translucent bar.
        // The bottom navigation has its own SafeArea for system gestures.
        bottom: !isPhone,
        child: isDesktop
            ? Row(
                children: [
                  _DesktopSidebar(
                    appState: appState,
                    profile: profile,
                    items: allItems,
                    currentIndex: index,
                    onSelect: selectPage,
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: currentLabel == 'chat' || currentLabel == 'profile' ? 940 : 1240),
                        child: SizedBox.expand(
                          child: RepaintBoundary(
                            child: _AnimatedTabContent(
                              key: ValueKey('tabs:${profile.id}:${profile.role.dbValue}:${profile.companyId}'),
                              index: index,
                              pages: pages,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : withSwipeNavigation(
                RepaintBoundary(
                  child: _AnimatedTabContent(
                    key: ValueKey('tabs:${profile.id}:${profile.role.dbValue}:${profile.companyId}'),
                    index: index,
                    pages: pages,
                  ),
                ),
              ),
      ),
      bottomNavigationBar: isDesktop ? null : _GlassNavigationBar(
        appState: appState,
        selectedIndex: navIndex,
        onDestinationSelected: (newIndex) => selectPage(navItems[newIndex].label),
        items: navItems,
      ),
    );
  }

  List<_NavItem> _bottomItemsFor(UserRole role) {
    if (role == UserRole.superAdmin) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('companies', Icons.apartment_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('profile', Icons.settings_rounded),
      ];
    }
    if (role == UserRole.user) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('tickets', Icons.assignment_rounded),
        _NavItem('my_account', Icons.account_balance_wallet_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('profile', Icons.settings_rounded),
      ];
    }

    if (role == UserRole.worker) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('tickets', Icons.assignment_rounded),
        _NavItem('work_activity', Icons.fact_check_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('profile', Icons.settings_rounded),
      ];
    }
    return const [
      _NavItem('dashboard', Icons.dashboard_rounded),
      _NavItem('tickets', Icons.assignment_rounded),
      _NavItem('chat', Icons.forum_rounded),
      _NavItem('profile', Icons.settings_rounded),
    ];
  }

  List<_NavItem> _itemsFor(UserRole role) {
    if (role == UserRole.superAdmin) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('companies', Icons.apartment_rounded),
        _NavItem('users', Icons.people_alt_rounded),
        _NavItem('ratings', Icons.star_rounded),
        _NavItem('billing', Icons.workspace_premium_rounded),
        _NavItem('subscribers', Icons.groups_2_rounded),
        _NavItem('billing_imports', Icons.upload_file_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('ads', Icons.campaign_rounded),
        _NavItem('scheduled_notifications', Icons.notification_add_rounded),
        _NavItem('tickets', Icons.assignment_rounded),
        _NavItem('profile', Icons.settings_rounded),
        _NavItem('work_activity', Icons.fact_check_rounded),
        _NavItem('smartcall_reports', Icons.call_rounded),
      ];
    }
    if (role == UserRole.director || role == UserRole.admin) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('tickets', Icons.assignment_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('profile', Icons.settings_rounded),
        _NavItem('billing', Icons.workspace_premium_rounded),
        _NavItem('subscribers', Icons.groups_2_rounded),
        _NavItem('ads', Icons.campaign_rounded),
        _NavItem('team', Icons.engineering_rounded),
        _NavItem('work_activity', Icons.fact_check_rounded),
        _NavItem('smartcall_reports', Icons.call_rounded),
      ];
    }
    if (role == UserRole.worker) {
      return const [
        _NavItem('dashboard', Icons.dashboard_rounded),
        _NavItem('tickets', Icons.assignment_rounded),
        _NavItem('chat', Icons.forum_rounded),
        _NavItem('profile', Icons.settings_rounded),
        _NavItem('ratings', Icons.star_rounded),
        _NavItem('work_activity', Icons.fact_check_rounded),
      ];
    }
    return const [
      _NavItem('dashboard', Icons.dashboard_rounded),
      _NavItem('tickets', Icons.assignment_rounded),
      _NavItem('chat', Icons.forum_rounded),
      _NavItem('profile', Icons.settings_rounded),
      _NavItem('my_account', Icons.account_balance_wallet_rounded),
    ];
  }

  List<Widget> _pagesFor(UserRole role) {
    if (role == UserRole.superAdmin) {
      return [
        DashboardPage(appState: appState),
        SuperAdminCompaniesPage(appState: appState),
        SuperAdminUsersPage(appState: appState),
        TeamPage(appState: appState, rankingOnly: true),
        BillingPage(appState: appState),
        SubscribersPage(appState: appState),
        BillingImportsPage(appState: appState),
        ChatPage(appState: appState),
        AdvertisementPage(appState: appState),
        ScheduledNotificationsPage(appState: appState),
        TicketsPage(appState: appState),
        ProfilePage(appState: appState),
        WorkActivityPage(appState: appState),
        SmartCallReportsPage(appState: appState),
      ];
    }
    if (role == UserRole.director || role == UserRole.admin) {
      return [
        DashboardPage(appState: appState),
        TicketsPage(appState: appState),
        ChatPage(appState: appState),
        ProfilePage(appState: appState),
        BillingPage(appState: appState),
        SubscribersPage(appState: appState),
        AdvertisementPage(appState: appState),
        TeamPage(appState: appState),
        WorkActivityPage(appState: appState),
        SmartCallReportsPage(appState: appState),
      ];
    }
    if (role == UserRole.worker) {
      return [
        DashboardPage(appState: appState),
        TicketsPage(appState: appState),
        ChatPage(appState: appState),
        ProfilePage(appState: appState),
        TeamPage(appState: appState, rankingOnly: true),
        WorkActivityPage(appState: appState),
      ];
    }
    return [
      DashboardPage(appState: appState),
      TicketsPage(appState: appState),
      ChatPage(appState: appState),
      ProfilePage(appState: appState),
      MyAccountPage(appState: appState),
    ];
  }


  Future<void> _exportExcel(BuildContext context, {required bool isWork}) async {
    if (_exportInProgress) return;
    _exportInProgress = true;
    // iPad uchun ulashish oynasining joylashuvi.
    final renderObject = context.findRenderObject();
    final Rect? shareOrigin =
    renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Excel tayyorlanmoqda. Rasmlar yuklanishi biroz vaqt olishi mumkin...'),
        duration: Duration(seconds: 20),
      ));
      final exportedFile = isWork
          ? await ServiceProExcelExport.work(appState)
          : await ServiceProExcelExport.tickets(appState);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Share.shareXFiles(
        [exportedFile],
        sharePositionOrigin: shareOrigin,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel yaratilmadi: ${appState.friendlyError('$error')}'),
        ),
      );
    } finally {
      _exportInProgress = false;
    }
  }

  void _showNotifications(BuildContext context) {
    showNotificationInbox(context, appState);
  }

}

/// Full, independently scrollable navigation for laptop and desktop widths.
/// Never changes the underlying role/page mapping or chat/ticket state.
class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.appState,
    required this.profile,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final AppState appState;
  final Profile profile;
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final companyName = appState.companyById(profile.companyId)?.name ?? appState.tr('all_companies');
    return SizedBox(
      width: 248,
      child: ColoredBox(
        color: colors.surfaceContainerLow,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.home_work_rounded, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(child: Text('ServicePro', maxLines: 1,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 0, 17, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appState.tr(profile.role.dbValue),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(companyName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final selected = i == currentIndex;
                  final count = switch (item.label) {
                    'dashboard' || 'ads' => appState.unreadAdvertisementCount,
                    'chat' => appState.unreadChatCount,
                    'tickets' => appState.unreadTicketCount,
                    _ => 0,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: AnimatedContainer(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: selected ? colors.primaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        selected: selected,
                        selectedColor: colors.onPrimaryContainer,
                        leading: Badge(
                          isLabelVisible: count > 0,
                          label: Text(count > 99 ? '99+' : '$count'),
                          child: Icon(item.icon, size: 22),
                        ),
                        title: Text(appState.tr(item.label), maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
                          onTap: () => onSelect(item.label),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('ServicePro • Desktop', style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenu extends StatelessWidget {
  const _SideMenu({
    required this.appState,
    required this.items,
    required this.drawerItems,
  });

  final AppState appState;
  final List<_NavItem> items;
  final List<_NavItem> drawerItems;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = appState.currentProfile!;
    final companyName = appState.companyById(profile.companyId)?.name ?? appState.tr('all_companies');
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.primaryContainer,
                    colors.secondaryContainer.withValues(alpha: .75),
                    colors.surfaceContainerHighest,
                  ],
                ),
                border: Border.all(color: colors.primary.withValues(alpha: .22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: const Icon(Icons.apps_rounded),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Menyu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${appState.tr(profile.role.dbValue)} • $companyName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            for (final item in drawerItems)
              _DrawerTile(
                appState: appState,
                item: item,
                selected: appState.selectedIndex == items.indexWhere((nav) => nav.label == item.label),
                subtitle: _drawerSubtitle(appState, item.label),
                badgeCount: item.label == 'ads' ? appState.unreadAdvertisementCount : 0,
                onTap: () {
                  Navigator.pop(context);
                  final pageIndex = items.indexWhere((nav) => nav.label == item.label);
                  if (item.label == 'ads') {
                    unawaited(appState.markAdvertisementNotificationsRead());
                  }

                  if (item.label == 'tickets') {
                    unawaited(appState.markTicketNotificationsRead());
                  }
                  appState.setSelectedIndex(pageIndex < 0 ? 0 : pageIndex);
                },
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'ServicePro',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _drawerSubtitle(AppState appState, String label) {
  switch (label) {
    case 'team':
      return appState.tr('team');
    case 'ratings':
      return appState.tr('ratings');
    case 'users':
      return 'Foydalanuvchilar va rollar';
    case 'billing':
      return 'Obuna, narx va to‘lovlar';
    case 'subscribers':
      return 'Abonentlar va qarzdorlik';
    case 'billing_imports':
      return 'Excel yuklash va eski importlar';
    case 'my_account':
      return 'Hisobim va to‘lovlar tarixim';
    case 'ads':
      return 'Reklama va e’lonlar';
    case 'scheduled_notifications':
      return 'Kun, sana va vaqt bo‘yicha avtomatik push';
    case 'tickets':
      return 'Barcha arizalar nazorati';
    case 'companies':
      return 'Tashkilotlar boshqaruvi';
    case 'profile':
      return 'Profil va sozlamalar';
    default:
      return appState.tr(label);
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.appState,
    required this.item,
    required this.selected,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  final AppState appState;
  final _NavItem item;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? colors.primaryContainer : colors.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? colors.primary.withValues(alpha: .35) : colors.outlineVariant.withValues(alpha: .7)),
      ),
      child: ListTile(
        leading: Badge(
          isLabelVisible: badgeCount > 0,
          label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
          child: Icon(item.icon, color: selected ? colors.primary : null),
        ),
        title: Text(
          appState.tr(item.label),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

/// Builds only the visible tab instead of laying out every visited screen.
/// Off-screen pages retain state, but do not consume layout/paint frames.
class _AnimatedTabContent extends StatefulWidget {
  const _AnimatedTabContent({
    required this.index,
    required this.pages, required Key key,
  });

  final int index;
  final List<Widget> pages;

  @override
  State<_AnimatedTabContent> createState() =>
      _AnimatedTabContentState();
}

class _AnimatedTabContentState extends State<_AnimatedTabContent> {
  late final PageController _pageController =
      PageController(initialPage: widget.index);

  @override
  void didUpdateWidget(covariant _AnimatedTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      // A page change during an ancestor build must not update ScrollPosition
      // synchronously (it can otherwise throw setState-during-build errors).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(widget.index);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      allowImplicitScrolling: false,
      itemCount: widget.pages.length,
      itemBuilder: (context, i) => _CachedTabPage(
        child: widget.pages[i],
      ),
    );
  }
}

class _CachedTabPage extends StatefulWidget {
  const _CachedTabPage({required this.child});
  final Widget child;

  @override
  State<_CachedTabPage> createState() => _CachedTabPageState();
}

class _CachedTabPageState extends State<_CachedTabPage>
    with AutomaticKeepAliveClientMixin<_CachedTabPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.appState, required this.item, this.selected = false});
  final AppState appState;
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    var count = 0;
    if (item.label == 'dashboard') count = appState.unreadAdvertisementCount;
    if (item.label == 'chat') count = appState.unreadChatCount;
    if (item.label == 'tickets') count = appState.unreadTicketCount;
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(
        item.icon,
        size: 23,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Glass is deliberately limited to phones. Tablets and narrow desktop windows
/// retain an opaque navigation surface; every size gets the same light motion.
class _GlassNavigationBar extends StatelessWidget {
  const _GlassNavigationBar({
    required this.appState,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final AppState appState;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_NavItem> items;

  int _badgeCount(_NavItem item) {
    switch (item.label) {
      case 'dashboard':
        return appState.unreadAdvertisementCount;
      case 'chat':
        return appState.unreadChatCount;
      case 'tickets':
        return appState.unreadTicketCount;
      default:
        return 0;
    }
  }

  Widget _destination(
      BuildContext context,
      int index,
      int activeIndex,
      Duration duration,
      ) {
    final item = items[index];
    final selected = index == activeIndex;
    final colors = Theme.of(context).colorScheme;

    final fullLabel = appState.tr(item.label);
    final label = fullLabel == 'Mening hisobim'
        ? 'Hisobim'
        : fullLabel;

    return Semantics(
      label: fullLabel,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: fullLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onDestinationSelected(index),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                2, 30, 2, 8,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: selected
                          ? const SizedBox(height: 25)
                          : _NavBadge(
                        appState: appState,
                        item: item,
                      ),
                    ),
                  ),

                  const SizedBox(height: 2),

                  AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: items.length == 5 ? 10 : 11,
                      height: 1.1,
                      fontWeight: selected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final platform = theme.platform;

    final isPhone =
        (platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS) &&
            MediaQuery.sizeOf(context).shortestSide < 600;

    final reduceMotion =
        MediaQuery.of(context).disableAnimations;

    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 230);

    final activeIndex =
    selectedIndex.clamp(0, items.length - 1);

    final activeItem = items[activeIndex];
    final activeBadge = _badgeCount(activeItem);

    final radius = BorderRadius.circular(27);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: isPhone
            ? colors.surface.withValues(
          alpha: dark ? 0.94 : 0.97,
        )
            : colors.surfaceContainerLow,
        border: Border.all(
          color: isPhone
              ? colors.outlineVariant.withValues(
            alpha: 0.45,
          )
              : colors.outlineVariant,
        ),
      ),
      child: const SizedBox.expand(),
    );

    // BackdropFilter forces a costly offscreen blur on each frame, especially
    // while large chat and report pages redraw. Use a tinted glass-like
    // surface: same theme colours, without the GPU blur and tab stutter.
    final Widget background = surface;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        12, 8, 12, 10,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 590,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth =
                  constraints.maxWidth / items.length;

              const bubbleSize = 56.0;

              final targetX =
                  (activeIndex + 0.5) * slotWidth -
                      bubbleSize / 2;

              return SizedBox(
                height: 92,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [

                    // 1. Pastki panel foni
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 65,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: dark ? 0.20 : 0.08,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: RepaintBoundary(
                          child: background,
                        ),
                      ),
                    ),

                    // 2. Sahifalar tugmalari
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Row(
                          children: [
                            for (var i = 0;
                            i < items.length;
                            i++)
                              Expanded(
                                child: _destination(
                                  context,
                                  i,
                                  activeIndex,
                                  duration,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 3. Yuqoriga ko'tarilgan aktiv tugma
                    Positioned(
                      left: 0,
                      top: 0,
                      width: bubbleSize,
                      height: bubbleSize,
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            end: targetX,
                          ),
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          builder: (context, x, child) {
                            return Transform.translate(
                              offset: Offset(x, 0),
                              child: child,
                            );
                          },
                          child: RepaintBoundary(
                            child: Container(
                              width: bubbleSize,
                              height: bubbleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Badge(
                                  isLabelVisible: activeBadge > 0,
                                  label: Text(
                                    activeBadge > 99
                                        ? '99+'
                                        : '$activeBadge',
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : const Duration(
                                      milliseconds: 150,
                                    ),
                                    child: Icon(
                                      activeItem.icon,
                                      key: ValueKey(
                                        activeItem.label,
                                      ),
                                      color: colors.onPrimary,
                                      size: 25,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
