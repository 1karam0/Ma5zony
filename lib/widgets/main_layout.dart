import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/app_notification.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/role_guard.dart';

class MainLayout extends StatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  String? _lastError;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final state = context.watch<AppState>();

    // Show error snackbar when errorMessage changes
    final error = state.errorMessage;
    if (error != null && error != _lastError) {
      _lastError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () => state.clearError(),
              ),
            ),
          );
        }
      });
    }

    return Scaffold(
      // Mobile drawer (< 600px): sidebar slides in from left
      drawer: isMobile
          ? Drawer(
              child: _Sidebar(isDesktop: true),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) _Sidebar(isDesktop: isDesktop),
          Expanded(
            child: Column(
              children: [
                _TopBar(isMobile: isMobile),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final bool isDesktop;

  const _Sidebar({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final userIsOwner = isOwner(user);

    return Container(
      width: isDesktop ? kSidebarWidth : kSidebarCollapsedWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        children: [
          // ── Logo / brand ────────────────────────────────────────────
          SizedBox(
            height: 64,
            child: Center(
              child: isDesktop
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Ma5zony',
                          style: AppTextStyles.h2.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    )
                  : const Icon(Icons.inventory_2,
                      color: AppColors.primary),
            ),
          ),
          const Divider(height: 1),

          // ── Nav items ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  path: '/dashboard',
                  isDesktop: isDesktop,
                ),

                // ── INVENTORY ───────────────────────────────────────
                _SectionDivider(label: 'INVENTORY', isDesktop: isDesktop),
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  path: '/products',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.local_shipping_outlined,
                  label: 'Suppliers',
                  path: '/suppliers',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.warehouse_outlined,
                  label: 'Warehouses',
                  path: '/warehouses',
                  isDesktop: isDesktop,
                ),

                // ── OPERATIONS ──────────────────────────────────────
                _SectionDivider(label: 'OPERATIONS', isDesktop: isDesktop),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'Demand Data',
                  path: '/demand-data',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.trending_up,
                  label: 'Forecasts',
                  path: '/forecasts',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Replenishment',
                  path: '/replenishment',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Purchase Orders',
                  path: '/orders',
                  isDesktop: isDesktop,
                ),

                // ── MANUFACTURING ────────────────────────────────────
                _SectionDivider(label: 'MANUFACTURING', isDesktop: isDesktop),
                _NavItem(
                  icon: Icons.category_outlined,
                  label: 'Raw Materials',
                  path: '/raw-materials',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.list_alt_outlined,
                  label: 'Bill of Materials',
                  path: '/bom',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.factory_outlined,
                  label: 'Manufacturers',
                  path: '/manufacturers',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Recommendations',
                  path: '/recommendations',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.precision_manufacturing_outlined,
                  label: 'Production Orders',
                  path: '/production-orders',
                  isDesktop: isDesktop,
                ),

                // ── FINANCE (owner only) ─────────────────────────────
                if (userIsOwner) ...[
                  _SectionDivider(label: 'FINANCE', isDesktop: isDesktop),
                  _NavItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Cash Flow',
                    path: '/cash-flow',
                    isDesktop: isDesktop,
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_outlined,
                    label: 'Financial Analytics',
                    path: '/financial-analytics',
                    isDesktop: isDesktop,
                  ),
                ],

                // ── SYSTEM ───────────────────────────────────────────
                _SectionDivider(label: 'SYSTEM', isDesktop: isDesktop),
                _NavItem(
                  icon: Icons.integration_instructions_outlined,
                  label: 'Integrations',
                  path: '/integrations',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  path: '/settings',
                  isDesktop: isDesktop,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _UserItem(isDesktop: isDesktop),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final bool isDesktop;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.toString();
    final isSelected = currentPath == path ||
        (path != '/dashboard' && currentPath.startsWith(path));
    return InkWell(
      onTap: () => context.go(path),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2), width: 1)
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              icon,
              color:
                  isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 18,
            ),
            if (isDesktop) ...[
              const SizedBox(width: 10),
              Text(
                label,
                style: isSelected
                    ? AppTextStyles.body.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )
                    : AppTextStyles.body.copyWith(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section label shown between nav-item groups in the expanded sidebar.
class _SectionDivider extends StatelessWidget {
  final String label;
  final bool isDesktop;
  const _SectionDivider({required this.label, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      // Collapsed sidebar: just a subtle line
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Divider(height: 1, color: AppColors.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 2),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          fontSize: 10,
          letterSpacing: 1.1,
          color: AppColors.textSecondary.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UserItem extends StatelessWidget {
  final bool isDesktop;

  const _UserItem({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    if (user == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: () {
          context.read<AppState>().logout();
          context.go('/login');
        },
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 16,
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
            if (isDesktop) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.role,
                      style: AppTextStyles.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.logout,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.isMobile = false});

  final bool isMobile;

  static const _routeTitles = [
    ('/orders/create', 'Create Purchase Order'),
    ('/orders/', 'Order Detail'),
    ('/orders', 'Purchase Orders'),
    ('/production-orders/', 'Production Order Detail'),
    ('/production-orders', 'Production Orders'),
    ('/dashboard', 'Dashboard'),
    ('/products', 'Products'),
    ('/suppliers', 'Suppliers'),
    ('/warehouses', 'Warehouses'),
    ('/demand-data', 'Demand Data'),
    ('/forecasts', 'Forecasts'),
    ('/replenishment', 'Replenishment'),
    ('/integrations', 'Integrations'),
    ('/settings', 'Settings'),
    ('/financial-analytics', 'Financial Analytics'),
    ('/raw-materials', 'Raw Materials'),
    ('/bom', 'Bill of Materials'),
    ('/manufacturers', 'Manufacturers'),
    ('/recommendations', 'Recommendations'),
    ('/cash-flow', 'Cash Flow'),
  ];

  String _titleFor(String location) {
    for (final entry in _routeTitles) {
      if (location.startsWith(entry.$1)) return entry.$2;
    }
    return 'Ma5zony';
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final title = _titleFor(location);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Hamburger menu on mobile
          if (isMobile)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Open navigation',
              ),
            ),
          Text(title, style: AppTextStyles.h2),
          const Spacer(),
          _GlobalSearchBox(),
          const SizedBox(width: 16),
          _NotificationBell(),
        ],
      ),
    );
  }
}

/// Notification bell icon with badge + dropdown panel.
class _NotificationBell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadNotificationCount;

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread', style: const TextStyle(fontSize: 10)),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
          color: unread > 0 ? AppColors.primary : AppColors.textSecondary,
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
          // Header with "Mark all read"
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
          // Notifications list (max 10)
          ...notifications.take(10).map((n) {
            return PopupMenuItem<String>(
              value: n.actionRoute,
              child: _NotificationTile(notification: n, state: state),
            );
          }),
        ];
      },
      onSelected: (route) {
        if (route.isNotEmpty) {
          context.go(route);
        }
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
                Text(notification.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight:
                          notification.isRead ? FontWeight.normal : FontWeight.w600,
                    )),
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

  static IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.lowStock:
        return Icons.warning_amber;
      case NotificationType.stockout:
        return Icons.error_outline;
      case NotificationType.orderApproved:
        return Icons.check_circle;
      case NotificationType.shopifySync:
        return Icons.sync;
      case NotificationType.forecastReady:
        return Icons.auto_graph;
      case NotificationType.general:
        return Icons.info_outline;
    }
  }

  static Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.lowStock:
        return AppColors.warning;
      case NotificationType.stockout:
        return AppColors.error;
      case NotificationType.orderApproved:
        return AppColors.success;
      case NotificationType.shopifySync:
        return AppColors.accent;
      case NotificationType.forecastReady:
        return AppColors.primary;
      case NotificationType.general:
        return AppColors.textSecondary;
    }
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

