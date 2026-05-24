import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final latest = state.latestCashFlow;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Cash Flow',
            actions: [
              ElevatedButton.icon(
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_file, size: 18),
                label: const Text('Import Data'),
                onPressed: _importing ? null : () => _showImportDialog(context, state),
              ),
            ],
          ),

          // KPI cards
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 220,
                child: KPICard(
                  title: 'Total Available',
                  value: latest != null
                      ? 'EGP ${latest.totalAvailable.toStringAsFixed(0)}'
                      : '—',
                  icon: Icons.account_balance,
                  color: AppColors.success,
                ),
              ),
              SizedBox(
                width: 220,
                child: KPICard(
                  title: 'Allocated to Production',
                  value: latest != null
                      ? 'EGP ${latest.allocatedToProduction.toStringAsFixed(0)}'
                      : '—',
                  icon: Icons.factory,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(
                width: 220,
                child: KPICard(
                  title: 'Remaining Budget',
                  value: latest != null
                      ? 'EGP ${latest.remainingBudget.toStringAsFixed(0)}'
                      : '—',
                  icon: Icons.account_balance_wallet,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Latest snapshot entries
          if (latest != null) ...[
            Text('Latest Snapshot (${_formatDate(latest.uploadedAt)})',
                style: AppTextStyles.h3),
            const SizedBox(height: 12),
            Card(
              child: HorizontallyScrollableTable(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Amount'), numeric: true),
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Notes')),
                  ],
                  rows: latest.entries.map((entry) {
                    final isNegative = entry.amount < 0;
                    return DataRow(cells: [
                      DataCell(Text(entry.category)),
                      DataCell(Text(
                        '${isNegative ? '-' : '+'}EGP ${entry.amount.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isNegative ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                      DataCell(Text(_formatDate(entry.date))),
                      DataCell(Text(entry.notes ?? '—')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.upload_file,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text(
                        'No cash flow data. Import your financial data to get started.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),

          // Historical snapshots
          if (state.cashFlowSnapshots.length > 1) ...[
            const SizedBox(height: 32),
            Text('History', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            Card(
              child: HorizontallyScrollableTable(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Total Available'), numeric: true),
                    DataColumn(label: Text('Allocated'), numeric: true),
                    DataColumn(label: Text('Remaining'), numeric: true),
                    DataColumn(label: Text('Entries')),
                  ],
                  rows: state.cashFlowSnapshots.map((s) {
                    return DataRow(cells: [
                      DataCell(Text(_formatDate(s.uploadedAt))),
                      DataCell(
                          Text('EGP ${s.totalAvailable.toStringAsFixed(0)}')),
                      DataCell(Text(
                          'EGP ${s.allocatedToProduction.toStringAsFixed(0)}')),
                      DataCell(
                          Text('EGP ${s.remainingBudget.toStringAsFixed(0)}')),
                      DataCell(Text('${s.entries.length}')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Import Cash Flow'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _pickExcelFile(context, state);
            },
            child: const ListTile(
              leading: Icon(Icons.table_chart, color: AppColors.primary),
              title: Text('Import from Excel'),
              subtitle: Text('Upload a .xlsx file with Category, Amount, Date, Notes columns'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              showDialog(
                context: context,
                builder: (_) => _ManualCashFlowDialog(
                  state: state,
                  onImported: () {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cash flow data imported'), duration: Duration(seconds: 3)),
                      );
                    }
                  },
                ),
              );
            },
            child: const ListTile(
              leading: Icon(Icons.edit_note, color: AppColors.primary),
              title: Text('Manual Entry'),
              subtitle: Text('Add income and expense rows manually'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExcelFile(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    setState(() => _importing = true);
    try {
      await state.importCashFlowFromExcel(bytes);
      messenger.showSnackBar(
        const SnackBar(content: Text('Excel data imported successfully'), duration: Duration(seconds: 3)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Import error: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ManualCashFlowDialog extends StatefulWidget {
  final AppState state;
  final VoidCallback onImported;
  const _ManualCashFlowDialog(
      {required this.state, required this.onImported});

  @override
  State<_ManualCashFlowDialog> createState() => _ManualCashFlowDialogState();
}

class _ManualCashFlowDialogState extends State<_ManualCashFlowDialog> {
  final List<_EntryRow> _rows = [];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.edit_note,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manual Cash Flow Entry', style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  'Add income (positive) and expense (negative) rows.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZohoFormSection(
                title: 'Entries',
                subtitle:
                    'Use negative amounts for expenses (e.g. -500 for a purchase).',
                children: [
                  ..._rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row.categoryCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Category', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: row.amountCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Amount',
                                  isDense: true,
                                  prefixText: 'EGP '),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: row.notesCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Notes', isDense: true),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove row',
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppColors.error),
                            onPressed: () => setState(() {
                              _rows[i].dispose();
                              _rows.removeAt(i);
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No entries yet. Click "Add Row" to start.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Row'),
                      onPressed: () =>
                          setState(() => _rows.add(_EntryRow())),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _saving || _rows.isEmpty ? null : _import,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Import'),
        ),
      ],
    );
  }

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      final rows = _rows.map((r) {
        return {
          'category': r.categoryCtrl.text.trim(),
          'amount': double.tryParse(r.amountCtrl.text.trim()) ?? 0,
          'date': DateTime.now().toIso8601String(),
          'notes': r.notesCtrl.text.trim(),
        };
      }).toList();
      await widget.state.importCashFlowFromRows(rows);
      if (mounted) {
        Navigator.pop(context);
        widget.onImported();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }
}

class _EntryRow {
  final TextEditingController categoryCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  void dispose() {
    categoryCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
  }
}
