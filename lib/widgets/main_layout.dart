// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/providers/app_state.dart';

class MainLayout extends StatelessWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(isDesktop: isDesktop),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: child),
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
    return Container(
      width: isDesktop ? kSidebarWidth : kSidebarCollapsedWidth,
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Center(
              child: isDesktop
                  ? Text(
                      'Ma5zony',
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.inventory_2, color: AppColors.primary),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard,
                  label: 'Dashboard',
                  path: '/dashboard',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.inventory,
                  label: 'Products',
                  path: '/products',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.local_shipping,
                  label: 'Suppliers',
                  path: '/suppliers',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.warehouse,
                  label: 'Warehouses',
                  path: '/warehouses',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.analytics,
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
                  icon: Icons.shopping_cart,
                  label: 'Replenishment',
                  path: '/replenishment',
                  isDesktop: isDesktop,
                ),
                _NavItem(
                  icon: Icons.integration_instructions,
                  label: 'Integrations',
                  path: '/integrations',
                  isDesktop: isDesktop,
                ),
                const Divider(),
                _NavItem(
                  icon: Icons.settings,
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
    final isSelected = GoRouterState.of(
      context,
    ).uri.toString().startsWith(path);
    return InkWell(
      onTap: () => context.go(path),
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            if (isDesktop) ...[
              const SizedBox(width: 12),
              Text(
                label,
                style: isSelected
                    ? AppTextStyles.body.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      )
                    : AppTextStyles.body,
              ),
            ],
          ],
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
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    // Get title from current route (naive implementation)
    final String location = GoRouterState.of(context).uri.toString();
    String title = 'Dashboard';
    if (location.contains('products')) {
      title = 'Products';
    } else if (location.contains('suppliers'))
      title = 'Suppliers';
    else if (location.contains('warehouses'))
      title = 'Warehouses';
    else if (location.contains('demand'))
      title = 'Demand Data';
    else if (location.contains('forecasts'))
      title = 'Forecasts';
    else if (location.contains('replenishment'))
      title = 'Replenishment';
    else if (location.contains('integrations'))
      title = 'Integrations';
    else if (location.contains('settings'))
      title = 'Settings';

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.h2),
          const Spacer(),
          _GlobalSearchBox(),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
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
        matchedWarehouses.isEmpty) return;

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
