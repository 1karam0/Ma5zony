import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/abc_xyz_service.dart';
import 'package:ma5zony/utils/constants.dart';

/// Visualises the 9-cell ABC-XYZ classification matrix and lets the user
/// drill into the products inside each cell.
///
/// Powered by [AppState.classifyProducts] / [AppState.abcXyzMatrix].
class AbcXyzScreen extends StatefulWidget {
  const AbcXyzScreen({super.key});

  @override
  State<AbcXyzScreen> createState() => _AbcXyzScreenState();
}

class _AbcXyzScreenState extends State<AbcXyzScreen> {
  String? _selectedCell; // e.g. "AX"

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matrix = state.abcXyzMatrix;
    final summary = state.abcXyzSummary;
    final productsById = {for (final p in state.products) p.id: p};

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ABC-XYZ Classification',
                        style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Text(
                      'Classify products by value (ABC) and demand variability (XYZ) to drive differentiated inventory policies.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.read<AppState>().classifyProducts(),
                icon: const Icon(Icons.refresh),
                label: const Text('Run Classification'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (matrix.isEmpty)
            _emptyState()
          else ...[
            _summaryCards(matrix.length, summary),
            const SizedBox(height: 20),
            _matrixGrid(summary),
            const SizedBox(height: 20),
            if (_selectedCell != null)
              _cellDetail(
                cell: _selectedCell!,
                matrix: matrix,
                productsById: productsById,
              ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.grid_view_outlined,
              size: 56, color: AppColors.textSubdued),
          const SizedBox(height: 12),
          Text('No classification yet', style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text(
            'Click "Run Classification" to compute the ABC-XYZ matrix from your products and demand history.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _summaryCards(int total, Map<String, int> summary) {
    final aCount = (summary['AX'] ?? 0) + (summary['AY'] ?? 0) + (summary['AZ'] ?? 0);
    final bCount = (summary['BX'] ?? 0) + (summary['BY'] ?? 0) + (summary['BZ'] ?? 0);
    final cCount = (summary['CX'] ?? 0) + (summary['CY'] ?? 0) + (summary['CZ'] ?? 0);
    final xCount = (summary['AX'] ?? 0) + (summary['BX'] ?? 0) + (summary['CX'] ?? 0);
    final yCount = (summary['AY'] ?? 0) + (summary['BY'] ?? 0) + (summary['CY'] ?? 0);
    final zCount = (summary['AZ'] ?? 0) + (summary['BZ'] ?? 0) + (summary['CZ'] ?? 0);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 800;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryCard('Total SKUs', '$total', AppColors.textPrimary,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class A', '$aCount', AppColors.classA,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class B', '$bCount', AppColors.classB,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class C', '$cCount', AppColors.classC,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class X', '$xCount', AppColors.classX,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class Y', '$yCount', AppColors.classY,
              width: wide ? 140 : c.maxWidth),
          _summaryCard('Class Z', '$zCount', AppColors.classZ,
              width: wide ? 140 : c.maxWidth),
        ],
      );
    });
  }

  Widget _summaryCard(String label, String value, Color color,
      {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.kpi),
        ],
      ),
    );
  }

  Widget _matrixGrid(Map<String, int> summary) {
    const rows = ['A', 'B', 'C'];
    const cols = ['X', 'Y', 'Z'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('9-Cell Matrix', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text(
              'ABC (rows) = value · XYZ (columns) = predictability. Click a cell for details.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(children: [
                  const SizedBox(width: 40),
                  for (final c in cols) _matrixHeader(c),
                ]),
                for (final r in rows)
                  TableRow(children: [
                    _matrixHeader(r),
                    for (final c in cols)
                      _matrixCell(r, c, summary['$r$c'] ?? 0),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _matrixHeader(String label) => Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );

  Widget _matrixCell(String r, String c, int count) {
    final cell = '$r$c';
    final isSelected = _selectedCell == cell;
    final color = _cellColor(cell);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: count > 0 ? () => setState(() => _selectedCell = cell) : null,
        borderRadius: AppRadius.sm,
        child: Container(
          width: 120, height: 80,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isSelected ? 0.25 : 0.10),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: AppRadius.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(cell,
                  style: AppTextStyles.h3.copyWith(color: color)),
              const SizedBox(height: 2),
              Text('$count SKU${count == 1 ? '' : 's'}',
                  style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Color _cellColor(String cell) {
    // Blend: severity comes mostly from the XYZ class
    if (cell.endsWith('X')) return AppColors.classX;
    if (cell.endsWith('Y')) return AppColors.classY;
    return AppColors.classZ;
  }

  Widget _cellDetail({
    required String cell,
    required Map<String, ProductClassification> matrix,
    required Map<String, dynamic> productsById,
  }) {
    final items =
        matrix.values.where((c) => c.label == cell).toList(growable: false);
    final sample = items.isNotEmpty ? items.first : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cellColor(cell).withValues(alpha: 0.15),
                    borderRadius: AppRadius.sm,
                  ),
                  child: Text(cell,
                      style: AppTextStyles.h3
                          .copyWith(color: _cellColor(cell))),
                ),
                const SizedBox(width: 12),
                Text('${items.length} product${items.length == 1 ? '' : 's'}',
                    style: AppTextStyles.body),
                const Spacer(),
                if (sample != null)
                  Chip(
                    label: Text(
                      'Recommended: ${sample.recommendedAlgorithm}',
                      style: AppTextStyles.bodySmall,
                    ),
                    backgroundColor: AppColors.background,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (sample != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadius.sm,
                ),
                child: Text(sample.strategy, style: AppTextStyles.body),
              ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text('No products in this cell.',
                  style: AppTextStyles.bodySmall)
            else
              Column(
                children: [
                  for (final item in items.take(20))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              productsById[item.productId]?.name ??
                                  item.productId,
                              style: AppTextStyles.body,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(item.recommendedAlgorithm,
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  if (items.length > 20)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+ ${items.length - 20} more',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
