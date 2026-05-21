import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ma5zony/utils/constants.dart';

/// Breadcrumb navigation row for detail screens.
///
/// Usage:
/// ```dart
/// Breadcrumbs(crumbs: [
///   ('Dashboard', '/dashboard'),
///   ('Orders', '/orders'),
///   ('Order #ABC', null),   // last crumb has no route
/// ])
/// ```
class Breadcrumbs extends StatelessWidget {
  final List<(String label, String? route)> crumbs;

  const Breadcrumbs({super.key, required this.crumbs});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final (label, route) = crumbs[i];
      final isLast = i == crumbs.length - 1;
      if (i > 0) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right,
                size: 14, color: AppColors.textSecondary),
          ),
        );
      }
      items.add(
        isLast
            ? Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              )
            : InkWell(
                onTap: route != null ? () => context.go(route) : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 2, vertical: 2),
                  child: Text(
                    label,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: items),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTextStyles.h2),
              if (subtitle != null) ...
                [
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                ],
            ],
          ),
          const Spacer(),
          if (actions != null)
            Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ],
      ),
    );
  }
}

/// KPI display card. Supports an optional [trend] value (e.g. 12.5 = ▲12.5%)
/// and a [trendIsGood] flag to determine whether positive trend is green or red.
class KPICard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final bool isAlert;
  /// Trend percentage change vs previous period. Positive = up, negative = down.
  final double? trend;
  /// If true, ▲ trend = green. If false, ▲ trend = red (e.g. for costs).
  final bool trendIsGood;

  const KPICard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
    this.subtitle,
    this.isAlert = false,
    this.trend,
    this.trendIsGood = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isAlert ? AppColors.error : color)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isAlert ? AppColors.error : color,
                    size: 20,
                  ),
                ),
                if (isAlert)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.h2.copyWith(
                    color: isAlert ? AppColors.error : AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTextStyles.label),
                    ),
                    if (trend != null) _TrendBadge(trend: trend!, isGood: trendIsGood),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double trend;
  final bool isGood;
  const _TrendBadge({required this.trend, required this.isGood});

  @override
  Widget build(BuildContext context) {
    final isPositive = trend >= 0;
    final Color color = (isPositive == isGood) ? AppColors.success : AppColors.error;
    final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        Text(
          '${trend.abs().toStringAsFixed(1)}%',
          style: AppTextStyles.label.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'active':
      case 'ok':
      case 'connected':
      case 'shopify':
        color = AppColors.success;
        break;
      case 'low':
      case 'monitor':
      case 'manual':
        color = AppColors.warning;
        break;
      case 'critical':
      case 'order now':
      case 'urgent':
      case 'not connected':
        color = AppColors.error;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A rich, branded empty-state widget used across all screens.
/// Replace bare "No X yet" text with this for consistent UX.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  /// Optional inline warning banner shown above the CTA buttons.
  final String? warningMessage;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.warningMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (warningMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warningMessage!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (primaryLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (primaryLabel != null)
                    ElevatedButton(
                      onPressed: onPrimary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(primaryLabel!),
                    ),
                  if (secondaryLabel != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline banner shown at the top of screens whose data depends on
/// another module (e.g. Forecasts need demand data).
class DependencyBanner extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const DependencyBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: AppTextStyles.bodySmall),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: Text(
              actionLabel,
              style: AppTextStyles.label
                  .copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AppToast ─────────────────────────────────────────────────────────────────

enum AppToastType { success, error, warning, info }

/// Unified toast helper. Replaces raw `ScaffoldMessenger.of(context).showSnackBar`.
///
/// Usage:
/// ```dart
/// AppToast.show(context, 'Product saved');
/// AppToast.show(context, 'Failed: $e', type: AppToastType.error);
/// ```
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final (Color bg, IconData icon) = switch (type) {
      AppToastType.success => (AppColors.success, Icons.check_circle_outline),
      AppToastType.error => (AppColors.error, Icons.error_outline),
      AppToastType.warning => (AppColors.warning, Icons.warning_amber_outlined),
      AppToastType.info => (AppColors.primary, Icons.info_outline),
    };

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }
}

/// Wraps any wide child (typically a [DataTable]) in a horizontal
/// [SingleChildScrollView] with a visible [Scrollbar].
///
/// Use this instead of [SizedBox(width: double.infinity)] for tables so they
/// scroll horizontally at narrow viewports instead of showing overflow stripes.
///
/// ```dart
/// HorizontallyScrollableTable(
///   child: DataTable(columns: [...], rows: [...]),
/// )
/// ```
class HorizontallyScrollableTable extends StatefulWidget {
  final Widget child;

  const HorizontallyScrollableTable({super.key, required this.child});

  @override
  State<HorizontallyScrollableTable> createState() =>
      _HorizontallyScrollableTableState();
}

class _HorizontallyScrollableTableState
    extends State<HorizontallyScrollableTable> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: widget.child,
      ),
    );
  }
}

