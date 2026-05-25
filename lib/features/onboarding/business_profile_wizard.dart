import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';

/// Phase 1.1 — Tell-us-about-your-business wizard.
///
/// One-time, 3 questions, ~30 seconds. Result is persisted as
/// `UserSettings.businessProfile` and drives the sidebar, terminology, and
/// hidden screens. Existing users (those who signed up before this feature)
/// also pass through here once on next login because the router redirects
/// while `businessProfile == null`.
class BusinessProfileWizard extends StatefulWidget {
  const BusinessProfileWizard({super.key});

  @override
  State<BusinessProfileWizard> createState() => _BusinessProfileWizardState();
}

class _BusinessProfileWizardState extends State<BusinessProfileWizard> {
  int _step = 0;
  String? _stockMode;
  String? _sourcing;
  final Set<String> _channels = {};
  bool _saving = false;

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _stockMode != null;
      case 1:
        return _sourcing != null;
      case 2:
        return _channels.isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    setState(() => _saving = true);
    try {
      final profile = BusinessProfile(
        stockMode: _stockMode!,
        sourcing: _sourcing!,
        channels: _channels.toList()..sort(),
      );
      await state.saveSettings(
        state.settings.copyWith(businessProfile: profile),
      );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                _Header(step: _step),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildStep(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _step == 0 || _saving
                          ? null
                          : () => setState(() => _step -= 1),
                      child: const Text('Back'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _step
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                      ],
                    ),
                    FilledButton(
                      onPressed: !_canContinue || _saving
                          ? null
                          : () {
                              if (_step < 2) {
                                setState(() => _step += 1);
                              } else {
                                _save();
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_step < 2 ? 'Continue' : 'Finish setup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepStock(
          key: const ValueKey('stock'),
          selected: _stockMode,
          onChanged: (v) => setState(() => _stockMode = v),
        );
      case 1:
        return _StepSourcing(
          key: const ValueKey('sourcing'),
          selected: _sourcing,
          onChanged: (v) => setState(() => _sourcing = v),
        );
      case 2:
        return _StepChannels(
          key: const ValueKey('channels'),
          selected: _channels,
          onToggle: (v) => setState(() {
            if (_channels.contains(v)) {
              _channels.remove(v);
            } else {
              _channels.add(v);
            }
          }),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int step;
  const _Header({required this.step});

  static const _titles = [
    'How do you keep stock?',
    'Where do products come from?',
    'How do you sell?',
  ];
  static const _subtitles = [
    'We\'ll tailor warehouses, fulfilment, and the sidebar to match.',
    'Decides whether you see suppliers, manufacturers, or both.',
    'Pick every channel you sell through — you can add more later.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${step + 1} of 3',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSubdued,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _titles[step],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _subtitles[step],
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

// ── Choice card primitive ──────────────────────────────────────────────────

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.white,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : AppColors.border.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: 22,
                  color: selected ? Colors.white : AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1: Stock ──────────────────────────────────────────────────────────

class _StepStock extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onChanged;
  const _StepStock({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChoiceCard(
          icon: Icons.store_outlined,
          title: 'One location',
          body: 'A single shop, studio, or warehouse.',
          selected: selected == 'single',
          onTap: () => onChanged('single'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.warehouse_outlined,
          title: 'Multiple locations',
          body: 'Several branches or warehouses with their own stock.',
          selected: selected == 'multi',
          onTap: () => onChanged('multi'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.local_shipping_outlined,
          title: 'I don\'t hold stock (dropship / print-on-demand)',
          body: 'A partner fulfils every order. We\'ll hide warehouses.',
          selected: selected == 'dropship',
          onTap: () => onChanged('dropship'),
        ),
      ],
    );
  }
}

// ── Step 2: Sourcing ───────────────────────────────────────────────────────

class _StepSourcing extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onChanged;
  const _StepSourcing(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChoiceCard(
          icon: Icons.shopping_bag_outlined,
          title: 'I buy finished products to resell',
          body: 'You\'ll work with suppliers and purchase orders.',
          selected: selected == 'buy',
          onTap: () => onChanged('buy'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.precision_manufacturing_outlined,
          title: 'I make products from raw materials',
          body: 'You\'ll work with BOMs, raw materials, and manufacturers.',
          selected: selected == 'make',
          onTap: () => onChanged('make'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.compare_arrows,
          title: 'Both — I make some and resell others',
          body: 'Every workflow stays available.',
          selected: selected == 'both',
          onTap: () => onChanged('both'),
        ),
      ],
    );
  }
}

// ── Step 3: Channels ───────────────────────────────────────────────────────

class _StepChannels extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _StepChannels(
      {super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChoiceCard(
          icon: Icons.shopping_cart_outlined,
          title: 'Online store (Shopify)',
          body: 'Sync products, sales, and stock with your Shopify shop.',
          selected: selected.contains('shopify'),
          onTap: () => onToggle('shopify'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.storefront_outlined,
          title: 'In-store / point of sale',
          body: 'Walk-in customers paying at the counter.',
          selected: selected.contains('instore'),
          onTap: () => onToggle('instore'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.handshake_outlined,
          title: 'Wholesale / B2B',
          body: 'You sell in bulk to other businesses with custom pricing.',
          selected: selected.contains('wholesale'),
          onTap: () => onToggle('wholesale'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          icon: Icons.public,
          title: 'Marketplaces (Amazon, Etsy, etc.)',
          body: 'Listings on third-party marketplaces.',
          selected: selected.contains('marketplace'),
          onTap: () => onToggle('marketplace'),
        ),
      ],
    );
  }
}
