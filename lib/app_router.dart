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
import 'package:ma5zony/features/forecasts/forecast_comparison_screen.dart';
import 'package:ma5zony/features/reorder_plan/reorder_plan_screen.dart';
import 'package:ma5zony/features/classification/abc_xyz_screen.dart';
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
import 'package:ma5zony/features/legal/legal_screens.dart';
import 'package:ma5zony/features/onboarding/setup_wizard_screen.dart';
import 'package:ma5zony/features/onboarding/business_profile_wizard.dart';
import 'package:ma5zony/features/orders/raw_material_orders_screen.dart';
import 'package:ma5zony/features/orders/create_raw_material_order_screen.dart';
import 'package:ma5zony/features/replenishment/replenishment_screen.dart';
import 'package:ma5zony/features/inbox/inbox_screen.dart';
import 'package:ma5zony/utils/role_guard.dart';

// Private navigators
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildAppRouter(AppState appState) {
  return GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: appState.authNotifier,
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) {
        final inviteToken = state.uri.queryParameters['invite'];
        return RegisterScreen(inviteToken: inviteToken);
      },
    ),
    // Public legal pages — no auth required
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => const TermsOfServiceScreen(),
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
    // Business-profile onboarding — kept as an *opt-in* route for users
    // who want to set their stock model / business type later (from
    // Settings). It is no longer forced on first login; the interactive
    // spotlight tour walks new users through setup instead.
    GoRoute(
      path: '/onboarding/profile',
      redirect: (context, state) {
        // If user landed here from a stale forced redirect (current session
        // before the change), or simply types the URL with no business
        // reason, send them to the dashboard so the spotlight tour can run.
        return '/dashboard';
      },
      builder: (context, state) => const BusinessProfileWizard(),
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
          path: '/inbox',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: InboxScreen()),
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
              const NoTransitionPage(child: ReorderPlanScreen()),
        ),
        GoRoute(
          path: '/forecasts/advanced',
          pageBuilder: (context, state) {
            final productId = state.uri.queryParameters['productId'];
            return NoTransitionPage(
              child: ForecastsScreen(preSelectedProductId: productId),
            );
          },
        ),
        GoRoute(
          path: '/forecasts/compare',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ForecastComparisonScreen()),
        ),
        GoRoute(
          path: '/classification',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AbcXyzScreen()),
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
        GoRoute(
          path: '/orders/raw-materials',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: RawMaterialOrdersScreen()),
        ),
        GoRoute(
          path: '/orders/raw-materials/create',
          pageBuilder: (context, state) {
            final productId = state.uri.queryParameters['productId'] ?? '';
            final qty = double.tryParse(
                state.uri.queryParameters['qty'] ?? '0') ?? 0;
            return NoTransitionPage(
              child: CreateRawMaterialOrderScreen(
                  productId: productId, forecastQty: qty),
            );
          },
        ),
        GoRoute(
          path: '/setup',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SetupWizardScreen()),
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final loggedIn = appState.currentUser != null;
    final path = state.uri.toString();
    final loggingIn = path == '/login' || path.startsWith('/register');

    // Portals and legal pages are public — no auth redirect
    if (path.startsWith('/supplier-portal') ||
        path.startsWith('/manufacturer-portal') ||
        path.startsWith('/factory-portal') ||
        path == '/privacy' ||
        path == '/terms') {
      return null;
    }

    if (!loggedIn && !loggingIn) {
      return '/login';
    }
    if (loggedIn && loggingIn) {
      return '/dashboard';
    }

    // Setup wizard is accessible after login
    if (path == '/setup' && !loggedIn) return '/login';

    // The business-profile wizard is no longer forced. New owners land
    // straight on the dashboard and are guided by the interactive spotlight
    // tour (see `WelcomeTourDialog.show`). The /onboarding/profile route
    // remains accessible for users who want to set their profile later from
    // Settings.

    // NOTE: We no longer force owners through a standalone setup wizard route.
    // The dashboard onboarding checklist IS the wizard — it appears on first
    // login and guides the user through every phase. The /setup route is kept
    // for backwards compatibility but is not forced.

    // Role-based route guard: block owner-only routes for Inventory Managers
    if (loggedIn) {
      if (ownerOnlyRoutes.contains(path) &&
          !isOwner(appState.currentUser)) {
        return '/dashboard';
      }
    }

    return null;
  },
);
}
