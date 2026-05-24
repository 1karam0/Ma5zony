import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/manufacturer.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

class ManufacturersScreen extends StatefulWidget {
  const ManufacturersScreen({super.key});

  @override
  State<ManufacturersScreen> createState() => _ManufacturersScreenState();
}

class _ManufacturersScreenState extends State<ManufacturersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final manufacturers = state.manufacturers.where((m) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.contactEmail.toLowerCase().contains(q);
    }).toList();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Manufacturers',
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Manufacturer'),
                onPressed: () => _showFormDialog(context, state),
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
                  title: 'Total',
                  value: '${state.manufacturers.length}',
                  icon: Icons.factory,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Avg Lead Time',
                  value: state.manufacturers.isEmpty
                      ? '—'
                      : '${(state.manufacturers.fold<int>(0, (s, m) => s + m.typicalProductionDays) / state.manufacturers.length).round()} days',
                  icon: Icons.schedule,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 300,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search manufacturers...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Capacity')),
                  DataColumn(label: Text('Lead Time')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: manufacturers.map((m) {
                  return DataRow(cells: [
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(m.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (m.address != null && m.address!.isNotEmpty)
                          Text(m.address!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    DataCell(Text(m.contactEmail)),
                    DataCell(Text(m.phone ?? '—')),
                    DataCell(Text('${m.productionCapacity} units')),
                    DataCell(Text('${m.typicalProductionDays} days')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: () =>
                              _showFormDialog(context, state, existing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          tooltip: 'Delete',
                          color: AppColors.error,
                          onPressed: () => _confirmDelete(context, state, m),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
          if (manufacturers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.factory_outlined,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('No manufacturers yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFormDialog(BuildContext context, AppState state,
      {Manufacturer? existing}) {
    showDialog(
      context: context,
      builder: (_) =>
          _ManufacturerFormDialog(state: state, existing: existing),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state, Manufacturer m) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Manufacturer'),
        content: Text('Delete "${m.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await state.deleteManufacturer(m.id);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Manufacturer deleted'), duration: Duration(seconds: 3)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(duration: const Duration(seconds: 3), content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ManufacturerFormDialog extends StatefulWidget {
  final AppState state;
  final Manufacturer? existing;

  const _ManufacturerFormDialog({required this.state, this.existing});

  @override
  State<_ManufacturerFormDialog> createState() =>
      _ManufacturerFormDialogState();
}

class _ManufacturerFormDialogState extends State<_ManufacturerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _leadTimeCtrl;
  late final TextEditingController _addressCtrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _emailCtrl = TextEditingController(text: e?.contactEmail ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _capacityCtrl = TextEditingController(
        text: e != null ? '${e.productionCapacity}' : '');
    _leadTimeCtrl = TextEditingController(
        text: e != null ? '${e.typicalProductionDays}' : '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _capacityCtrl.dispose();
    _leadTimeCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

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
            child: const Icon(Icons.precision_manufacturing_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEdit ? 'Edit Manufacturer' : 'New Manufacturer',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  _isEdit
                      ? 'Update production capacity and contact details.'
                      : 'Add a production partner to assign jobs to.',
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
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ZohoFormSection(
                  title: 'Contact Details',
                  subtitle: 'How your team reaches this manufacturer.',
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Contact Email *'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Phone'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ZohoFormSection(
                  title: 'Production',
                  subtitle:
                      'Capacity caps batch sizes; lead time drives planning.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _capacityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Production Capacity *',
                              suffixText: 'units',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (int.tryParse(v) == null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _leadTimeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Typical Production Time *',
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (int.tryParse(v) == null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ZohoFormSection(
                  title: 'Location',
                  subtitle: 'Optional — useful for logistics planning.',
                  collapsible: true,
                  initiallyExpanded: false,
                  children: [
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: 'e.g. 10 Factory St, Industrial Zone',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ],
            ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Save Changes' : 'Add Manufacturer'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final manufacturer = Manufacturer(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        productionCapacity: int.parse(_capacityCtrl.text.trim()),
        typicalProductionDays: int.parse(_leadTimeCtrl.text.trim()),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
      );
      if (_isEdit) {
        await widget.state.updateManufacturer(manufacturer);
      } else {
        await widget.state.addManufacturer(manufacturer);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 3),
              content:
                  Text(_isEdit ? 'Manufacturer updated' : 'Manufacturer added')),
        );
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
}
