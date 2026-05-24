import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/models/app_notification.dart';
import 'package:ma5zony/models/app_user.dart';
import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/command_palette.dart';
import 'package:ma5zony/widgets/onboarding_phase_bar.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

// ── Nav data ──────────────────────────────────────────────────────────────────

/// A labelled nav category with a representative icon and its route entries.
class _NavGroup {
  final String label;
  final IconData icon;
  final List<NavRouteEntry> entries;

  /// Optional uppercase section header rendered above the group when it
  /// differs from the previously-rendered section (Zoho pattern).
  final String? section;

  const _NavGroup({
    required this.label,
    required this.icon,
    required this.entries,
    this.section,
  });
}

// All nav groups (role filtering applied at runtime via _visibleGroupsForUser)
const _kGroupDashboard = _NavGroup(
  label: 'Dashboard',
  icon: Icons.space_dashboard_outlined,
  entries: [
    NavRouteEntry(icon: Icons.space_dashboard_outlined, label: 'Dashboard', path: '/dashboard'),
    NavRouteEntry(icon: Icons.inbox_outlined, label: 'Action Center', path: '/inbox'),
  ],
);

// Products is the anchor of the entire supply chain — direct link, always visible
const _kGroupProducts = _NavGroup(
  label: 'Products',
  icon: Icons.inventory_2_outlined,
  section: 'INVENTORY',
  entries: [
    NavRouteEntry(icon: Icons.inventory_2_outlined, label: 'Products', path: '/products'),
  ],
);

// Supply chain setup: follow the chain — Supplier → Raw Material → BOM → Manufacturer → Warehouse
const _kGroupSupplyChain = _NavGroup(
  label: 'Supply Chain Setup',
  icon: Icons.account_tree_outlined,
  section: 'INVENTORY',
  entries: [
    NavRouteEntry(icon: Icons.local_shipping_outlined, label: 'Suppliers', path: '/suppliers'),
    NavRouteEntry(icon: Icons.category_outlined, label: 'Raw Materials', path: '/raw-materials'),
    NavRouteEntry(icon: Icons.account_tree_outlined, label: 'Bill of Materials', path: '/bom'),
    NavRouteEntry(icon: Icons.factory_outlined, label: 'Manufacturers', path: '/manufacturers'),
    NavRouteEntry(icon: Icons.warehouse_outlined, label: 'Warehouses', path: '/warehouses'),
  ],
);

// Operational: demand analysis, forecasting, and all order types
const _kGroupDemandOrders = _NavGroup(
  label: 'Demand & Orders',
  icon: Icons.trending_up_outlined,
  section: 'OPERATIONS',
  entries: [
    NavRouteEntry(icon: Icons.query_stats, label: 'Forecasts', path: '/forecasts'),
    NavRouteEntry(icon: Icons.show_chart, label: 'Demand Data', path: '/demand-data'),
    NavRouteEntry(icon: Icons.receipt_long_outlined, label: 'Purchase Orders', path: '/orders'),
    NavRouteEntry(icon: Icons.inventory_outlined, label: 'Material Orders', path: '/orders/raw-materials'),
    NavRouteEntry(icon: Icons.precision_manufacturing_outlined, label: 'Production Orders', path: '/production-orders'),
    NavRouteEntry(icon: Icons.auto_awesome_motion_outlined, label: 'Replenishment', path: '/replenishment'),
    NavRouteEntry(icon: Icons.grid_view_outlined, label: 'Product Analysis', path: '/classification'),
  ],
);

// Finance group: everything related to money flow
const _kGroupFinance = _NavGroup(
  label: 'Finance',
  icon: Icons.account_balance_wallet_outlined,
  section: 'FINANCE',
  entries: [
    NavRouteEntry(icon: Icons.account_balance_wallet_outlined, label: 'Cash Flow', path: '/cash-flow'),
    NavRouteEntry(icon: Icons.bar_chart_outlined, label: 'Financial Analytics', path: '/financial-analytics'),
  ],
);