// ─── AlertBanner ──────────────────────────────────────────────────────────────

/// 4C — Semantic alert banner with a 4 px left accent bar.
///
/// ```dart
/// AlertBanner(
///   severity: AlertSeverity.warning,
///   title: '3 items below reorder point',
///   message: 'Review your replenishment recommendations.',
///   action: TextButton(onPressed: ..., child: Text('View')),
/// )
/// ```
enum AlertSeverity { info, success, warning, error }

class AlertBanner extends StatelessWidget {
  final AlertSeverity severity;
  final String title;
  final String? message;
  final Widget? action;
  final VoidCallback? onDismiss;

  const AlertBanner({
    super.key,
    required this.severity,
    required this.title,
    this.message,
    this.action,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, border, icon, iconColor) = switch (severity) {
      AlertSeverity.info    => (AppColors.infoBg,    AppColors.infoBorder,    Icons.info_outline,         AppColors.info),
      AlertSeverity.success => (AppColors.successBg, AppColors.successBorder, Icons.check_circle_outline,  AppColors.success),
      AlertSeverity.warning => (AppColors.warningBg, AppColors.warningBorder, Icons.warning_amber_outlined, AppColors.warning),
      AlertSeverity.error   => (AppColors.errorBg,   AppColors.errorBorder,   Icons.error_outline,         AppColors.error),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 4 px accent bar
            Container(width: 4, color: border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                    if (message != null) ...[
                      const SizedBox(height: 2),
                      Text(message!, style: AppTextStyles.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: action!,
              ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.textSecondary,
                onPressed: onDismiss,
                tooltip: 'Dismiss',
              ),
          ],
        ),
      ),
    );
  }
}

// ─── SkeletonLoader ───────────────────────────────────────────────────────────

/// 4I — Pulsing placeholder block used while data is loading.
///
/// ```dart
/// SkeletonLoader(width: double.infinity, height: 20)
/// ```
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 6,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: Color.lerp(
            const Color(0xFFE8EAED),
            const Color(0xFFF8F9FA),
            _anim.value,
          ),
        ),
      ),
    );
  }
}

// ── AppFormDialog ─────────────────────────────────────────────────────────────

/// Reusable dialog shell: header with title + close, scrollable form body,
/// sticky footer with action buttons. Replaces raw [AlertDialog] for forms.
class AppFormDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  const AppFormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Text(title, style: AppTextStyles.h2),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: child,
              ),
            ),
            // Footer actions
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a styled confirmation dialog. Returns [true] if confirmed.
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: isDanger
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

// ── EmptyState ────────────────────────────────────────────────────────────────

/// Consistent empty-state placeholder for lists, search results, etc.
///
/// Usage:
/// ```dart
/// if (items.isEmpty)
///   EmptyState(
///     icon: Icons.inventory_2_outlined,
///     heading: 'No products yet',
///     body: 'Add your first product to start tracking inventory.',
///     action: ElevatedButton.icon(
///       onPressed: _openAdd,
///       icon: const Icon(Icons.add),
///       label: const Text('Add Product'),
///     ),
///   )
/// ```
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String heading;
  final String? body;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.heading,
    this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: AppRadius.soft,
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(icon, size: 28, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              heading,
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  body!,
                  style:
                      AppTextStyles.body.copyWith(color: AppColors.textSubdued),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Skeleton placeholder for a KPI card grid (4 cards).
class KPICardSkeleton extends StatelessWidget {
  const KPICardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w > 900 ? 4 : w > 500 ? 2 : 1;
      const spacing = 16.0;
      final cardW = (w - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: List.generate(
          4,
          (_) => Container(
            width: cardW,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLoader(width: 80, height: 12),
                SizedBox(height: 12),
                SkeletonLoader(width: 48, height: 24),
                SizedBox(height: 8),
                SkeletonLoader(width: 120, height: 10),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Skeleton placeholder for a DataTable (3 rows × n columns).
class TableSkeleton extends StatelessWidget {
  final int columns;
  final int rows;

  const TableSkeleton({super.key, this.columns = 5, this.rows = 5});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header row
            Row(
              children: List.generate(
                columns,
                (_) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: const SkeletonLoader(width: double.infinity, height: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ...List.generate(rows, (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: List.generate(
                  columns,
                  (_) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SkeletonLoader(
                        width: double.infinity,
                        height: 14,
                        borderRadius: 4,
                      ),
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
