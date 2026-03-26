import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/app_user.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/utils/role_guard.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
                  ],
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
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
  String? _planningBucket;
  bool _initialized = false;

  void _initFromSettings(UserSettings s) {
    if (_initialized) return;
    _serviceLevelCtrl = TextEditingController(text: '${s.serviceLevelTarget}');
    _leadTimeCtrl = TextEditingController(text: '${s.defaultLeadTimeDays}');
    _planningBucket = s.planningTimeBucket;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _serviceLevelCtrl.dispose();
      _leadTimeCtrl.dispose();
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
                Text('Inventory Policies', style: AppTextStyles.h3),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _serviceLevelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service Level Target (%)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _leadTimeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Default Lead Time (Days)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _planningBucket,
                  decoration: const InputDecoration(
                    labelText: 'Planning Time Bucket',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) => setState(() => _planningBucket = v),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final appState = context.read<AppState>();
                      final updated = appState.settings.copyWith(
                        serviceLevelTarget:
                            double.tryParse(_serviceLevelCtrl.text),
                        defaultLeadTimeDays:
                            int.tryParse(_leadTimeCtrl.text),
                        planningTimeBucket: _planningBucket,
                      );
                      await appState.saveSettings(updated);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settings saved')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Changes'),
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
    if (result == 'success') {
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team member added successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
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
