import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';
import 'package:ma5zony/features/onboarding/tour_targets.dart';

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
              KeyedSubtree(
                key: TourTargets.instance.keyFor('page:suppliers.add'),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddSupplierDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Supplier'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
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
            EmptyStateWidget(
              icon: Icons.local_shipping_outlined,
              title: 'No suppliers yet',
              description: 'Add your first supplier to track lead times and manage orders.',
              primaryLabel: 'Add Supplier',
              onPrimary: () => _showAddSupplierDialog(context),
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
                  DataColumn(label: Text('Rating')),
                  DataColumn(label: Text('Linked Products')),
                  DataColumn(label: Text('Raw Materials')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: suppliers.map((s) {
                  final linkedProductCount = state.products
                      .where((p) => p.supplierId == s.id)
                      .length;
                  final linkedRMs = state.rawMaterials
                      .where((r) => s.suppliedRawMaterialIds.contains(r.id))
                      .toList();
                  return DataRow(
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((s.address ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        size: 12,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 2),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 220),
                                      child: Text(
                                        s.address!.split('\n').first,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.label.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
                      DataCell(_PerformanceRating(rating: s.performanceRating)),
                      DataCell(Text('$linkedProductCount products')),
                      DataCell(
                        InkWell(
                          onTap: linkedRMs.isEmpty
                              ? null
                              : () => showDialog(
                                    context: context,
                                    builder: (_) => _LinkedRmDialog(
                                      supplierName: s.name,
                                      rawMaterials: linkedRMs,
                                    ),
                                  ),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: linkedRMs.isEmpty
                                  ? AppColors.border
                                  : AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 12,
                                    color: linkedRMs.isEmpty
                                        ? AppColors.textSecondary
                                        : AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '${linkedRMs.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: linkedRMs.isEmpty
                                        ? AppColors.textSecondary
                                        : AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
                                        SnackBar(duration: const Duration(seconds: 3), content: Text('Failed to delete supplier: $e')),
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
      useRootNavigator: false,
      builder: (ctx) => const _SupplierFormDialog(supplier: null),
    );
  }

  void _showEditSupplierDialog(BuildContext context, Supplier supplier) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => _SupplierFormDialog(supplier: supplier),
    );
  }
}

// ─── Linked RM Dialog ─────────────────────────────────────────────────────────

class _LinkedRmDialog extends StatelessWidget {
  final String supplierName;
  final List<dynamic> rawMaterials;

  const _LinkedRmDialog({
    required this.supplierName,
    required this.rawMaterials,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Raw Materials — $supplierName'),
      content: SizedBox(
        width: 400,
        child: rawMaterials.isEmpty
            ? const Text('No raw materials linked to this supplier.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: rawMaterials.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final rm = rawMaterials[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.circle, size: 8,
                        color: AppColors.primary),
                    title: Text(rm.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${rm.sku}  ·  ${rm.unitOfMeasure}  ·  EGP ${rm.unitCost.toStringAsFixed(2)}/unit'),
                    trailing: rm.currentStock <= rm.safetyStock
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Low Stock',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                          )
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _PerformanceRating extends StatelessWidget {
  final double? rating;
  const _PerformanceRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    if (rating == null) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final stars = rating!.clamp(0.0, 5.0);
    final color = stars >= 4.0
        ? AppColors.success
        : (stars >= 2.5 ? AppColors.warning : AppColors.error);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          stars.toStringAsFixed(1),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
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

// ─── Supplier Form Dialog ─────────────────────────────────────────────────────

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
  late final TextEditingController _ratingCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _mapsUrlCtrl;
  double? _latitude;
  double? _longitude;
  late Set<String> _selectedRawMaterialIds;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _selectedRawMaterialIds =
        Set<String>.from(s?.suppliedRawMaterialIds ?? const []);
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _emailCtrl = TextEditingController(text: s?.contactEmail ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _leadTimeCtrl = TextEditingController(
      text: s != null ? '${s.typicalLeadTimeDays}' : '',
    );
    _ratingCtrl = TextEditingController(
      text: s?.performanceRating != null
          ? s!.performanceRating!.toStringAsFixed(1)
          : '',
    );
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _latitude = s?.latitude;
    _longitude = s?.longitude;
    _mapsUrlCtrl = TextEditingController(
      text: (s?.latitude != null && s?.longitude != null)
          ? 'https://www.google.com/maps?q=${s!.latitude},${s.longitude}'
          : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _leadTimeCtrl.dispose();
    _ratingCtrl.dispose();
    _addressCtrl.dispose();
    _mapsUrlCtrl.dispose();
    super.dispose();
  }

  /// Extracts (lat, lng) from a Google Maps URL.
  /// Supports common formats: ?q=lat,lng | @lat,lng,zoom | !3dlat!4dlng
  (double, double)? _parseGoogleMapsLatLng(String url) {
    if (url.trim().isEmpty) return null;
    // Pattern 1: @lat,lng — most common in browser share links
    final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }
    // Pattern 2: ?q=lat,lng or &q=lat,lng
    final qMatch = RegExp(r'[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1)!);
      final lng = double.tryParse(qMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }
    // Pattern 3: !3dlat!4dlng (encoded share URLs)
    final bangMatch =
        RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(url);
    if (bangMatch != null) {
      final lat = double.tryParse(bangMatch.group(1)!);
      final lng = double.tryParse(bangMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }
    return null;
  }

  void _onMapsUrlChanged(String url) {
    final coords = _parseGoogleMapsLatLng(url);
    if (coords != null) {
      setState(() {
        _latitude = coords.$1;
        _longitude = coords.$2;
      });
    }
  }

  Future<void> _openInMaps() async {
    String? url;
    if (_latitude != null && _longitude != null) {
      url = 'https://www.google.com/maps?q=$_latitude,$_longitude';
    } else if (_addressCtrl.text.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(_addressCtrl.text.trim());
      url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
    }
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ratingText = _ratingCtrl.text.trim();
    final isEdit = widget.supplier != null;
    final supplier = Supplier(
      id: widget.supplier?.id ?? '',
      name: _nameCtrl.text.trim(),
      contactEmail: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      typicalLeadTimeDays: int.tryParse(_leadTimeCtrl.text) ?? 0,
      performanceRating:
          ratingText.isEmpty ? null : double.tryParse(ratingText),
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      suppliedRawMaterialIds: _selectedRawMaterialIds.toList(),
    );
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    try {
      if (isEdit) {
        await appState.updateSupplier(supplier);
      } else {
        await appState.addSupplier(supplier);
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(isEdit ? 'Supplier updated' : 'Supplier added')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Failed to save supplier: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;
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
            child: const Icon(Icons.local_shipping_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEdit ? 'Edit Supplier' : 'New Supplier',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  isEdit
                      ? 'Update supplier contact, lead time and location.'
                      : 'Add a vendor that delivers products or raw materials.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.pop(context),
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
              children: [
                // ── Section 1: Contact Details ───────────────────────────
                ZohoFormSection(
                  title: 'Contact Details',
                  subtitle: 'How your team reaches this supplier.',
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Supplier Name *'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Contact Email *',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              final emailRegex =
                                  RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                              if (!emailRegex.hasMatch(v.trim())) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Phone'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Section 2: Performance ───────────────────────────────
                ZohoFormSection(
                  title: 'Performance',
                  subtitle:
                      'Lead time drives reorder point. Rating ranks suppliers when ordering.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _leadTimeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Lead Time *',
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Lead time is required';
                              }
                              final val = int.tryParse(v);
                              if (val == null || val < 1) {
                                return 'Enter a positive number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _ratingCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Performance Rating (optional)',
                              hintText: 'e.g. 4.5',
                              suffixText: '/ 5',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final val = double.tryParse(v.trim());
                              if (val == null || val < 0 || val > 5) {
                                return 'Enter a value between 0 and 5';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Section 3: Materials Supplied ────────────────────
                _RawMaterialsPicker(
                  selectedIds: _selectedRawMaterialIds,
                  onChanged: (ids) =>
                      setState(() => _selectedRawMaterialIds = ids),
                ),

                // ── Section 4: Location (collapsible) ────────────────────
                ZohoFormSection(
                  title: 'Location',
                  subtitle:
                      'Optional — pin a Maps location for logistics & ETA.',
                  collapsible: true,
                  initiallyExpanded: false,
                  children: [
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: 'e.g. 15 Industrial Zone, Cairo',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mapsUrlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Google Maps link',
                        hintText: 'Paste link from Google Maps → Share',
                        prefixIcon: const Icon(Icons.map_outlined),
                        helperText: (_latitude != null && _longitude != null)
                            ? 'Location pinned: '
                                '${_latitude!.toStringAsFixed(5)}, '
                                '${_longitude!.toStringAsFixed(5)}'
                            : 'Paste a Maps URL to pin exact coordinates',
                        helperMaxLines: 2,
                        suffixIcon: IconButton(
                          tooltip: 'Open in Google Maps',
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: _openInMaps,
                        ),
                      ),
                      onChanged: _onMapsUrlChanged,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(isEdit ? 'Save Changes' : 'Add Supplier'),
        ),
      ],
    );
  }
}

enum _ChipAction { edit, delete }

/// Multi-select chip picker for the raw materials this supplier carries.
/// A single vendor commonly delivers many materials, so we expose all of
/// them and let the user toggle them on/off.
class _RawMaterialsPicker extends StatelessWidget {
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const _RawMaterialsPicker({
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final rawMaterials = context.watch<AppState>().rawMaterials;
    return ZohoFormSection(
      title: 'Materials Supplied',
      subtitle:
          'Tick every raw material this supplier can deliver. Used when '
          'auto-generating purchase orders.',
      collapsible: true,
      initiallyExpanded: selectedIds.isNotEmpty,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...rawMaterials.map((rm) {
              final isSelected = selectedIds.contains(rm.id);
              return GestureDetector(
                onLongPress: () async {
                  final action = await _showChipContextMenu(context, rm);
                  if (action == _ChipAction.edit) {
                    await _showEditMaterialDialog(context, rm);
                  } else if (action == _ChipAction.delete) {
                    final confirmed = await _confirmDeleteMaterial(context, rm.name);
                    if (confirmed == true && context.mounted) {
                      await context.read<AppState>().deleteRawMaterial(rm.id);
                      final next = Set<String>.from(selectedIds)..remove(rm.id);
                      onChanged(next);
                    }
                  }
                },
                child: FilterChip(
                  label: Text(rm.name),
                  selected: isSelected,
                  onSelected: (val) {
                    final next = Set<String>.from(selectedIds);
                    if (val) {
                      next.add(rm.id);
                    } else {
                      next.remove(rm.id);
                    }
                    onChanged(next);
                  },
                ),
              );
            }),
            // "+ New material" chip — creates a raw material inline and
            // auto-selects it so the user never has to leave this form.
            ActionChip(
              avatar: const Icon(Icons.add, size: 14, color: AppColors.primary),
              label: const Text('New material\u2026',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
              onPressed: () async {
                final newId =
                    await _showQuickMaterialDialog(context);
                if (newId != null) {
                  final next = Set<String>.from(selectedIds)..add(newId);
                  onChanged(next);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ── Selected materials bar ──────────────────────────────────────
        // Always shown; gives clear visual confirmation of what is linked.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selectedIds.isEmpty
                ? AppColors.border.withValues(alpha: 0.4)
                : AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selectedIds.isEmpty
                  ? AppColors.divider
                  : AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: selectedIds.isEmpty
              ? Row(
                  children: [
                    Icon(Icons.link_off,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('No materials linked yet — tick chips above to link.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link,
                            size: 13, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('Linked:',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    ...rawMaterials
                        .where((rm) => selectedIds.contains(rm.id))
                        .map((rm) => InputChip(
                              label: Text(rm.name,
                                  style: AppTextStyles.bodySmall.copyWith(
                                      fontWeight: FontWeight.w500)),
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              side: BorderSide(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.35)),
                              deleteIconColor: AppColors.primary,
                              onDeleted: () {
                                final next = Set<String>.from(selectedIds)
                                  ..remove(rm.id);
                                onChanged(next);
                              },
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 0),
                            )),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Text(
          'Long-press any chip above to edit or delete that material.',
          style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  /// Long-press popup: returns the chosen action (edit / delete) or null.
  Future<_ChipAction?> _showChipContextMenu(
      BuildContext context, RawMaterial rm) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final offset = button.localToGlobal(
        Offset(button.size.width / 2, button.size.height / 2),
        ancestor: overlay);
    return showMenu<_ChipAction>(
      context: context,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy, offset.dx + 1, offset.dy + 1),
      items: [
        PopupMenuItem(
          value: _ChipAction.edit,
          child: Row(
            children: const [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('Edit material'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ChipAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red[700]),
              const SizedBox(width: 8),
              Text('Delete material',
                  style: TextStyle(color: Colors.red[700])),
            ],
          ),
        ),
      ],
    );
  }

  /// Pre-filled edit dialog for an existing raw material.
  Future<void> _showEditMaterialDialog(
      BuildContext context, RawMaterial rm) {
    final nameCtrl = TextEditingController(text: rm.name);
    final costCtrl = TextEditingController(
        text: rm.unitCost > 0 ? rm.unitCost.toString() : '');
    final formKey = GlobalKey<FormState>();
    String uom = rm.unit.isNotEmpty ? rm.unit : 'units';
    const uoms = ['units', 'g', 'kg', 'm', 'cm', 'L', 'mL', 'pcs'];

    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Raw Material'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Material Name *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: costCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Unit Cost', prefixText: 'EGP '),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: uoms.contains(uom) ? uom : 'units',
                          decoration:
                              const InputDecoration(labelText: 'Unit'),
                          items: uoms
                              .map((u) => DropdownMenuItem(
                                  value: u, child: Text(u)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => uom = v ?? 'units'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final updated = RawMaterial(
                  id: rm.id,
                  name: nameCtrl.text.trim(),
                  sku: rm.sku,
                  unit: uom,
                  unitOfMeasure: uom,
                  unitCost: double.tryParse(costCtrl.text.trim()) ?? rm.unitCost,
                  currentStock: rm.currentStock,
                  safetyStock: rm.safetyStock,
                  leadTimeDays: rm.leadTimeDays,
                );
                await ctx.read<AppState>().updateRawMaterial(updated);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirm before deleting a material globally.
  Future<bool?> _confirmDeleteMaterial(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete material?'),
        content: Text(
            '"$name" will be permanently removed from your inventory and '
            'unlinked from all suppliers. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Shows a compact dialog to create a new raw material.
  /// Returns the newly created material's ID, or null if cancelled.
  Future<String?> _showQuickMaterialDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String uom = 'units';

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Raw Material'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Material Name *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: costCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Unit Cost', prefixText: 'EGP '),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: uom,
                          decoration:
                              const InputDecoration(labelText: 'Unit'),
                          items: ['units', 'g', 'kg', 'm', 'cm', 'L', 'mL', 'pcs']
                              .map((u) =>
                                  DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => uom = v ?? 'units'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final appState = ctx.read<AppState>();
                final rm = RawMaterial(
                  id: '',
                  name: nameCtrl.text.trim(),
                  sku: '',
                  unit: uom,
                  unitOfMeasure: uom,
                  unitCost:
                      double.tryParse(costCtrl.text.trim()) ?? 0,
                  currentStock: 0,
                  safetyStock: 0,
                  leadTimeDays: 0,
                );
                await appState.addRawMaterial(rm);
                // Find the just-added material by name to get its ID.
                final saved = appState.rawMaterials
                    .where((m) => m.name == rm.name)
                    .lastOrNull;
                if (ctx.mounted) Navigator.pop(ctx, saved?.id);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
