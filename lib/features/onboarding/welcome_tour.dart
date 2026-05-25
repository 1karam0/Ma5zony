import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/features/onboarding/spotlight_coach.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// A multi-step welcome tour shown to brand-new SME owners after they finish
/// the Business Profile wizard. The goal is to:
///
///   1. Orient the user to the sidebar and key destinations.
///   2. Explain the data dependency chain (Suppliers → Materials → Products
///      → BOM → Demand Data → Reorder Plan → Purchase Order).
///   3. Point at the in-dashboard checklist as the ongoing source of truth.
///
/// On finish (or skip) we set `settings.tourCompleted = true` so it doesn't
/// auto-show again. A "Replay tour" button on the dashboard re-opens it.
class WelcomeTourDialog extends StatefulWidget {
  const WelcomeTourDialog({super.key});

  /// Launches the interactive spotlight coach directly — no static slide
  /// modal, no "raw steps" screen. The coach dims the page, cuts a window
  /// around each real sidebar/UI anchor, and walks the user through the
  /// setup chain (Suppliers → Manufacturers → Raw Materials → Warehouses →
  /// Products → BOM → Reorder Plan), navigating between routes between
  /// steps.
  ///
  /// Persists `settings.tourCompleted = true` so it doesn't auto-launch
  /// again. The dashboard "Replay tour" button still calls this to re-run
  /// the spotlight on demand.
  static Future<bool> show(BuildContext context) async {
    // Wait one frame so the dashboard (and its sidebar anchors) are mounted
    // before the coach tries to locate them.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!context.mounted) return false;

    await SpotlightCoach.start(
      context,
      [
        // ── Welcome ──────────────────────────────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar.group:Dashboard',
          title: 'Welcome to Ma5zony 👋',
          description:
              'I\'ll walk you through setup in the correct order — each step unlocks the next. '
              'At every action step the highlighted button is live and the tour auto-advances once you save.',
          navigateTo: '/dashboard',
        ),

        // ── Step 1: Connect Shopify (optional, but do it FIRST) ──────────
        const SpotlightStep(
          anchorId: 'sidebar.group:Settings',
          title: 'Step 1 — Connect Shopify (if you use it)',
          description:
              'If you sell on Shopify, connect it NOW — before adding anything else. '
              'This lets you import your product catalogue and sales history in later steps. '
              'Skip ahead if you don\'t use Shopify.',
          navigateTo: '/integrations',
        ),

        // ── Step 2: Suppliers ────────────────────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar.group:Supply Chain Setup',
          title: 'Step 2 — Supply Chain Setup',
          description:
              'Suppliers must exist BEFORE you import or add products — '
              'every product links to the supplier you buy it from so the reorder plan knows who to order from and their lead time.',
          navigateTo: '/suppliers',
        ),
        SpotlightStep(
          anchorId: 'page:suppliers.add',
          title: 'Add your first supplier',
          description:
              'Click the highlighted button and fill in the form. '
              'The tour continues automatically the moment you save your first supplier.',
          completeWhen: (ctx) => ctx.read<AppState>().suppliers.isNotEmpty,
        ),

        // ── Step 3: Warehouses ───────────────────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar:/warehouses',
          title: 'Step 3 — Warehouses',
          description:
              'Warehouses must also exist before you add products — '
              'stock levels are tracked per warehouse. Add your shop, studio, or storage location.',
          navigateTo: '/warehouses',
        ),
        SpotlightStep(
          anchorId: 'page:warehouses.add',
          title: 'Add your first warehouse',
          description:
              'Click here and fill in the location. '
              'Tour continues once saved.',
          completeWhen: (ctx) => ctx.read<AppState>().warehouses.isNotEmpty,
        ),

