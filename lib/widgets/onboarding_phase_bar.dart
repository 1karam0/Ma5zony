import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// A thin sticky banner shown at the top of authenticated screens during
/// onboarding. Shows compact progress + "Resume Setup" button.
/// Auto-hides once all setup steps are complete.
class OnboardingPhaseBar extends StatelessWidget {
  final AppState state;

  // currentRoute is kept for API compatibility with existing callers but
  // is no longer used now that the banner is not route-specific.
  // ignore: avoid_unused_constructor_parameters
  const OnboardingPhaseBar({
    super.key,
    required this.state,
    required String currentRoute,
  });

  /// The ordered list of phase routes that the wizard walks through.
  static const List<_Phase> phases = [
    _Phase(label: 'Products', route: '/products'),
    _Phase(label: 'Suppliers', route: '/suppliers'),
    _Phase(label: 'Raw Materials', route: '/raw-materials'),
    _Phase(label: 'Bill of Materials', route: '/bom'),
    _Phase(label: 'Manufacturers', route: '/manufacturers'),
    _Phase(label: 'Warehouses', route: '/warehouses'),
    _Phase(label: 'Sales History', route: '/demand-data'),
    _Phase(label: 'Forecast', route: '/forecasts'),
  ];

  bool _needsOnboarding() {
    if (state.products.isEmpty) return true;
    if (state.suppliers.isEmpty) return true;
    if (state.rawMaterials.isEmpty) return true;
    final bomProductIds = state.boms.map((b) => b.finalProductId).toSet();
    if (state.products.any((p) => !bomProductIds.contains(p.id))) return true;
    if (state.manufacturers.isEmpty) return true;
    if (state.warehouses.isEmpty) return true;
    if (state.demandByProduct.isEmpty) return true;
    if (state.currentForecast == null) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsOnboarding()) return const SizedBox.shrink();

    // Count completed phases for the progress fraction
    final completed = phases.where((p) {
      switch (p.route) {
        case '/products':
          return state.products.isNotEmpty;
        case '/suppliers':
          return state.suppliers.isNotEmpty;
        case '/raw-materials':
          return state.rawMaterials.isNotEmpty;
        case '/bom':
          final bomProductIds =
              state.boms.map((b) => b.finalProductId).toSet();
          return state.products
              .every((p) => bomProductIds.contains(p.id));
        case '/manufacturers':
          return state.manufacturers.isNotEmpty;
        case '/warehouses':
          return state.warehouses.isNotEmpty;
        case '/demand-data':
          return state.demandByProduct.isNotEmpty;
        case '/forecasts':
          return state.currentForecast != null;
        default:
          return false;
      }
    }).length;
    final progress = completed / phases.length;

    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.rocket_launch_outlined,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Setup incomplete — $completed/${phases.length} steps done',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => context.go('/setup'),
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text('Resume Setup'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Phase {
  final String label;
  final String route;
  const _Phase({required this.label, required this.route});
}