class _GlobalSearchBox extends StatefulWidget {
  @override
  State<_GlobalSearchBox> createState() => _GlobalSearchBoxState();
}

class _GlobalSearchBoxState extends State<_GlobalSearchBox> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _onChanged(String query) {
    _removeOverlay();
    if (query.trim().isEmpty) return;

    final state = context.read<AppState>();
    final q = query.toLowerCase();

    final matchedProducts = state.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .take(5)
        .toList();

    final matchedSuppliers = state.suppliers
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.contactEmail.toLowerCase().contains(q))
        .take(3)
        .toList();

    final matchedWarehouses = state.warehouses
        .where((w) =>
            w.name.toLowerCase().contains(q) ||
            w.city.toLowerCase().contains(q))
        .take(3)
        .toList();

    if (matchedProducts.isEmpty &&
        matchedSuppliers.isEmpty &&
        matchedWarehouses.isEmpty) {
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        top: offset.dy + renderBox.size.height + 4,
        left: offset.dx,
        width: 300,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                if (matchedProducts.isNotEmpty) ...[
                  _sectionLabel('Products'),
                  ...matchedProducts.map((p) => _resultTile(
                        icon: Icons.inventory,
                        title: p.name,
                        subtitle: p.sku,
                        onTap: () {
                          _clear();
                          context.go('/products');
                        },
                      )),
                ],
                if (matchedSuppliers.isNotEmpty) ...[
                  _sectionLabel('Suppliers'),
                  ...matchedSuppliers.map((s) => _resultTile(
                        icon: Icons.local_shipping,
                        title: s.name,
                        subtitle: s.contactEmail,
                        onTap: () {
                          _clear();
                          context.go('/suppliers');
                        },
                      )),
                ],
                if (matchedWarehouses.isNotEmpty) ...[
                  _sectionLabel('Warehouses'),
                  ...matchedWarehouses.map((w) => _resultTile(
                        icon: Icons.warehouse,
                        title: w.name,
                        subtitle: w.city,
                        onTap: () {
                          _clear();
                          context.go('/warehouses');
                        },
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        child: Text(text,
            style: AppTextStyles.label
                .copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
      );

  Widget _resultTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.primary),
        title: Text(title, style: AppTextStyles.body),
        subtitle: Text(subtitle, style: AppTextStyles.label),
        onTap: onTap,
      );

  void _clear() {
    _controller.clear();
    _removeOverlay();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'Search products, suppliers...',
                hintStyle:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: _clear,
              child: const Icon(Icons.close,
                  size: 16, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
