import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/features/auth/login_screen.dart';
import 'package:ma5zony/features/auth/register_screen.dart';
import 'package:ma5zony/widgets/main_layout.dart';
import 'package:ma5zony/features/dashboard/dashboard_screen.dart';
import 'package:ma5zony/features/products/products_screen.dart';
import 'package:ma5zony/features/suppliers/suppliers_screen.dart';
import 'package:ma5zony/features/warehouses/warehouses_screen.dart';
import 'package:ma5zony/features/demand_data/demand_data_screen.dart';
import 'package:ma5zony/features/forecasts/forecasts_screen.dart';
import 'package:ma5zony/features/replenishment/replenishment_screen.dart';
import 'package:ma5zony/features/integrations/integrations_screen.dart';
import 'package:ma5zony/features/settings/settings_screen.dart';
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
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainLayout(child: child);
      },
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DashboardScreen()),
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
      ],
    ),
  ],
  redirect: (context, state) {
    final loggedIn = appState.currentUser != null;
    final loggingIn =
        state.uri.toString() == '/login' || state.uri.toString() == '/register';

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
