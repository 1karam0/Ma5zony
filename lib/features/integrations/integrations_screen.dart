import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _importing = false;
  bool _syncing = false;
  bool _connecting = false;
  bool _importingOrders = false;
  final _domainController = TextEditingController();

  // Session-local sync log (most recent first)
  final List<_SyncLogEntry> _syncLog = [];

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  void _log(String type, String message, {bool error = false}) {
    setState(() {
      _syncLog.insert(
          0, _SyncLogEntry(type: type, message: message, error: error));
      if (_syncLog.length > 20) _syncLog.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connection = state.shopifyConnection;
    final isConnected = connection?.isConnected ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Integrations Hub'),

          // Shopify card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_bag,
                      size: 40,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + status chip
                        Row(
                          children: [
                            Text('Shopify', style: AppTextStyles.h2),
                            const SizedBox(width: 12),
                            StatusChip(
                              isConnected ? 'Connected' : 'Not Connected',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (isConnected && connection?.lastSyncAt != null)
                          Text(
                            'Last synced: ${DateFormat('MMM d, yyyy HH:mm').format(connection!.lastSyncAt!)}',
                            style: AppTextStyles.label,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Sync products, variants, and inventory levels automatically. Import orders to adjust stock.',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Capabilities list
                        const Column(
                          children: [
                            _CapabilityItem(label: 'Inventory Sync'),
                            _CapabilityItem(label: 'Order Imports'),
                            _CapabilityItem(label: 'Product Mapping'),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Domain field + Connect / Disconnect
                        if (!isConnected) ...[
                          SizedBox(
                            width: 380,
                            child: TextField(
                              controller: _domainController,
                              decoration: const InputDecoration(
                                labelText: 'Shopify Store Domain',
                                hintText: 'mystore.myshopify.com',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 380,
                            child: _ShopifyUrlHelp(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _connecting
                                  ? null
                                  : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final appState = context.read<AppState>();
                                if (isConnected) {
                                  await appState.disconnectShopify();
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Shopify store disconnected',
                                        ),
                                      ),
                                    );
                                  }
                                } else {
                                  final domain = _domainController.text.trim();
                                  if (domain.isEmpty) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter your Shopify store domain first.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _connecting = true);
                                  try {
                                    // Get OAuth URL from Cloud Function
                                    final authUrl =
                                        await appState.getShopifyOAuthUrl(domain);
                                    if (authUrl != null) {
                                      final uri = Uri.parse(authUrl);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                      // Poll until the connection is confirmed
                                      await appState.connectShopify(domain);
                                    }
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Shopify store connected!',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Connection failed: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _connecting = false);
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConnected
                                    ? Colors.red[50]
                                    : AppColors.primary,
                                foregroundColor: isConnected
                                    ? Colors.red
                                    : Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: _connecting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                isConnected
                                    ? 'Disconnect Store'
                                    : 'Connect Shopify Store',
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _importing
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        final appState =
                                            context.read<AppState>();
                                        final router = GoRouter.of(context);
                                        setState(() => _importing = true);
                                        try {
                                          final result =
                                              await appState.importShopifyProducts();
                                          if (mounted) {
                                            final newC = result['newCount'] ?? 0;
                                            final merged = result['mergedCount'] ?? 0;
                                            _log('Products', '$newC new, $merged updated');
                                            final hasWarehouses =
                                                appState.warehouses.isNotEmpty;
                                            messenger.showSnackBar(
                                              SnackBar(
                                                duration: const Duration(
                                                    seconds: 5),
                                                content: Text(
                                                  '$newC new product(s) added, $merged existing updated. ${hasWarehouses ? "Next: assign them to a warehouse." : "Next: create a warehouse to organize them."}',
                                                ),
                                                action: SnackBarAction(
                                                  label: hasWarehouses
                                                      ? 'Assign to Warehouse'
                                                      : 'Create Warehouse',
                                                  onPressed: () =>
                                                      router.go('/warehouses'),
                                                ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Import failed: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _importing = false);
                                          }
                                        }
                                      },
                                icon: _importing
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download),
                                label: const Text('Import Products'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _syncing
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() => _syncing = true);
                                        try {
                                          await context
                                              .read<AppState>()
                                              .syncShopifyInventory();
                                          if (mounted) {
                                            _log('Inventory', 'Inventory synced');
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Inventory synced!',
                                                ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Sync failed: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _syncing = false);
                                          }
                                        }
                                      },
                                icon: _syncing
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.sync),
                                label: const Text('Sync Inventory'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _importingOrders
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() => _importingOrders = true);
                                        try {
                                          final result = await context
                                              .read<AppState>()
                                              .importShopifyOrders();
                                          if (mounted) {
                                            final count =
                                                result?['newRecordsImported'] ?? 0;
                                            _log('Orders', '$count demand records imported');
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '$count demand record(s) imported from orders',
                                                ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            final msg = e.toString();
                                            final isScope = msg.contains('Access denied') || msg.contains('scope') || msg.contains('read_orders');
                                            messenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: Colors.red,
                                                duration: const Duration(seconds: 8),
                                                content: Text(
                                                  isScope
                                                      ? 'Permission error: disconnect and reconnect Shopify to grant order access.'
                                                      : 'Order import failed: $msg',
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                                () => _importingOrders = false);
                                          }
                                        }
                                      },
                                icon: _importingOrders
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.history),
                                label: const Text('Import Order History'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Security notice
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Real Shopify OAuth tokens are managed securely on your backend server. '
                    'This client never stores sensitive credentials.',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Session sync log
          if (_syncLog.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Recent Activity', style: AppTextStyles.h3),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _syncLog.clear()),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._syncLog.map((e) => _SyncLogTile(entry: e)),
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

class _CapabilityItem extends StatelessWidget {
  final String label;
  const _CapabilityItem({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 16),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.body),
        ],
      ),
    );
  }
}

// ─── Shopify URL Help ─────────────────────────────────────────────────────────

class _ShopifyUrlHelp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
          dense: true,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(Icons.help_outline,
              size: 16, color: AppColors.primary),
          title: const Text(
            'How do I find my Shopify store URL?',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary),
          ),
          children: const [
            _HelpStep(
              n: '1',
              text:
                  'Log in to your Shopify Admin at shopify.com/admin.',
            ),
            _HelpStep(
              n: '2',
              text:
                  'Look at the URL in your browser. It looks like '
                  '"https://admin.shopify.com/store/your-store-name".',
            ),
            _HelpStep(
              n: '3',
              text:
                  'Your store domain is "your-store-name.myshopify.com". '
                  'Replace "your-store-name" with the value after /store/.',
            ),
            _HelpStep(
              n: '4',
              text:
                  'Alternatively, in Shopify Admin go to Settings → Domains. '
                  'Your permanent .myshopify.com domain is listed at the top.',
            ),
            _HelpStep(
              n: '5',
              text:
                  'Paste only the domain (e.g. "my-store.myshopify.com"), '
                  'without "https://" or trailing slashes.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  final String n;
  final String text;
  const _HelpStep({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                n,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sync Log ─────────────────────────────────────────────────────────────────

class _SyncLogEntry {
  final String type;
  final String message;
  final DateTime at;
  final bool error;
  _SyncLogEntry({required this.type, required this.message, this.error = false})
      : at = DateTime.now();
}

class _SyncLogTile extends StatelessWidget {
  const _SyncLogTile({required this.entry});
  final _SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.error ? AppColors.error : AppColors.success;
    final icon = entry.error ? Icons.error_outline : Icons.check_circle_outline;
    final time = DateFormat('HH:mm:ss').format(entry.at);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '[${entry.type}]',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: color, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.message,
                style: const TextStyle(fontSize: 12)),
          ),
          Text(time,
              style: AppTextStyles.label.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