// Settings group: integrations + app configuration
const _kGroupSettings = _NavGroup(
  label: 'Settings',
  icon: Icons.tune,
  section: 'SYSTEM',
  entries: [
    NavRouteEntry(icon: Icons.cable_outlined, label: 'Integrations', path: '/integrations'),
    NavRouteEntry(icon: Icons.tune, label: 'Settings', path: '/settings'),
  ],
);

// Focused Manufacturing group for the Manufacturer role
const _kGroupManufacturerFocused = _NavGroup(
  label: 'Manufacturing',
  icon: Icons.factory_outlined,
  entries: [
    NavRouteEntry(icon: Icons.precision_manufacturing_outlined, label: 'Production Orders', path: '/production-orders'),
    NavRouteEntry(icon: Icons.auto_awesome_motion_outlined, label: 'Replenishment', path: '/replenishment'),
    NavRouteEntry(icon: Icons.account_tree_outlined, label: 'Bill of Materials', path: '/bom'),
  ],
);

// Focused group for the Raw Material Factory role
const _kGroupRawMaterials = _NavGroup(
  label: 'Materials',
  icon: Icons.category_outlined,
  entries: [
    NavRouteEntry(icon: Icons.category_outlined, label: 'Raw Materials', path: '/raw-materials'),
    NavRouteEntry(icon: Icons.local_shipping_outlined, label: 'Suppliers', path: '/suppliers'),
  ],
);

/// Returns nav groups visible to [user] based on their role.
List<_NavGroup> _visibleGroupsForUser(AppUser? user) {
  if (user == null) {
    return [_kGroupDashboard, _kGroupProducts, _kGroupSupplyChain, _kGroupDemandOrders, _kGroupFinance, _kGroupSettings];
  }
  return switch (user.role) {
    AppUser.roleSmeOwner => [
        _kGroupDashboard, _kGroupProducts, _kGroupSupplyChain,
        _kGroupDemandOrders, _kGroupFinance, _kGroupSettings,
      ],
    AppUser.roleInventoryManager => [
        _kGroupDashboard, _kGroupProducts, _kGroupSupplyChain,
        _kGroupDemandOrders, _kGroupFinance, _kGroupSettings,
      ],
    AppUser.roleManufacturer => [
        _kGroupDashboard, _kGroupManufacturerFocused,
      ],
    AppUser.roleRawMaterialFactory => [
        _kGroupDashboard, _kGroupRawMaterials,
      ],
    _ => [_kGroupDashboard, _kGroupProducts, _kGroupSupplyChain, _kGroupDemandOrders, _kGroupFinance, _kGroupSettings],
  };
}

// ── Route → page title ────────────────────────────────────────────────────────

const List<(String, String)> _kRouteTitles = [
  ('/orders/raw-materials/create', 'Create RM Order'),
  ('/orders/raw-materials', 'Raw Material Orders'),
  ('/orders/create', 'Create Purchase Order'),
  ('/orders/', 'Order Detail'),
  ('/orders', 'Purchase Orders'),
  ('/production-orders/', 'Production Order Detail'),
  ('/production-orders', 'Production Orders'),
  ('/forecasts/compare', 'Forecast Algorithm Comparison'),
  ('/forecasts', 'Demand Forecasting'),
  ('/setup', 'Setup Wizard'),
  ('/dashboard', 'Dashboard'),
  ('/products', 'Products'),
  ('/suppliers', 'Suppliers'),
  ('/warehouses', 'Warehouses'),
  ('/demand-data', 'Demand Data'),
  ('/classification', 'ABC-XYZ Classification'),
  ('/replenishment', 'Replenishment'),
  ('/inbox', 'Action Center'),
  ('/integrations', 'Integrations'),
  ('/settings', 'Settings'),
  ('/financial-analytics', 'Financial Analytics'),
  ('/raw-materials', 'Raw Materials'),
  ('/bom', 'Bill of Materials'),
  ('/manufacturers', 'Manufacturers'),
  ('/recommendations', 'Production Recommendations'),
  ('/cash-flow', 'Cash Flow'),
];

