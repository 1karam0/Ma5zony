import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';
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

class _UserManagementTab extends StatelessWidget {
  const _UserManagementTab();

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AppState>().currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            if (currentUser != null)
              DataRow(
                cells: [
                  DataCell(Text(currentUser.name)),
                  DataCell(Text(currentUser.role)),
                  const DataCell(StatusChip('Active')),
                  const DataCell(Icon(Icons.more_horiz)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
