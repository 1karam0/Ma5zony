import 'package:flutter/material.dart';
import 'package:ma5zony/utils/constants.dart';

/// Zoho-inspired component library.
///
/// These widgets are additive — they do not replace any existing components,
/// they sit alongside [shared_widgets.dart] to bring the dashboard and forms
/// closer to Zoho Inventory's guided, progressive-disclosure UX.
///
/// All widgets here are stateless and self-contained.
///
/// See `ma5zony_ux_improvement_report.md` for design rationale.

// ─────────────────────────────────────────────────────────────────────────────
// HorizontalTabBar
// ─────────────────────────────────────────────────────────────────────────────

/// A single pill on a [HorizontalTabBar].
class ZohoTab {
  final String label;
  final IconData? icon;

  /// Optional small badge (e.g. remaining onboarding task count).
  final int? badge;
  final Color? badgeColor;
  const ZohoTab({required this.label, this.icon, this.badge, this.badgeColor});
}

/// Horizontal scrollable tab bar used to switch the *content* area of a screen
/// (Zoho pattern — Dashboard / Getting Started / Help & Support).
///
/// This is NOT a navigation tab — it does not change the route. Use it to swap
/// the body of a single screen.
class HorizontalTabBar extends StatelessWidget {
  final List<ZohoTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  const HorizontalTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _TabPill(
                tab: tabs[i],
                selected: i == selectedIndex,
                onTap: () => onChanged(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final ZohoTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill(
      {required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.textOnPrimary : AppColors.textPrimary;
    final bg = selected ? AppColors.primary : AppColors.surfaceSunken;
    final badgeBg = tab.badgeColor ??
        (selected ? Colors.white.withValues(alpha: 0.25) : AppColors.warning);
    final badgeFg = selected ? Colors.white : Colors.white;

    return Material(
      color: bg,
      borderRadius: AppRadius.pill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.icon != null) ...[
                Icon(tab.icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(tab.label, style: AppTextStyles.tabLabel.copyWith(color: fg)),
              if (tab.badge != null && tab.badge! > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${tab.badge}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeFg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GettingStartedHeroCard
// ─────────────────────────────────────────────────────────────────────────────

/// Hero card for the Getting Started tab.
///
/// Shows: greeting, progress text ("01/08 Tasks Completed"), and a linear
/// progress bar. Mirrors Zoho Inventory's onboarding card.
class GettingStartedHeroCard extends StatelessWidget {
  final String userName;
  final String emoji;
  final String subtitle;
  final int doneCount;
  final int totalCount;

  const GettingStartedHeroCard({
    super.key,
    required this.userName,
    required this.emoji,
    required this.subtitle,
    required this.doneCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            const Color(0xFF005C46),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $userName',
                      style: AppTextStyles.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.body
                          .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '${doneCount.toString().padLeft(2, '0')}/'
                '${totalCount.toString().padLeft(2, '0')} Tasks Completed',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SetupActionCard
// ─────────────────────────────────────────────────────────────────────────────

/// "Configure Tax / Connect Shopify / Invite Team" action card.
///
/// Renders an icon, title, subtitle, and a trailing CTA button.
class SetupActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onTap;
  final Color? iconColor;

  const SetupActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: AppRadius.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
              borderRadius: AppRadius.sm,
            ),
            child: Icon(icon, size: 20, color: iconColor ?? AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
            ),
            child: Text(ctaLabel),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HelpSupportCard
// ─────────────────────────────────────────────────────────────────────────────

/// "Need help and support? Go →" persistent banner used on Getting Started.
class HelpSupportCard extends StatelessWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;

  const HelpSupportCard({
    super.key,
    required this.onTap,
    this.title = 'Need help and support?',
    this.subtitle = 'Browse docs, watch tutorials, or contact our team.',
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: AppRadius.md,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.md,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: AppRadius.md,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: AppRadius.sm,
                ),
                child: const Icon(Icons.support_agent,
                    size: 22, color: AppColors.info),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward,
                  size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RequiredLabel
// ─────────────────────────────────────────────────────────────────────────────

/// Form-field label that renders in [AppColors.requiredLabel] when required,
/// matching Zoho's pattern (no asterisk — the color signals the requirement).
class RequiredLabel extends StatelessWidget {
  final String text;
  final bool required;

  const RequiredLabel({super.key, required this.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.formLabel.copyWith(
        color: required ? AppColors.requiredLabel : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZohoFormSection
// ─────────────────────────────────────────────────────────────────────────────

/// Grouped form section — optionally collapsible ("Add More Information ▶").
///
/// Use this to break long forms into logical groups: Basic Information,
/// Inventory Settings, Pricing Information, etc.
class ZohoFormSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// When true, the section starts collapsed and shows a chevron.
  final bool collapsible;
  final bool initiallyExpanded;

  /// When true, draws a leading toggle switch (e.g. "Pricing Information [on]").
  final bool showToggle;
  final bool toggleValue;
  final ValueChanged<bool>? onToggleChanged;

  const ZohoFormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.showToggle = false,
    this.toggleValue = false,
    this.onToggleChanged,
  });

  @override
  State<ZohoFormSection> createState() => _ZohoFormSectionState();
}

class _ZohoFormSectionState extends State<ZohoFormSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveExpanded = widget.showToggle ? widget.toggleValue : _expanded;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: AppRadius.sm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppTextStyles.formSection),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.showToggle)
                    Switch(
                      value: widget.toggleValue,
                      onChanged: widget.onToggleChanged,
                      activeThumbColor: AppColors.primary,
                    )
                  else if (widget.collapsible)
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.chevron_right,
                          size: 20, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          if (effectiveExpanded) ...[
            const SizedBox(height: 12),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TypeSelectorGroup
// ─────────────────────────────────────────────────────────────────────────────

/// A single option for [TypeSelectorGroup].
class TypeOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const TypeOption({required this.value, required this.label, this.icon});
}

/// Radio-style horizontal row for type selection (e.g. Goods / Service /
/// Raw Material). Each option renders as a card with a radio dot.
class TypeSelectorGroup<T> extends StatelessWidget {
  final List<TypeOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const TypeSelectorGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _TypeOptionCard<T>(
              option: options[i],
              selected: options[i].value == value,
              onTap: () => onChanged(options[i].value),
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeOptionCard<T> extends StatelessWidget {
  final TypeOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surfaceCard,
      borderRadius: AppRadius.md,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.md,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: AppRadius.md,
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.textSubdued,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              if (option.icon != null) ...[
                Icon(option.icon,
                    size: 16,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  option.label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color:
                        selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FeatureDiscoveryCard
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontally scrollable feature discovery cards (Zoho "More Features" row).
class FeatureDiscoveryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accentColor;

  const FeatureDiscoveryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.primary;
    return SizedBox(
      width: 220,
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: AppRadius.md,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: AppRadius.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: AppRadius.sm,
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(height: 12),
                Text(title,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Open',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: accent, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward, size: 13, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OrgContextPill
// ─────────────────────────────────────────────────────────────────────────────

/// Company/org context pill rendered at the top of the sidebar.
///
/// Tapping it can open profile / settings shortcuts. For now it just shows the
/// org name and a chevron.
class OrgContextPill extends StatelessWidget {
  final String orgName;
  final VoidCallback? onTap;

  const OrgContextPill({super.key, required this.orgName, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: AppRadius.sm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.sm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business_center_outlined,
                  size: 13, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  orgName,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down,
                  size: 14, color: Colors.white.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PendingActionsCard
// ─────────────────────────────────────────────────────────────────────────────

/// One row inside [PendingActionsCard].
class PendingAction {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? count;
  final String ctaLabel;
  final VoidCallback onTap;

  const PendingAction({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.count,
    this.ctaLabel = 'Review',
    required this.onTap,
  });
}

/// Zoho-style "Pending Actions" card — a prioritized list of items that need
/// the user's attention (low stock, POs awaiting approval, production orders
/// in draft, etc.). Each row links to the relevant screen.
class PendingActionsCard extends StatelessWidget {
  final List<PendingAction> actions;
  final String title;

  const PendingActionsCard({
    super.key,
    required this.actions,
    this.title = 'Pending Actions',
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.h3),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${actions.length}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.borderSubtle),
            _PendingActionRow(action: actions[i]),
          ],
        ],
      ),
    );
  }
}

class _PendingActionRow extends StatelessWidget {
  final PendingAction action;
  const _PendingActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: AppRadius.sm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: action.iconColor.withValues(alpha: 0.1),
                borderRadius: AppRadius.sm,
              ),
              child: Icon(action.icon, size: 18, color: action.iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.label,
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (action.count != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  action.count!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              action.ctaLabel,
              style: AppTextStyles.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZohoStepper — workflow progress (Draft → Submitted → Approved → ...)
// ─────────────────────────────────────────────────────────────────────────────

class ZohoStepperStep {
  final String label;
  final IconData? icon;
  const ZohoStepperStep({required this.label, this.icon});
}

/// Horizontal stepper showing the progress of a multi-stage workflow such as
/// a purchase order (Draft → Submitted → Approved → Shipped → Received) or a
/// production order. The connector before a completed/current step is filled.
class ZohoStepper extends StatelessWidget {
  final List<ZohoStepperStep> steps;

  /// 0-based index of the currently active step. All steps with index < this
  /// value are rendered as completed.
  final int currentIndex;

  const ZohoStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _StepNode(
                step: steps[i],
                index: i,
                state: i < currentIndex
                    ? _StepState.completed
                    : (i == currentIndex
                        ? _StepState.current
                        : _StepState.upcoming),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: i < currentIndex
                        ? AppColors.primary
                        : AppColors.borderSubtle,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

enum _StepState { completed, current, upcoming }

class _StepNode extends StatelessWidget {
  final ZohoStepperStep step;
  final int index;
  final _StepState state;
  const _StepNode(
      {required this.step, required this.index, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    switch (state) {
      case _StepState.completed:
        bg = AppColors.primary;
        fg = Colors.white;
        border = AppColors.primary;
        break;
      case _StepState.current:
        bg = Colors.white;
        fg = AppColors.primary;
        border = AppColors.primary;
        break;
      case _StepState.upcoming:
        bg = Colors.white;
        fg = AppColors.textSubdued;
        border = AppColors.borderSubtle;
        break;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
          child: state == _StepState.completed
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Center(
                  child: step.icon != null
                      ? Icon(step.icon, size: 16, color: fg)
                      : Text(
                          '${index + 1}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 88,
          child: Text(
            step.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: state == _StepState.upcoming
                  ? AppColors.textSubdued
                  : AppColors.textPrimary,
              fontWeight: state == _StepState.current
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
