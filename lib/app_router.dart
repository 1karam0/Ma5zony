import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/features/auth/login_screen.dart';
import 'package:ma5zony/features/auth/register_screen.dart';
import 'package:ma5zony/widgets/main_layout.dart';
import 'package:ma5zony/features/dashboard/dashboard_screen.dart';
import 'package:ma5zony/features/dashboard/owner_dashboard_screen.dart';
import 'package:ma5zony/features/products/products_screen.dart';
import 'package:ma5zony/features/suppliers/suppliers_screen.dart';
import 'package:ma5zony/features/warehouses/warehouses_screen.dart';
import 'package:ma5zony/features/demand_data/demand_data_screen.dart';
import 'package:ma5zony/features/forecasts/forecasts_screen.dart';
import 'package:ma5zony/features/replenishment/replenishment_screen.dart';
import 'package:ma5zony/features/integrations/integrations_screen.dart';
import 'package:ma5zony/features/settings/settings_screen.dart';
import 'package:ma5zony/features/financial_analytics/financial_analytics_screen.dart';
import 'package:ma5zony/features/orders/orders_screen.dart';
import 'package:ma5zony/features/orders/create_order_screen.dart';
import 'package:ma5zony/features/orders/order_detail_screen.dart';
import 'package:ma5zony/features/supplier_portal/supplier_portal_screen.dart';
import 'package:ma5zony/features/raw_materials/raw_materials_screen.dart';
import 'package:ma5zony/features/bom/bom_screen.dart';
import 'package:ma5zony/features/manufacturers/manufacturers_screen.dart';
import 'package:ma5zony/features/manufacturing/recommendations_screen.dart';
import 'package:ma5zony/features/manufacturing/production_orders_screen.dart';
import 'package:ma5zony/features/manufacturing/production_order_detail_screen.dart';
import 'package:ma5zony/features/cash_flow/cash_flow_screen.dart';
import 'package:ma5zony/features/manufacturer_portal/manufacturer_portal_screen.dart';
import 'package:ma5zony/features/factory_portal/factory_portal_screen.dart';
import 'package:ma5zony/utils/role_guard.dart';

// Private navigators
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildAppRouter(AppState appState) => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: appState,
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    // Supplier portal — outside the auth shell (no login required)
    GoRoute(
      path: '/supplier-portal',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return SupplierPortalScreen(accessToken: token);
      },
    ),
    // Manufacturer portal — outside the auth shell (no login required)
    GoRoute(
      path: '/manufacturer-portal',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return ManufacturerPortalScreen(accessToken: token);
      },
    ),
    // Factory portal — outside the auth shell (no login required)
    GoRoute(
      path: '/factory-portal',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return FactoryPortalScreen(accessToken: token);
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainLayout(child: child);
      },
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) {
            final user = appState.currentUser;
            final Widget dashboard = isOwner(user)
                ? const OwnerDashboardScreen()
                : const DashboardScreen();
            return NoTransitionPage(child: dashboard);
          },
        ),
        GoRoute(
          path: '/products',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProductsScreen()),
        ),
        GoRoute(
          path: '/suppliers',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SuppliersScreen()),
        ),
        GoRoute(
          path: '/warehouses',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: WarehousesScreen()),
        ),
        GoRoute(
          path: '/demand-data',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DemandDataScreen()),
        ),
        GoRoute(
          path: '/forecasts',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ForecastsScreen()),
        ),
        GoRoute(
          path: '/replenishment',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ReplenishmentScreen()),
        ),
        GoRoute(
          path: '/integrations',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: IntegrationsScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
        GoRoute(
          path: '/financial-analytics',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: FinancialAnalyticsScreen()),
        ),
        GoRoute(
          path: '/orders',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: OrdersScreen()),
        ),
        GoRoute(
          path: '/orders/create',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CreateOrderScreen()),
        ),
        GoRoute(
          path: '/orders/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return NoTransitionPage(
              child: OrderDetailScreen(orderId: id),
            );
          },
        ),
        GoRoute(
          path: '/raw-materials',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: RawMaterialsScreen()),
        ),
        GoRoute(
          path: '/bom',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: BomScreen()),
        ),
        GoRoute(
          path: '/manufacturers',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ManufacturersScreen()),
        ),
        GoRoute(
          path: '/recommendations',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: RecommendationsScreen()),
        ),
        GoRoute(
          path: '/production-orders',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProductionOrdersScreen()),
        ),
        GoRoute(
          path: '/production-orders/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return NoTransitionPage(
              child: ProductionOrderDetailScreen(orderId: id),
            );
          },
        ),
        GoRoute(
          path: '/cash-flow',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CashFlowScreen()),
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final loggedIn = appState.currentUser != null;
    final path = state.uri.toString();
    final loggingIn = path == '/login' || path == '/register';

    // Portals are public — no auth redirect
    if (path.startsWith('/supplier-portal') ||
        path.startsWith('/manufacturer-portal') ||
        path.startsWith('/factory-portal')) {
      return null;
    }

    if (!loggedIn && !loggingIn) return '/login';
    if (loggedIn && loggingIn) return '/dashboard';

    // Role-based route guard: block owner-only routes for Inventory Managers
    if (loggedIn) {
      final path = state.uri.toString();
      if (ownerOnlyRoutes.contains(path) &&
          !isOwner(appState.currentUser)) {
        return '/dashboard';
      }
    }

    return null;
  },
);