        // ── Step 4: Products ─────────────────────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar.group:Products',
          title: 'Step 4 — Products',
          description:
              'NOW add your products — suppliers and warehouses already exist, '
              'so you can link everything immediately. '
              'Import from Shopify or add manually — your choice.',
          navigateTo: '/products',
        ),
        SpotlightStep(
          anchorId: 'page:products.import',
          title: 'Option A — Import from Shopify',
          description:
              'Pulls your product catalogue in one click. '
              '⚠️ Shopify only sends the SELLING price — you must enter the unit cost (what YOU pay) for each product, otherwise COGS, margin and reorder costs are all wrong. '
              'Hit "Skip step" if you\'ll add manually.',
          completeWhen: (ctx) => ctx.read<AppState>().products.isNotEmpty,
        ),
        SpotlightStep(
          anchorId: 'page:products.add',
          title: 'Option B — Add a product manually',
          description:
              'Click here, fill the form (including unit cost), save. '
              'For manufactured items, cost is calculated from the BOM you\'ll build in a later step.',
          completeWhen: (ctx) => ctx.read<AppState>().products.isNotEmpty,
        ),

        // ── Step 5: Manufacturing (optional) ─────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar:/manufacturers',
          title: 'Step 5 — Manufacturers (skip if reseller)',
          description:
              'If you make products in-house or through partners, list them here. '
              'Pure resellers can skip steps 5–7 entirely.',
          navigateTo: '/manufacturers',
        ),
        SpotlightStep(
          anchorId: 'page:manufacturers.add',
          title: 'Add a manufacturer',
          description:
              'Click here to add one. '
              'Auto-advances when saved — or hit "Skip step" if you don\'t manufacture anything.',
          completeWhen: (ctx) => ctx.read<AppState>().manufacturers.isNotEmpty,
        ),
        const SpotlightStep(
          anchorId: 'sidebar:/raw-materials',
          title: 'Step 6 — Raw Materials (manufacturing only)',
          description:
              'List every material you buy as inputs. '
              'Each links to a supplier — that\'s how reorder math knows lead times for components.',
          navigateTo: '/raw-materials',
        ),
        SpotlightStep(
          anchorId: 'page:rawmaterials.add',
          title: 'Add a raw material',
          description:
              'Click and add one — link it to its supplier. '
              'Auto-advances when saved, or "Skip step" if reseller-only.',
          completeWhen: (ctx) => ctx.read<AppState>().rawMaterials.isNotEmpty,
        ),
        const SpotlightStep(
          anchorId: 'sidebar:/bom',
          title: 'Step 7 — Bill of Materials (manufacturing only)',
          description:
              'For each manufactured product, map the raw materials it consumes and their quantities. '
              'Ma5zony rolls this up automatically into the product\'s unit cost.',
          navigateTo: '/bom',
        ),
        SpotlightStep(
          anchorId: 'page:bom.add',
          title: 'Build your first BOM',
          description:
              'Click here, pick the finished product, add materials + quantities. '
              'Auto-advances when saved, or "Skip step" if no manufactured products.',
          completeWhen: (ctx) => ctx.read<AppState>().boms.isNotEmpty,
        ),

        // ── Final: Reorder Plan ──────────────────────────────────────────
        const SpotlightStep(
          anchorId: 'sidebar:/forecasts',
          title: 'Final step — Reorder Plan',
          description:
              'Import your sales history from Shopify (or upload a CSV) to give Ma5zony demand data. '
              'It then tells you exactly what to reorder, how much, and when. '
              'You\'re all set — replay this tour any time from the dashboard!',
          navigateTo: '/forecasts',
        ),
      ],
      onNavigate: (path) {
        if (context.mounted) context.go(path);
      },
    );

    // Mark tour as done only AFTER the coach exits (user finished or skipped).
    // Doing it up-front caused the flag to be set on a mid-tour browser
    // refresh, so the tour would never auto-restart.
    if (context.mounted) {
      final state = context.read<AppState>();
      unawaited(state.saveSettings(state.settings.copyWith(tourCompleted: true)));
    }
    return true;
  }

  @override
  State<WelcomeTourDialog> createState() => _WelcomeTourDialogState();
}

class _WelcomeTourDialogState extends State<WelcomeTourDialog> {
  final _controller = PageController();
  int _page = 0;

  late final List<_TourSlide> _slides;

