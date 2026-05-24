import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/app_user.dart';
import 'package:ma5zony/models/workflow_log.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/backend_api_service.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/utils/role_guard.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Settings'),
                const TabBar(
                  tabs: [
                    Tab(text: 'Global Parameters'),
                    Tab(text: 'Forecasting Defaults'),
                    Tab(text: 'User Management'),
                    Tab(text: 'Preferences'),
                    Tab(text: 'Activity Log'),
                  ],
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  isScrollable: true,
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _GlobalParametersTab(),
                _ForecastingDefaultsTab(),
                _UserManagementTab(),
                _PreferencesTab(),
                _ActivityLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalParametersTab extends StatefulWidget {
  const _GlobalParametersTab();

  @override
  State<_GlobalParametersTab> createState() => _GlobalParametersTabState();
}

class _GlobalParametersTabState extends State<_GlobalParametersTab> {
  late TextEditingController _serviceLevelCtrl;
  late TextEditingController _leadTimeCtrl;
  late TextEditingController _orderingCostCtrl;
  late TextEditingController _holdingRateCtrl;
  String? _planningBucket;
  bool _initialized = false;

  void _initFromSettings(UserSettings s) {
    if (_initialized) return;
    _serviceLevelCtrl = TextEditingController(text: '${s.serviceLevelTarget.toInt()}');
    _leadTimeCtrl = TextEditingController(text: '${s.defaultLeadTimeDays}');
    _orderingCostCtrl = TextEditingController(text: s.orderingCost.toStringAsFixed(0));
    _holdingRateCtrl = TextEditingController(text: (s.holdingRate * 100).toStringAsFixed(0));
    _planningBucket = s.planningTimeBucket;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _serviceLevelCtrl.dispose();
      _leadTimeCtrl.dispose();
      _orderingCostCtrl.dispose();
      _holdingRateCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    _initFromSettings(settings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Service Level & Lead Time ──────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.policy, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('Inventory Policies', style: AppTextStyles.h3),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These values control safety stock and order quantity calculations across all products.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _serviceLevelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Service Level Target (%)',
                        border: OutlineInputBorder(),
                        hintText: '95',
                        helperText: 'Higher % = more safety stock buffer. Recommended: 95%.',
                        prefixIcon: Icon(Icons.verified_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _leadTimeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Default Lead Time (days)',
                        border: OutlineInputBorder(),
                        hintText: '7',
                        helperText: 'Used when a product or supplier has no lead time set.',
                        prefixIcon: Icon(Icons.schedule_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _planningBucket,
                      decoration: const InputDecoration(
                        labelText: 'Planning Time Bucket',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                        DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                        DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                      ],
                      onChanged: (v) => setState(() => _planningBucket = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Order Cost Settings ─────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calculate, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Text('Order Cost Settings', style: AppTextStyles.h3),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Used to calculate the recommended order quantity for each product.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _orderingCostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ordering Cost per Order',
                        border: OutlineInputBorder(),
                        hintText: '250',
                        helperText: 'Fixed cost each time you place a purchase order.',
                        prefixIcon: Icon(Icons.receipt_outlined),
                        prefixText: 'EGP ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _holdingRateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Annual Holding Rate (% of unit cost)',
                        border: OutlineInputBorder(),
                        hintText: '20',
                        helperText: 'Annual cost to store one unit. Typically 20–30%.',
                        prefixIcon: Icon(Icons.warehouse_outlined),
                        suffixText: '%',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  final holdingRateParsed = double.tryParse(_holdingRateCtrl.text);
                  final updated = appState.settings.copyWith(
                    serviceLevelTarget: double.tryParse(_serviceLevelCtrl.text),
                    defaultLeadTimeDays: int.tryParse(_leadTimeCtrl.text),
                    planningTimeBucket: _planningBucket,
                    orderingCost: double.tryParse(_orderingCostCtrl.text),
                    holdingRate: holdingRateParsed != null ? holdingRateParsed / 100 : null,
                  );
                  await appState.saveSettings(updated);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 3)),
                    );
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastingDefaultsTab extends StatefulWidget {
  const _ForecastingDefaultsTab();

  @override
  State<_ForecastingDefaultsTab> createState() =>
      _ForecastingDefaultsTabState();
}

class _ForecastingDefaultsTabState extends State<_ForecastingDefaultsTab> {
  late TextEditingController _smaWindowCtrl;
  late TextEditingController _sesAlphaCtrl;
  bool _initialized = false;

  void _initFromSettings(UserSettings s) {
    if (_initialized) return;
    _smaWindowCtrl = TextEditingController(text: '${s.smaWindow}');
    _sesAlphaCtrl = TextEditingController(text: '${s.sesAlpha}');
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _smaWindowCtrl.dispose();
      _sesAlphaCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    _initFromSettings(settings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 600,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Algorithm Defaults', style: AppTextStyles.h3),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _smaWindowCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Default SMA Window Size',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sesAlphaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Default SES Alpha',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final appState = context.read<AppState>();
                      final updated = appState.settings.copyWith(
                        smaWindow: int.tryParse(_smaWindowCtrl.text),
                        sesAlpha: double.tryParse(_sesAlphaCtrl.text),
                      );
                      await appState.saveSettings(updated);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Forecasting defaults saved'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Defaults'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserManagementTab extends StatefulWidget {
  const _UserManagementTab();

  @override
  State<_UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends State<_UserManagementTab> {
  final _emailController = TextEditingController();
  bool _inviting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _inviteMember() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _inviting = true);
    final state = context.read<AppState>();
    final result = await state.inviteTeamMember(email);
    setState(() => _inviting = false);

    if (!mounted) return;
    if (result == 'added') {
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team member added successfully.'), duration: Duration(seconds: 3)),
      );
    } else if (result == 'invited') {
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation email sent. They will receive a link to join.'),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(result)),
      );
    }
  }

  Future<void> _removeMember(AppUser member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Team Member'),
        content: Text('Remove ${member.name} from your team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AppState>().removeTeamMember(member.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUser = state.currentUser;
    final userIsOwner = isOwner(currentUser);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Current User Info ─────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your Account', style: AppTextStyles.h3),
                  const SizedBox(height: 16),
                  if (currentUser != null)
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: Text(
                            currentUser.name.isNotEmpty
                                ? currentUser.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(currentUser.name,
                                  style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600)),
                              Text(currentUser.email,
                                  style: AppTextStyles.bodySmall),
                            ],
                          ),
                        ),
                        StatusChip(currentUser.role),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Team Management (Owner only) ──────────────────────────
          if (userIsOwner) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Team Members', style: AppTextStyles.h3),
                        const Spacer(),
                        Text(
                          '${state.teamMembers.length} members',
                          style: AppTextStyles.label,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Invite Row ───────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText:
                                  'Enter Inventory Manager email to invite',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            onSubmitted: (_) => _inviteMember(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _inviting ? null : _inviteMember,
                          icon: _inviting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add),
                          label: const Text('Add'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Members Table ────────────────────────────────
                    if (state.teamMembers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No team members yet. Invite an Inventory Manager by email.',
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Role')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: state.teamMembers.map((member) {
                            return DataRow(cells: [
                              DataCell(Text(member.name,
                                  style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(member.email)),
                              DataCell(
                                  StatusChip(member.role == 'Inventory Manager'
                                      ? 'Active'
                                      : member.role)),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: AppColors.error),
                                  tooltip: 'Remove from team',
                                  onPressed: () => _removeMember(member),
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // ── IM view: show who they belong to ─────────────────────
            if (currentUser?.ownerId != null)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.business, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Text('You are part of an owner\'s team.',
                          style: AppTextStyles.body),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Preferences Tab ──────────────────────────────────────────────────────────

class _PreferencesTab extends StatelessWidget {
  const _PreferencesTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final isDark = state.themeMode == ThemeMode.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Appearance card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance', style: AppTextStyles.h3),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dark Mode'),
                      subtitle: Text(
                        isDark ? 'Currently using dark theme' : 'Currently using light theme',
                        style: AppTextStyles.label,
                      ),
                      secondary: Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        color: AppColors.primary,
                      ),
                      value: isDark,
                      onChanged: (_) => state.toggleTheme(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Onboarding card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Onboarding', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text(
                      'Re-open the setup wizard to add suppliers, products, warehouses, or import demand data.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: () => context.go('/setup'),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Open Setup Wizard'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Notifications card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text(
                      'Configure which alerts you receive via email.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Weekly Email Digest'),
                      subtitle: const Text(
                          'Receive a summary of inventory, forecasts, and orders every week.'),
                      value: settings.emailDigest,
                      onChanged: (v) async {
                        final updated = settings.copyWith(emailDigest: v);
                        await context.read<AppState>().saveSettings(updated);
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Low Stock Alerts'),
                      subtitle: const Text(
                          'Send an email when any product falls below its reorder point.'),
                      value: settings.lowStockAlerts,
                      onChanged: (v) async {
                        final updated = settings.copyWith(lowStockAlerts: v);
                        await context.read<AppState>().saveSettings(updated);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Danger zone card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Text('Danger Zone',
                            style: AppTextStyles.h3
                                .copyWith(color: AppColors.error)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Permanently delete your account and all associated data. '
                      'This action cannot be undone.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    _DeleteAccountButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountButton extends StatefulWidget {
  const _DeleteAccountButton();

  @override
  State<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<_DeleteAccountButton> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and ALL your data '
          '(products, orders, suppliers, forecasts, etc.).\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await BackendApiService().deleteAccount();
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.logout();
      if (!mounted) return;
      context.go('/login');
    } on BackendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _deleting ? null : _confirmAndDelete,
      icon: _deleting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.delete_forever),
      label: Text(_deleting ? 'Deleting…' : 'Delete My Account'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: BorderSide(color: AppColors.error),
      ),
    );
  }
}

// ── Activity Log Tab ────────────────────────────────────────────────────────

class _ActivityLogTab extends StatefulWidget {
  const _ActivityLogTab();

  @override
  State<_ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<_ActivityLogTab> {
  bool _loading = false;
  String _filterType = 'all';

  static const _entityTypes = [
    ('all', 'All'),
    ('product', 'Products'),
    ('purchaseOrder', 'Purchase Orders'),
    ('supplierOrder', 'Supplier Orders'),
    ('productionOrder', 'Production Orders'),
    ('rawMaterialOrder', 'Raw Material Orders'),
    ('recommendation', 'Recommendations'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await context.read<AppState>().loadWorkflowLogs();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<AppState>().workflowLogs;
    final filtered = _filterType == 'all'
        ? logs
        : logs.where((l) => l.entityType == _filterType).toList();

    // Sort newest first
    final sorted = [...filtered]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Activity Log', style: AppTextStyles.h3),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All significant actions performed in your workspace.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          // Filter chips
          Wrap(
            spacing: 8,
            children: _entityTypes.map(((String, String) t) {
              final (value, label) = t;
              final selected = _filterType == value;
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() => _filterType = value),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                checkmarkColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (sorted.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 48,
                        color: AppColors.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('No activity recorded yet.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sorted.length,
                separatorBuilder: (context2, index) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) => _LogTile(log: sorted[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final WorkflowLog log;
  const _LogTile({required this.log});

  static const _iconMap = <String, IconData>{
    'received': Icons.inventory_2,
    'approved': Icons.check_circle,
    'rejected': Icons.cancel,
    'created': Icons.add_circle_outline,
    'updated': Icons.edit,
    'deleted': Icons.delete_outline,
    'sent': Icons.email,
    'completed': Icons.task_alt,
    'generated': Icons.auto_awesome,
    'ordered': Icons.shopping_cart,
  };

  static const _colorMap = <String, Color>{
    'received': AppColors.success,
    'approved': AppColors.success,
    'completed': AppColors.success,
    'rejected': AppColors.error,
    'deleted': AppColors.error,
    'created': AppColors.primary,
    'generated': AppColors.primary,
    'updated': AppColors.warning,
    'sent': Colors.blue,
    'ordered': Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _iconMap[log.action] ?? Icons.circle;
    final color = _colorMap[log.action] ?? AppColors.textSecondary;
    final timeStr = _formatRelative(log.timestamp);

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 16),
      ),
      title: Text(
        '${_capitalize(log.action)} ${_humanize(log.entityType)}',
        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: log.details != null
          ? Text(log.details!, style: AppTextStyles.label, maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: Text(timeStr,
          style: AppTextStyles.label
              .copyWith(color: AppColors.textSecondary, fontSize: 11)),
    );
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _humanize(String s) {
    // camelCase → space-separated
    return s.replaceAllMapped(
        RegExp(r'([A-Z])'), (m) => ' ${m.group(1)!.toLowerCase()}');
  }
}
