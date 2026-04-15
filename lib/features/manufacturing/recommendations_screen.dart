import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = {for (final p in state.products) p.id: p.name};

    final pending = state.mfgRecommendations
        .where((r) => r.status == RecommendationStatus.pending)
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    final approved = state.mfgRecommendations
        .where((r) => r.status == RecommendationStatus.approved)
        .toList();
    final rejected = state.mfgRecommendations
        .where((r) => r.status == RecommendationStatus.rejected)
        .toList();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Manufacturing Recommendations',
            actions: [
              ElevatedButton.icon(
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate'),
                onPressed: _generating ? null : () => _generate(state),
              ),
            ],
          ),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Pending',
                  value: '${pending.length}',
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Approved',
                  value: '${approved.length}',
                  icon: Icons.check_circle,
                  color: AppColors.success,
                ),
              ),
              if (state.latestCashFlow != null)
                SizedBox(
                  width: 200,
                  child: KPICard(
                    title: 'Available Budget',
                    value:
                        '\$${state.latestCashFlow!.remainingBudget.toStringAsFixed(0)}',
                    icon: Icons.account_balance_wallet,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Pending Recommendations
          if (pending.isNotEmpty) ...[
            Text('Pending Review', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            ...pending.map((rec) => _RecommendationCard(
                  rec: rec,
                  productName: products[rec.productId] ?? 'Unknown',
                  manufacturers: state.manufacturers,
                  onApprove: (manufacturerId) =>
                      _approve(state, rec, manufacturerId),
                  onReject: () => _reject(state, rec),
                )),
            const SizedBox(height: 24),
          ],

          // Approved
          if (approved.isNotEmpty) ...[
            Text('Approved', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            ...approved.map((rec) => _RecommendationCard(
                  rec: rec,
                  productName: products[rec.productId] ?? 'Unknown',
                  manufacturers: state.manufacturers,
                )),
            const SizedBox(height: 24),
          ],

          // Rejected
          if (rejected.isNotEmpty) ...[
            Text('Rejected', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            ...rejected.map((rec) => _RecommendationCard(
                  rec: rec,
                  productName: products[rec.productId] ?? 'Unknown',
                  manufacturers: state.manufacturers,
                )),
          ],

          if (state.mfgRecommendations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text(
                        'No recommendations yet. Click "Generate" to analyze your inventory.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _generate(AppState state) async {
    setState(() => _generating = true);
    try {
      await state.generateMfgRecommendations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recommendations generated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _approve(AppState state, ManufacturingRecommendation rec,
      String manufacturerId) async {
    try {
      await state.approveMfgRecommendation(rec, manufacturerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Approved — production order & material orders created')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _reject(AppState state, ManufacturingRecommendation rec) async {
    try {
      await state.rejectMfgRecommendation(rec);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _RecommendationCard extends StatelessWidget {
  final ManufacturingRecommendation rec;
  final String productName;
  final List<dynamic> manufacturers;
  final void Function(String manufacturerId)? onApprove;
  final VoidCallback? onReject;

  const _RecommendationCard({
    required this.rec,
    required this.productName,
    required this.manufacturers,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = rec.status == RecommendationStatus.pending;
    final statusColor = switch (rec.status) {
      RecommendationStatus.pending => AppColors.warning,
      RecommendationStatus.approved => AppColors.success,
      RecommendationStatus.rejected => AppColors.error,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(productName, style: AppTextStyles.h3),
                ),
                _PriorityBadge(priority: rec.priority),
                const SizedBox(width: 8),
                Chip(
                  label: Text(rec.status.name.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(rec.reasoning, style: AppTextStyles.body),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _InfoChip(
                    label: 'Quantity', value: '${rec.suggestedQty} units'),
                _InfoChip(
                    label: 'Cost',
                    value: '\$${rec.estimatedCost.toStringAsFixed(0)}'),
                _InfoChip(
                    label: 'Timeline',
                    value: '${rec.estimatedTimeline} days'),
                if (rec.cashConstraint)
                  const Chip(
                    avatar:
                        Icon(Icons.warning, size: 16, color: AppColors.warning),
                    label: Text('Cash Constrained',
                        style: TextStyle(fontSize: 12)),
                    backgroundColor: Color(0xFFFFF3E0),
                    side: BorderSide.none,
                  ),
              ],
            ),
            if (isPending && onApprove != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _showManufacturerPicker(context),
                    child: const Text('Approve & Assign'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showManufacturerPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Select Manufacturer'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (manufacturers.isEmpty)
                    const Text('No manufacturers available. Add one first.')
                  else
                    ...manufacturers.map((m) {
                      final mfr = m as dynamic;
                      final mfrId = mfr.id as String;
                      final isSelected = selected == mfrId;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected ? AppColors.primary : null,
                        ),
                        title: Text(mfr.name as String),
                        subtitle: Text(
                            '${mfr.productionCapacity} units, ${mfr.typicalProductionDays} days'),
                        onTap: () =>
                            setDialogState(() => selected = mfrId),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        onApprove!(selected!);
                      },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final double priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = priority > 70
        ? AppColors.error
        : priority > 40
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'P ${priority.round()}',
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        Text(value, style: AppTextStyles.body),
      ],
    );
  }
}