String _titleForRoute(String location) {
  for (final (prefix, title) in _kRouteTitles) {
    if (location.startsWith(prefix)) return title;
  }
  return 'Ma5zony';
}

// ── MainLayout ─────────────────────────────────────────────────────────────────

class MainLayout extends StatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  String? _lastError;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return true;
    }
    return false;
  }

  void _openCommandPalette() {
    if (!mounted) return;
    final user = context.read<AppState>().currentUser;
    final entries = _visibleGroupsForUser(user).expand((g) => g.entries).toList();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => CommandPalette(entries: entries),
    );
  }

  void _showErrorIfNeeded(AppState state) {
    final error = state.errorMessage;
    if (error != null && error != _lastError) {
      _lastError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
              content: Text(error),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ))
            .closed
            .then((_) {
          if (mounted) state.clearError();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _showErrorIfNeeded(state);

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) return _buildMobileLayout(state);

    final user = state.currentUser;
    final groups = _visibleGroupsForUser(user);
    final badges = _buildBadges(state);

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            groups: groups,
            badges: badges,
            user: user,
            onLogout: () {
              state.logout();
              context.go('/login');
            },
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(isMobile: false, onOpenPalette: _openCommandPalette),
                OnboardingPhaseBar(
                  state: state,
                  currentRoute: GoRouterState.of(context).uri.toString(),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(AppState state) {
    final user = state.currentUser;
    final groups = _visibleGroupsForUser(user);
    final badges = _buildBadges(state);
    final loc = GoRouterState.of(context).uri.toString();

    // Zoho-style bottom nav — 5 most-used destinations + More (drawer).
    const bottomTabs = <(String, String, IconData)>[
      ('/dashboard', 'Home', Icons.dashboard_outlined),
      ('/products', 'Products', Icons.inventory_2_outlined),
      ('/orders', 'Orders', Icons.receipt_long_outlined),
      ('/forecasts', 'Forecasts', Icons.query_stats),
      ('__more__', 'More', Icons.menu),
    ];

    int currentIndex = 0;
    for (int i = 0; i < bottomTabs.length - 1; i++) {
      final path = bottomTabs[i].$1;
      if (loc == path || (path != '/dashboard' && loc.startsWith(path))) {
        currentIndex = i;
        break;
      }
    }

    return Scaffold(
      key: _mobileScaffoldKey,
      drawer: Drawer(
        width: 260,
        child: _Sidebar(
          groups: groups,
          badges: badges,
          user: user,
          onNavTap: () => Navigator.of(context).pop(),
          onLogout: () {
            Navigator.of(context).pop();
            state.logout();
            context.go('/login');
          },
        ),
      ),
      body: Column(
        children: [
          _TopBar(isMobile: true, onOpenPalette: _openCommandPalette),
          OnboardingPhaseBar(
            state: state,
            currentRoute: loc,
          ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.surfaceCard,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            selectedLabelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500),
            showUnselectedLabels: true,
            elevation: 0,
            onTap: (i) {
              final tab = bottomTabs[i];
              if (tab.$1 == '__more__') {
                _mobileScaffoldKey.currentState?.openDrawer();
              } else {
                context.go(tab.$1);
              }
            },
            items: [
              for (final t in bottomTabs)
                BottomNavigationBarItem(
                  icon: Icon(t.$3, size: 22),
                  label: t.$2,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, int> _buildBadges(AppState state) {
    final totalInboxCount = (state.hasUrgentStockAlerts
            ? state.criticalStockProducts.length
            : 0) +
        state.openRecommendations +
        state.purchaseOrders
            .where((o) => o.status.name == 'draft')
            .length +
        state.mfgRecommendations
            .where((r) => r.status == RecommendationStatus.pending)
            .length +
        state.supplierOrders
            .where((o) => o.status == 'acknowledged' && o.response != null)
            .length;

    return {
      '/inbox': totalInboxCount,
      '/dashboard': state.hasUrgentStockAlerts ? state.criticalStockProducts.length : 0,
      '/replenishment': state.openRecommendations,
      '/orders': state.purchaseOrders
          .where((o) =>
              o.status.name == 'pending' || o.status.name == 'confirmed')
          .length,
      '/recommendations': state.mfgRecommendations
          .where((r) => r.status == RecommendationStatus.pending)
          .length,
      '/production-orders': state.productionOrders
          .where((o) =>
              o.status == ProductionOrderStatus.draft ||
              o.status == ProductionOrderStatus.approved ||
              o.status == ProductionOrderStatus.inProduction)
          .length,
      '/orders/raw-materials': state.rmPurchaseOrders
          .where((o) => o.status == 'draft')
          .length,
    };
  }
}

// ── Sidebar (permanent, always expanded) ─────────────────────────────────────

class _Sidebar extends StatefulWidget {
  final List<_NavGroup> groups;
  final Map<String, int> badges;
  final AppUser? user;
  final VoidCallback onLogout;
  final VoidCallback? onNavTap;

  const _Sidebar({
    required this.groups,
    required this.badges,
    required this.user,
    required this.onLogout,
    this.onNavTap,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late Set<int> _expanded;
  String? _trackedLoc;

  @override
  void initState() {
    super.initState();
    _expanded = {};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = GoRouterState.of(context).uri.toString();
    if (loc == _trackedLoc) return;
    _trackedLoc = loc;
    for (int i = 0; i < widget.groups.length; i++) {
      final hasActive = widget.groups[i].entries.any((e) =>
          loc == e.path || (e.path != '/dashboard' && loc.startsWith(e.path)));
      if (hasActive) _expanded = {..._expanded, i};
    }
  }

  void _toggle(int i) => setState(() {
        if (_expanded.contains(i)) {
          _expanded = _expanded.difference({i});
        } else {
          _expanded = {..._expanded, i};
        }
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(right: BorderSide(color: Color(0x18FFFFFF))),
      ),
      child: Column(
        children: [
          // Brand header
          SizedBox(
            height: kTopBarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.inventory_2, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ma5zony',
                    style: AppTextStyles.h2.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Org context pill (Zoho pattern)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OrgContextPill(
                orgName: widget.user?.name.split(' ').first.isNotEmpty == true
                    ? '${widget.user!.name.split(' ').first}\'s Workspace'
                    : 'My Workspace',
                onTap: () => context.go('/settings'),
              ),
            ),
          ),

          // Nav groups
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (int i = 0; i < widget.groups.length; i++) ...[
                  // Render uppercase section header when section changes
                  if (widget.groups[i].section != null &&
                      (i == 0 ||
                          widget.groups[i - 1].section !=
                              widget.groups[i].section))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Text(
                        widget.groups[i].section!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  _SidebarGroup(
                    group: widget.groups[i],
                    badges: widget.badges,
                    expanded: _expanded.contains(i),
                    onToggle: () => _toggle(i),
                    onNavigate: (path) {
                      context.go(path);
                      widget.onNavTap?.call();
                    },
                  ),
                ],
              ],
            ),
          ),

          // User row
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: _UserFlyoutItem(user: widget.user, onTap: widget.onLogout),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar group (category with click-to-expand sub-items) ──────────────────

class _SidebarGroup extends StatelessWidget {
  final _NavGroup group;
  final Map<String, int> badges;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String) onNavigate;

  const _SidebarGroup({
    required this.group,
    required this.badges,
    required this.expanded,
    required this.onToggle,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final groupHasActive = group.entries.any((e) =>
        loc == e.path || (e.path != '/dashboard' && loc.startsWith(e.path)));
    final totalBadge = group.entries.fold(0, (s, e) => s + (badges[e.path] ?? 0));
    final isSingle = group.entries.length == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category header
        InkWell(
          onTap: isSingle ? () => onNavigate(group.entries.first.path) : onToggle,
          hoverColor: AppColors.sidebarBgHover,
          splashColor: Colors.transparent,
          child: SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Accent bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: groupHasActive ? 20 : 0,
                  decoration: BoxDecoration(
                    color: AppColors.sidebarAccent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
                const SizedBox(width: 12),
                // Icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: groupHasActive
                        ? AppColors.sidebarAccent.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    group.icon,
                    size: 16,
                    color: groupHasActive ? AppColors.sidebarTextActive : AppColors.sidebarText,
                  ),
                ),
                const SizedBox(width: 10),
                // Label
                Expanded(
                  child: Text(
                    group.label,
                    style: (groupHasActive
                            ? AppTextStyles.sidebarItemActive
                            : AppTextStyles.sidebarItem)
                        .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                // Badge when collapsed
                if (totalBadge > 0 && !expanded)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$totalBadge',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                // Chevron
                if (!isSingle)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.sidebarText.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Animated sub-items dropdown
        if (!isSingle)
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: expanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in group.entries)
                    _FlyoutItem(
                      entry: entry,
                      badge: badges[entry.path] ?? 0,
                      onTap: () => onNavigate(entry.path),
                      indented: true,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Flyout item ───────────────────────────────────────────────────────────────

class _FlyoutItem extends StatelessWidget {
  final NavRouteEntry entry;
  final int badge;
  final VoidCallback onTap;

  /// When true, adds extra left indent to show hierarchy inside a category.
  final bool indented;

  const _FlyoutItem({
    required this.entry,
    required this.onTap,
    this.badge = 0,
    this.indented = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final isActive = loc == entry.path ||
        (entry.path != '/dashboard' && loc.startsWith(entry.path));

    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.sidebarBgHover,
      splashColor: Colors.transparent,
      child: SizedBox(
        height: 36,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 2px accent bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 2,
              height: isActive ? 16 : 0,
              decoration: BoxDecoration(
                color: AppColors.sidebarAccent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            // Extra indent for nested items
            SizedBox(width: indented ? 20 : 10),
            // Icon in tinted square
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.sidebarAccent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                entry.icon,
                size: 14,
                color: isActive
                    ? AppColors.sidebarTextActive
                    : AppColors.sidebarText.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.label,
                style: (isActive
                        ? AppTextStyles.sidebarItemActive
                        : AppTextStyles.sidebarItem)
                    .copyWith(fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── User items ────────────────────────────────────────────────────────────────

class _UserFlyoutItem extends StatelessWidget {
  final AppUser? user;
  final VoidCallback onTap;

  const _UserFlyoutItem({required this.user, required this.onTap});

  Color _roleColor(String role) => switch (role) {
        AppUser.roleSmeOwner => AppColors.primary,
        AppUser.roleInventoryManager => AppColors.info,
        AppUser.roleManufacturer => AppColors.warning,
        AppUser.roleRawMaterialFactory => AppColors.accent,
        _ => AppColors.textSubdued,
      };

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    final roleColor = _roleColor(user!.role);

    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.sidebarBgHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar with role-coloured ring
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: roleColor.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Center(
                child: Text(
                  user!.name.isNotEmpty ? user!.name[0].toUpperCase() : '?',
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user!.name,
                    style: AppTextStyles.sidebarItem.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: roleColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      user!.role,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: roleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Sign out',
              child: Icon(
                Icons.logout,
                size: 14,
                color: AppColors.sidebarText.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isMobile;
  final VoidCallback onOpenPalette;

  const _TopBar({required this.isMobile, required this.onOpenPalette});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final title = _titleForRoute(location);

    return Container(
      height: kTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          if (isMobile)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, size: 20),
                color: AppColors.textSecondary,
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Open navigation',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ),
          if (isMobile) const SizedBox(width: 8),
          Text(title, style: AppTextStyles.h2),
          const Spacer(),
          _CommandPaletteTrigger(onTap: onOpenPalette),
          const SizedBox(width: 8),
          _QuickActionButton(),
          const SizedBox(width: 8),
          _NotificationBell(),
        ],
      ),
    );
  }
}

// ── ⌘K pill trigger ──────────────────────────────────────────────────────────

class _CommandPaletteTrigger extends StatelessWidget {
  final VoidCallback onTap;

  const _CommandPaletteTrigger({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final hint = isApple ? '⌘K' : 'Ctrl K';

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pill,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          border: Border.all(color: AppColors.divider),
          borderRadius: AppRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 14, color: AppColors.textSubdued),
            const SizedBox(width: 6),
            Text(
              'Search...',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSubdued,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: AppRadius.sharp,
                color: AppColors.surface,
              ),
              child: Text(hint, style: AppTextStyles.kbd),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick-Action "+ New" Button ───────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.read<AppState>().currentUser;
    final isManufacturer = user?.role == AppUser.roleManufacturer;
    final isFactory = user?.role == AppUser.roleRawMaterialFactory;

    final actions = <_QuickAction>[
      if (!isManufacturer && !isFactory)
        _QuickAction(Icons.receipt_long_outlined, 'New Purchase Order', '/orders/create'),
      if (!isFactory)
        _QuickAction(Icons.inventory_2_outlined, 'Add Product', '/products'),
      if (!isManufacturer && !isFactory)
        _QuickAction(Icons.query_stats, 'Run Forecast', '/forecasts'),
      if (!isFactory)
        _QuickAction(Icons.precision_manufacturing_outlined, 'New Production Order', '/production-orders'),
    ];

    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      tooltip: 'Quick actions',
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text('Quick Actions', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSubdued,
          )),
        ),
        ...actions.map((a) => PopupMenuItem<String>(
          value: a.path,
          height: 40,
          child: Row(
            children: [
              Icon(a.icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(a.label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        )),
      ],
      onSelected: (path) => context.go(path),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('New', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String path;
  const _QuickAction(this.icon, this.label, this.path);
}

// ── Notification Bell ─────────────────────────────────────────────────────────

class _NotificationBell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadNotificationCount;

    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread', style: const TextStyle(fontSize: 10)),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
          color: unread > 0 ? AppColors.primary : AppColors.textSecondary,
          size: 20,
        ),
      ),
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
      itemBuilder: (_) {
        final notifications = state.notifications;
        if (notifications.isEmpty) {
          return [
            const PopupMenuItem(
              enabled: false,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No notifications')),
              ),
            ),
          ];
        }
        return [
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                Text('Notifications', style: AppTextStyles.h3),
                const Spacer(),
                if (unread > 0)
                  TextButton(
                    onPressed: () {
                      state.markAllNotificationsRead();
                      Navigator.pop(context);
                    },
                    child: const Text('Mark all read',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...notifications.take(10).map(
                (n) => PopupMenuItem<String>(
                  value: n.actionRoute,
                  child: _NotificationTile(notification: n, state: state),
                ),
              ),
        ];
      },
      onSelected: (route) {
        if (route.isNotEmpty) context.go(route);
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final AppState state;

  const _NotificationTile({required this.notification, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: notification.isRead
            ? Colors.transparent
            : AppColors.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForType(notification.type),
              size: 20, color: _colorForType(notification.type)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: notification.isRead
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(notification.message,
                    style: AppTextStyles.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_timeAgo(notification.createdAt),
                    style: AppTextStyles.label.copyWith(fontSize: 11)),
              ],
            ),
          ),
          if (!notification.isRead)
            InkWell(
              onTap: () => state.markNotificationRead(notification.id),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.check_circle_outline,
                    size: 16, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconForType(NotificationType type) => switch (type) {
        NotificationType.lowStock => Icons.warning_amber,
        NotificationType.stockout => Icons.error_outline,
        NotificationType.orderApproved => Icons.check_circle,
        NotificationType.shopifySync => Icons.sync,
        NotificationType.forecastReady => Icons.auto_graph,
        NotificationType.general => Icons.info_outline,
      };

  static Color _colorForType(NotificationType type) => switch (type) {
        NotificationType.lowStock => AppColors.warning,
        NotificationType.stockout => AppColors.error,
        NotificationType.orderApproved => AppColors.success,
        NotificationType.shopifySync => AppColors.accent,
        NotificationType.forecastReady => AppColors.primary,
        NotificationType.general => AppColors.textSecondary,
      };

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
