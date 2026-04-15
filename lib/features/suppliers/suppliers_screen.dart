import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = state.suppliers;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Supplier Management',
            actions: [
              ElevatedButton.icon(
                onPressed: () => _showAddSupplierDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Supplier'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // KPI row
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Suppliers',
                  value: '${suppliers.length}',
                  icon: Icons.local_shipping,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Avg Lead Time',
                  value: suppliers.isEmpty
                      ? '—'
                      : '${(suppliers.fold<int>(0, (s, sup) => s + sup.typicalLeadTimeDays) / suppliers.length).toStringAsFixed(1)} days',
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Fast Suppliers (<7d)',
                  value:
                      '${suppliers.where((s) => s.typicalLeadTimeDays < 7).length}',
                  icon: Icons.flash_on,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (suppliers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No suppliers yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Add your first supplier to get started.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Supplier Name')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Lead Time')),
                  DataColumn(label: Text('Linked Products')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: suppliers.map((s) {
                  final linkedCount = state.products
                      .where((p) => p.supplierId == s.id)
                      .length;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          s.name,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(Text(s.contactEmail)),
                      DataCell(Text(s.phone ?? '—')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${s.typicalLeadTimeDays} days'),
                            const SizedBox(width: 8),
                            _LeadTimeChip(days: s.typicalLeadTimeDays),
                          ],
                        ),
                      ),
                      DataCell(Text('$linkedCount products')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () =>
                                  _showEditSupplierDialog(context, s),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 20,
                                color: AppColors.error,
                              ),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Supplier'),
                                    content: Text(
                                      'Delete "${s.name}"? This cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: AppColors.error)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  try {
                                    await context
                                        .read<AppState>()
                                        .deleteSupplier(s.id);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to delete supplier: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _SupplierFormDialog(supplier: null),
    );
  }

  void _showEditSupplierDialog(BuildContext context, Supplier supplier) {
    showDialog(
      context: context,
      builder: (ctx) => _SupplierFormDialog(supplier: supplier),
    );
  }
}

class _LeadTimeChip extends StatelessWidget {
  final int days;
  const _LeadTimeChip({required this.days});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    if (days < 7) {
      color = AppColors.success;
      label = 'Fast';
    } else if (days < 21) {
      color = AppColors.warning;
      label = 'Avg';
    } else {
      color = AppColors.error;
      label = 'Slow';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _SupplierFormDialog extends StatefulWidget {
  final Supplier? supplier;
  const _SupplierFormDialog({required this.supplier});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _leadTimeCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _emailCtrl = TextEditingController(text: s?.contactEmail ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _leadTimeCtrl = TextEditingController(
      text: s != null ? '${s.typicalLeadTimeDays}' : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _leadTimeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Supplier' : 'Add New Supplier'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Supplier Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contact Email',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _leadTimeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lead Time (days)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Lead time is required';
                    final val = int.tryParse(v);
                    if (val == null || val < 1) return 'Enter a positive number';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final supplier = Supplier(
              id: widget.supplier?.id ?? '',
              name: _nameCtrl.text.trim(),
              contactEmail: _emailCtrl.text.trim(),
              phone: _phoneCtrl.text.trim().isEmpty
                  ? null
                  : _phoneCtrl.text.trim(),
              typicalLeadTimeDays:
                  int.tryParse(_leadTimeCtrl.text) ?? 0,
            );
            final appState = context.read<AppState>();
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(context);
            try {
              if (isEdit) {
                await appState.updateSupplier(supplier);
              } else {
                await appState.addSupplier(supplier);
              }
              nav.pop();
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Failed to save supplier: $e'), backgroundColor: Colors.red),
              );
            }
          },
          child: Text(isEdit ? 'Save Changes' : 'Add Supplier'),
        ),
      ],
    );
  }
}
