import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/services/mock_data_service.dart';
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

class _GlobalParametersTab extends StatelessWidget {
  const _GlobalParametersTab();

  @override
  Widget build(BuildContext context) {
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
                  initialValue: '95',
                  decoration: const InputDecoration(
                    labelText: 'Service Level Target (%)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: '7',
                  decoration: const InputDecoration(
                    labelText: 'Default Lead Time (Days)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: 'Daily',
                  decoration: const InputDecoration(
                    labelText: 'Planning Time Bucket',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
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

class _ForecastingDefaultsTab extends StatelessWidget {
  const _ForecastingDefaultsTab();

  @override
  Widget build(BuildContext context) {
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
                  initialValue: '3',
                  decoration: const InputDecoration(
                    labelText: 'Default SMA Window Size',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: '0.5',
                  decoration: const InputDecoration(
                    labelText: 'Default SES Alpha',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
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
    final currentUser = context.watch<MockDataService>().currentUser;

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
            const DataRow(
              cells: [
                DataCell(Text('Admin User')),
                DataCell(Text('SME Owner')),
                DataCell(StatusChip('Active')),
                DataCell(Icon(Icons.more_horiz)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
