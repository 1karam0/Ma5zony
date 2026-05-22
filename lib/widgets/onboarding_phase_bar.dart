import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// A thin sticky banner shown at the top of phase screens during onboarding.
///
/// Lets the user move directly from one phase to the next without going back
/// to the dashboard. Auto-hides once onboarding is complete or the current
/// route is not a phase.
class OnboardingPhaseBar extends StatelessWidget {
  final AppState state;
  final String currentRoute;

  const OnboardingPhaseBar({
    super.key,
    required this.state,
    required this.currentRoute,
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

  int _currentPhaseIndex() {
    for (var i = 0; i < phases.length; i++) {
      if (currentRoute.startsWith(phases[i].route)) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsOnboarding()) return const SizedBox.shrink();
    final idx = _currentPhaseIndex();
    if (idx < 0) return const SizedBox.shrink();

    final prev = idx > 0 ? phases[idx - 1] : null;
    final next = idx < phases.length - 1 ? phases[idx + 1] : null;
    final current = phases[idx];

    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Container(
        height: 44,
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
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Setup wizard — Step ${idx + 1} of ${phases.length}: ${current.label}',
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
                  value: (idx + 1) / phases.length,
                  minHeight: 4,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: prev == null ? null : () => context.go(prev.route),
              icon: const Icon(Icons.chevron_left, size: 16),
              label: Text(prev?.label ?? 'Previous',
                  overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: next == null ? null : () => context.go(next.route),
              icon: const Icon(Icons.chevron_right, size: 16),
              label: Text('Next: ${next?.label ?? '—'}',
                  overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Back to setup overview',
              icon: const Icon(Icons.dashboard_outlined, size: 16),
              onPressed: () => context.go('/dashboard'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              color: AppColors.textSecondary,
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