  @override
  void initState() {
    super.initState();
    _slides = _buildSlides();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_TourSlide> _buildSlides() {
    return [
      _TourSlide(
        icon: Icons.celebration_outlined,
        title: 'Welcome to Ma5zony 👋',
        subtitle: 'Your inventory & order command centre',
        body: const _BulletList(items: [
          'Forecast demand from real sales data',
          'Know exactly when (and how much) to reorder',
          'Track raw materials, production & purchase orders in one place',
        ]),
        footer:
            'This quick tour will show you around — about 60 seconds.',
      ),
      _TourSlide(
        icon: Icons.menu_book_outlined,
        title: 'Your sidebar, at a glance',
        subtitle: 'Each group represents a stage of your operations',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SidebarRow(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              desc: 'KPIs, pending actions and your setup checklist.',
            ),
            _SidebarRow(
              icon: Icons.inventory_2_outlined,
              label: 'Products',
              desc: 'Finished goods you sell. Sync from Shopify or add manually.',
            ),
            _SidebarRow(
              icon: Icons.account_tree_outlined,
              label: 'Supply Chain Setup',
              desc:
                  'Suppliers, raw materials, BOM, manufacturers, warehouses.',
            ),
            _SidebarRow(
              icon: Icons.shopping_cart_outlined,
              label: 'Orders',
              desc: 'Reorder Plan + order history.',
            ),
            _SidebarRow(
              icon: Icons.attach_money_outlined,
              label: 'Finance',
              desc: 'Cash flow and financial analytics.',
            ),
          ],
        ),
      ),
      _TourSlide(
        icon: Icons.alt_route_outlined,
        title: 'The setup path',
        subtitle:
            'Follow this order — each step depends on the one before it',
        body: const _StepList(steps: [
          _Step(
            number: '1',
            title: 'Suppliers',
            desc:
                'Who you buy from. Set lead times so reorder dates are accurate.',
          ),
          _Step(
            number: '2',
            title: 'Manufacturers',
            desc:
                'Only if you make products in-house or with partners. Skip if you only resell.',
          ),
          _Step(
            number: '3',
            title: 'Raw Materials',
            desc:
                'List materials and link each to its supplier. Manufacturing only.',
          ),
          _Step(
            number: '4',
            title: 'Warehouses',
            desc: 'Where stock lives. Single or multi-location.',
          ),
          _Step(
            number: '5',
            title: 'Products + unit cost',
            desc:
                'Shopify only imports the selling price — you must enter the unit cost yourself, otherwise every KPI is wrong.',
          ),
          _Step(
            number: '6',
            title: 'BOM (manufactured items)',
            desc:
                'Map each manufactured product to the raw materials it consumes.',
          ),
        ]),
        footer:
            'Suppliers + manufacturers + materials must exist BEFORE you set up products — products link back to them.',
      ),
      _TourSlide(
        icon: Icons.rocket_launch_outlined,
        title: 'Your first purchase order',
        subtitle: 'Once data is in, ordering takes 3 clicks',
        body: const _StepList(steps: [
          _Step(
            number: '1',
            title: 'Import demand data',
            desc:
                'Upload sales history (CSV) or sync from Shopify. The more data, the smarter the forecast.',
          ),
          _Step(
            number: '2',
            title: 'Open the Reorder Plan',
            desc:
                'Ma5zony lists every product that needs restocking with a suggested quantity.',
          ),
          _Step(
            number: '3',
            title: 'Approve → Purchase Order',
            desc:
                'Tick the items, hit Approve. A draft PO is created — email it to the supplier in one click.',
          ),
        ]),
      ),
      _TourSlide(
        icon: Icons.task_alt_outlined,
        title: "You're all set",
        subtitle: 'A few last tips',
        body: const _BulletList(items: [
          'A setup checklist on your dashboard tracks remaining tasks.',
          'Click any KPI card to drill into details.',
          'You can re-open this tour anytime from the dashboard header.',
          'Integrations → Connect Shopify to auto-import products & sales.',
        ]),
        footer: 'Start with Suppliers, or jump straight to the dashboard.',
      ),
    ];
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    } else {
      _finish(jumpTo: null);
    }
  }

  void _back() {
    if (_page > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish({String? jumpTo}) async {
    final state = context.read<AppState>();
    // Persist the completion flag so we don't auto-show again. Fire and
    // forget — UI shouldn't block on a network round trip.
    final updated = state.settings.copyWith(tourCompleted: true);
    unawaited(state.saveSettings(updated));
    if (!mounted) return;
    Navigator.of(context).pop(true);
    if (jumpTo != null) {
      // small post-frame delay so the dialog has time to dismiss before nav.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(jumpTo);
      });
    }
  }

  /// Marks the welcome tour as complete, dismisses the modal, then launches
  /// the spotlight coach that walks the user across screens highlighting the
  /// key sidebar destinations.
  Future<void> _startSpotlightTour() async {
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    final rootContext = context;
    final updated = state.settings.copyWith(tourCompleted: true);
    unawaited(state.saveSettings(updated));
    navigator.pop(true);
    // Wait for the modal to dismiss + first frame to render.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!rootContext.mounted) return;
    await SpotlightCoach.start(
      rootContext,
      const [
        SpotlightStep(
          anchorId: 'sidebar.group:Dashboard',
          title: 'Dashboard',
          description:
              'Your home base — KPIs, setup checklist, and any pending actions live here.',
          navigateTo: '/dashboard',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/suppliers',
          title: 'Step 1 — Suppliers',
          description:
              'Start here. Add every supplier you buy from — products and raw materials link back to these.',
          navigateTo: '/suppliers',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/manufacturers',
          title: 'Step 2 — Manufacturers',
          description:
              'Only if you make products in-house or with partners. Skip if you only resell.',
          navigateTo: '/manufacturers',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/raw-materials',
          title: 'Step 3 — Raw Materials',
          description:
              'List the materials you buy and link each to its supplier. Manufacturing only.',
          navigateTo: '/raw-materials',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/warehouses',
          title: 'Step 4 — Warehouses',
          description:
              'Where stock lives. Add at least one warehouse before adding products.',
          navigateTo: '/warehouses',
        ),
        SpotlightStep(
          anchorId: 'sidebar.group:Products',
          title: 'Step 5 — Products',
          description:
              'Now add your products. Shopify imports name & price — you MUST type the unit cost yourself or every KPI will be wrong.',
          navigateTo: '/products',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/bom',
          title: 'Step 6 — Bill of Materials',
          description:
              'For each manufactured product, map the raw materials it consumes. Required before production orders.',
          navigateTo: '/bom',
        ),
        SpotlightStep(
          anchorId: 'sidebar:/forecasts',
          title: 'Final step — Reorder Plan',
          description:
              'Once products & demand data are in, Ma5zony suggests exactly what to reorder and when.',
          navigateTo: '/forecasts',
        ),
      ],
      onNavigate: (path) {
        if (rootContext.mounted) rootContext.go(path);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;
    final isFirst = _page == 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with skip button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Step ${_page + 1} of ${_slides.length}',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    TextButton(
                      onPressed: () => _finish(jumpTo: null),
                      child: const Text('Skip tour'),
                    ),
                ],
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (ctx, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: active ? 22 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
            // Footer actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: isFirst ? null : _back,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  if (isLast) ...[
                    OutlinedButton(
                      onPressed: () => _finish(jumpTo: '/dashboard'),
                      child: const Text('Just go to Dashboard'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _startSpotlightTour,
                      icon: const Icon(Icons.tour_outlined, size: 18),
                      label: const Text('Show me around'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _next,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Next'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

class _TourSlide {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget body;
  final String? footer;
  const _TourSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    this.footer,
  });
}

class _SlideView extends StatelessWidget {
  final _TourSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(slide.title, style: AppTextStyles.h2),
          const SizedBox(height: 4),
          Text(
            slide.subtitle,
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          slide.body,
          if (slide.footer != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(slide.footer!,
                        style: AppTextStyles.bodySmall),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4, right: 10),
                      child: Icon(Icons.check_circle,
                          size: 16, color: AppColors.success),
                    ),
                    Expanded(
                        child:
                            Text(t, style: AppTextStyles.body)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  const _SidebarRow({
    required this.icon,
    required this.label,
    required this.desc,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final String number;
  final String title;
  final String desc;
  const _Step({
    required this.number,
    required this.title,
    required this.desc,
  });
}

class _StepList extends StatelessWidget {
  final List<_Step> steps;
  const _StepList({required this.steps});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps
          .map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      s.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: AppTextStyles.body
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(s.desc,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// End of file.
