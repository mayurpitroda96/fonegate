import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'models/models.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/dashboard_socket.dart';
import 'services/download_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const FoneGateDashboardApp());
}

class FoneGateDashboardApp extends StatefulWidget {
  const FoneGateDashboardApp({super.key});

  @override
  State<FoneGateDashboardApp> createState() => _FoneGateDashboardAppState();
}

class _FoneGateDashboardAppState extends State<FoneGateDashboardApp> {
  bool _isLoggedIn = ApiService.isAuthenticated;

  void _onLoginSuccess() {
    setState(() => _isLoggedIn = true);
  }

  void _onLogout() async {
    await ApiService.logout();
    setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoneGate Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F62FE),
          brightness: Brightness.dark,
          surface: const Color(0xFF16181D),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        cardTheme: const CardThemeData(color: Color(0xFF1B1E26), elevation: 0),
      ),
      home: _isLoggedIn
          ? DashboardHomeScreen(onLogout: _onLogout)
          : LoginScreen(onLoginSuccess: _onLoginSuccess),
    );
  }
}

class DashboardHomeScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const DashboardHomeScreen({super.key, required this.onLogout});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
  int _selectedIndex = 0;
  final DashboardSocket _socket = DashboardSocket();
  bool _isSocketConnected = false;

  GatewayStats? _stats;
  List<Device> _devices = [];
  List<SmsMessage> _messages = [];
  List<Webhook> _webhooks = [];
  List<WebhookLog> _webhookLogs = [];
  List<ApiKey> _apiKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _socket.connect();
    _socket.connectionStream.listen((connected) {
      if (mounted) setState(() => _isSocketConnected = connected);
    });

    // Handle real-time updates from WebSocket
    _socket.eventStream.listen((event) {
      final eventName = event['event'] as String?;
      if (eventName == 'sms:new' ||
          eventName == 'sms:status' ||
          eventName == 'device:status') {
        _loadData(silent: true);
      }
    });

    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final statsFuture = ApiService.fetchStats();
      final devicesFuture = ApiService.fetchDevices();
      final messagesFuture = ApiService.fetchMessages(limit: 50);
      final webhooksFuture = ApiService.fetchWebhooks();
      final logsFuture = ApiService.fetchWebhookLogs();
      final apiKeysFuture = ApiService.fetchApiKeys();

      final results = await Future.wait([
        statsFuture,
        devicesFuture,
        messagesFuture,
        webhooksFuture,
        logsFuture,
        apiKeysFuture,
      ]);

      if (mounted) {
        setState(() {
          _stats = results[0] as GatewayStats;
          _devices = results[1] as List<Device>;
          _messages = results[2] as List<SmsMessage>;
          _webhooks = results[3] as List<Webhook>;
          _webhookLogs = results[4] as List<WebhookLog>;
          _apiKeys = results[5] as List<ApiKey>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        widget.onLogout();
        return;
      }
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showBackupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.import_export, color: Color(0xFF0F62FE)),
            SizedBox(width: 10),
            Text('Backup & Restore Database'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export your entire database (devices, messages, and webhooks) to a JSON file, or restore from a previous backup file.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // Export Card
              Card(
                color: const Color(0xFF14161C),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.download, color: Colors.greenAccent, size: 28),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Export Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('Download complete JSON snapshot', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () async {
                          try {
                            final jsonStr = await ApiService.exportBackup();
                            final filename = 'opensms_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
                            downloadJsonFile(jsonStr, filename);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Backup exported successfully! Check your downloads.')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        child: const Text('Export JSON'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Import Card
              Card(
                color: const Color(0xFF14161C),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.upload, color: Colors.amberAccent, size: 28),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Import Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('Restore from a JSON backup file', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _handleImportBackup(ctx),
                        child: const Text('Import JSON'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImportBackup(BuildContext dialogContext) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (picked.isEmpty) {
        return;
      }

      final fileBytes = await picked.first.readAsBytes();
      final jsonStr = utf8.decode(fileBytes);

      if (!mounted) return;

      String selectedMode = 'merge';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (confirmCtx) => StatefulBuilder(
          builder: (context, setConfirmState) => AlertDialog(
            title: const Text('Confirm Restore Mode'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose how to restore this backup:'),
                  const SizedBox(height: 16),
                  Center(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'merge', label: Text('Merge Data')),
                        ButtonSegment(value: 'replace', label: Text('Wipe & Replace')),
                      ],
                      selected: {selectedMode},
                      onSelectionChanged: (val) => setConfirmState(() => selectedMode = val.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (selectedMode == 'replace' ? Colors.red : const Color(0xFF0F62FE)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selectedMode == 'replace'
                          ? 'WARNING: This will wipe all current messages, devices, and webhooks before importing the backup file.'
                          : 'Merge: Existing records with matching IDs will be updated, and new records will be added.',
                      style: TextStyle(
                        fontSize: 12,
                        color: selectedMode == 'replace' ? Colors.redAccent : Colors.lightBlueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: selectedMode == 'replace' ? Colors.red : null,
                ),
                onPressed: () => Navigator.pop(confirmCtx, true),
                child: Text(selectedMode == 'replace' ? 'Confirm Replace' : 'Confirm Merge'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;

      final res = await ApiService.importBackup(jsonStr, mode: selectedMode);
      if (dialogContext.mounted) Navigator.pop(dialogContext);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Import successful!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showChangePasswordDialog() {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Admin Password'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final current = currentPassController.text.trim();
              final newP = newPassController.text.trim();
              final confirmP = confirmPassController.text.trim();

              if (newP != confirmP) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('New passwords do not match'), backgroundColor: Colors.red),
                  );
                }
                return;
              }

              try {
                await ApiService.changePassword(current, newP);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
  }

  void _showConfigDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend API Settings'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'http://localhost:8080',
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
              await ApiService.setBaseUrl(controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _socket.disconnect();
              _socket.connect();
              _loadData();
            },
            child: const Text('Save & Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar Navigation
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) =>
                setState(() => _selectedIndex = idx),
            backgroundColor: const Color(0xFF14161C),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/logo_icon.png', width: 48, height: 48),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'FoneGate',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.phone_android_outlined),
                selectedIcon: Icon(Icons.phone_android),
                label: Text('Devices'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.send_outlined),
                selectedIcon: Icon(Icons.send),
                label: Text('Send SMS'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.mark_email_read_outlined),
                selectedIcon: Icon(Icons.mark_email_read),
                label: Text('Messages'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.webhook_outlined),
                selectedIcon: Icon(Icons.webhook),
                label: Text('Webhooks'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.vpn_key_outlined),
                selectedIcon: Icon(Icons.vpn_key),
                label: Text('API Keys'),
              ),
            ],
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFF232732),
          ),

          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF14161C),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF232732)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _getPageTitle(_selectedIndex),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      // Real-time Socket Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (_isSocketConnected ? Colors.green : Colors.amber)
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                (_isSocketConnected
                                        ? Colors.green
                                        : Colors.amber)
                                    .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isSocketConnected
                                    ? Colors.greenAccent
                                    : Colors.amberAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isSocketConnected
                                  ? 'Live Socket Sync'
                                  : 'Connecting...',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isSocketConnected
                                    ? Colors.greenAccent
                                    : Colors.amberAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.backup_outlined, size: 16),
                        label: const Text('Backup / Restore', style: TextStyle(fontSize: 12)),
                        onPressed: _showBackupDialog,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh',
                        onPressed: () => _loadData(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        tooltip: 'Server Settings',
                        onPressed: _showConfigDialog,
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Admin Account',
                        onSelected: (val) {
                          if (val == 'password') {
                            _showChangePasswordDialog();
                          } else if (val == 'backup') {
                            _showBackupDialog();
                          } else if (val == 'logout') {
                            widget.onLogout();
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            enabled: false,
                            child: Text(
                              'Signed in as ${ApiService.currentUser?['username'] ?? 'admin'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'password',
                            child: Row(
                              children: [
                                Icon(Icons.key_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Change Password'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'backup',
                            child: Row(
                              children: [
                                Icon(Icons.import_export, size: 18),
                                SizedBox(width: 10),
                                Text('Backup & Restore'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 18, color: Colors.redAccent),
                                SizedBox(width: 10),
                                Text('Logout', style: TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2128),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF2E3340)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: const Color(0xFF0F62FE),
                                child: Text(
                                  (ApiService.currentUser?['username'] ?? 'A')[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ApiService.currentUser?['username'] ?? 'admin',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Tab Body
                Expanded(
                  child: _isLoading && _stats == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildTabContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle(int index) {
    switch (index) {
      case 0:
        return 'System Overview';
      case 1:
        return 'Connected Android Devices';
      case 2:
        return 'SMS Dispatch Console';
      case 3:
        return 'Message Logs & Audit';
      case 4:
        return 'Webhooks & HTTP Dispatcher';
      case 5:
        return 'API Keys';
      default:
        return 'Dashboard';
    }
  }

  Widget _buildTabContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildDevicesTab();
      case 2:
        return _buildSendSmsTab();
      case 3:
        return _buildMessagesTab();
      case 4:
        return _buildWebhooksTab();
      case 5:
        return _buildApiKeysTab();
      default:
        return const SizedBox();
    }
  }

  // TAB 0: OVERVIEW
  Widget _buildOverviewTab() {
    final stats =
        _stats ??
        GatewayStats(
          totalSent: 0,
          totalDelivered: 0,
          totalFailed: 0,
          totalReceived: 0,
          pendingQueue: 0,
          activeDevices: 0,
          totalDevices: 0,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metrics Cards Row
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Sent',
                  stats.totalSent.toString(),
                  Icons.outbox,
                  const Color(0xFF0F62FE),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Delivered',
                  stats.totalDelivered.toString(),
                  Icons.check_circle_outline,
                  const Color(0xFF24A148),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Inbound Received',
                  stats.totalReceived.toString(),
                  Icons.move_to_inbox,
                  const Color(0xFF0072C3),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Active Phones',
                  '${stats.activeDevices} / ${stats.totalDevices}',
                  Icons.smartphone,
                  const Color(0xFF8A3FFC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Live Recent Messages Table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Live Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.0),
                      child: Center(
                        child: Text(
                          'No messages sent or received yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _messages.take(10).length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFF282C35)),
                      itemBuilder: (context, idx) {
                        final msg = _messages[idx];
                        return _buildMessageRow(msg);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageRow(SmsMessage msg) {
    final isOutbound = msg.direction == 'outbound';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(
            isOutbound ? Icons.arrow_upward : Icons.arrow_downward,
            color: isOutbound ? Colors.amberAccent : Colors.lightBlueAccent,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            msg.phoneNumber,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              msg.message,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
            ),
          ),
          const SizedBox(width: 16),
          _buildStatusBadge(msg.status),
          const SizedBox(width: 16),
          Text(
            DateFormat('HH:mm:ss').format(msg.createdAt.toLocal()),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'delivered':
        color = Colors.green;
        break;
      case 'sent':
        color = Colors.blue;
        break;
      case 'received':
        color = Colors.teal;
        break;
      case 'pending':
      case 'queued':
        color = Colors.amber;
        break;
      case 'failed':
      default:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // TAB 1: DEVICES
  Widget _buildDevicesTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Registered Android Gateways',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Pair New Phone'),
                onPressed: _showPairDeviceDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(
                  child: Text(
                    'No Android gateway phones registered yet.\nClick "Pair New Phone" to generate a pairing token.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 540,
                  mainAxisExtent: 220,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _devices.length,
                itemBuilder: (context, idx) => _buildDeviceCard(_devices[idx]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(Device device) {
    final wsBase = ApiService.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = '$wsBase/ws/gateway';
    final qrPayload = jsonEncode({
      'serverUrl': wsUrl,
      'token': device.token,
      'name': device.name,
      'id': device.id,
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smartphone,
                        color: device.isOnline
                            ? Colors.greenAccent
                            : Colors.grey,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              device.isOnline
                                  ? 'Online (Connected)'
                                  : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: device.isOnline
                                    ? Colors.greenAccent
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Device',
                        onPressed: () async {
                          await ApiService.deleteDevice(device.id);
                          _loadData();
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    children: [
                      const Icon(
                        Icons.battery_std,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Battery: ${device.batteryLevel}%${device.isCharging ? ' (Charging)' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.sim_card_outlined,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          device.simInfo ?? 'SIM: Standard',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14161C),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Token: ${device.token}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy Token',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Device token copied to clipboard!',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Right QR Code column
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _showDeviceQrDialog(device),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: QrImageView(
                        data: qrPayload,
                        version: QrVersions.auto,
                        size: 120.0,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.fullscreen, size: 15),
                  label: const Text(
                    'Enlarge QR',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _showDeviceQrDialog(device),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceQrDialog(Device device) {
    final wsBase = ApiService.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = '$wsBase/ws/gateway';

    final qrPayload = jsonEncode({
      'serverUrl': wsUrl,
      'token': device.token,
      'name': device.name,
      'id': device.id,
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code, color: Color(0xFF0F62FE)),
            const SizedBox(width: 10),
            Text('Pair ${device.name}'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this QR code using the FoneGate Android app to instantly pair your phone.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 220.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server: $wsUrl',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Token: ${device.token}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPairDeviceDialog() {
    final nameController = TextEditingController(text: 'Android Gateway 1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pair New Android Gateway Phone'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a friendly name for this phone. A secure device token will be generated to connect the mobile app.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                final created = await ApiService.createDevice(name);
                await _loadData();
                _showDeviceQrDialog(created);
              }
            },
            child: const Text('Generate Token & QR Code'),
          ),
        ],
      ),
    );
  }

  // TAB 2: SEND SMS
  Widget _buildSendSmsTab() {
    final phoneController = TextEditingController();
    final messageController = TextEditingController();
    String? selectedDeviceId;
    int selectedSim = 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: StatefulBuilder(
              builder: (context, setFormState) {
                final charCount = messageController.text.length;
                final segments = (charCount / 160).ceil();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dispatch SMS Message',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The SMS will be queued and pushed instantly to the online Android phone.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Phone Number',
                        hintText: '+1234567890',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: messageController,
                      maxLines: 4,
                      onChanged: (_) => setFormState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Message Body',
                        hintText: 'Type your SMS message here...',
                        border: const OutlineInputBorder(),
                        helperText:
                            '$charCount characters (~$segments SMS parts)',
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: selectedDeviceId,
                            decoration: const InputDecoration(
                              labelText: 'Target Device',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Any Online Device'),
                              ),
                              ..._devices.map(
                                (d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${d.name} (${d.isOnline ? 'Online' : 'Offline'})',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setFormState(() => selectedDeviceId = val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedSim,
                            decoration: const InputDecoration(
                              labelText: 'SIM Slot',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('SIM 1')),
                              DropdownMenuItem(value: 1, child: Text('SIM 2')),
                            ],
                            onChanged: (val) =>
                                setFormState(() => selectedSim = val ?? 0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text(
                          'Queue & Send SMS',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final to = phoneController.text.trim();
                          final msg = messageController.text.trim();
                          if (to.isEmpty || msg.isEmpty) return;

                          try {
                            await ApiService.sendSms(
                              to: to,
                              message: msg,
                              deviceId: selectedDeviceId,
                              simSlot: selectedSim,
                            );
                            phoneController.clear();
                            messageController.clear();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('SMS queued successfully!'),
                                ),
                              );
                            }
                            _loadData();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // TAB 3: MESSAGES
  Widget _buildMessagesTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'All Messages',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _loadData(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _messages.isEmpty
                    ? const Center(child: Text('No message history found.'))
                    : ListView.separated(
                        itemCount: _messages.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFF282C35)),
                        itemBuilder: (context, idx) {
                          final msg = _messages[idx];
                          return ListTile(
                            leading: Icon(
                              msg.direction == 'outbound'
                                  ? Icons.outgoing_mail
                                  : Icons.mark_email_read,
                              color: msg.direction == 'outbound'
                                  ? Colors.amberAccent
                                  : Colors.lightBlueAccent,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  msg.phoneNumber,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildStatusBadge(msg.status),
                              ],
                            ),
                            subtitle: Text(msg.message),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(msg.createdAt.toLocal()),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                                if (msg.status == 'failed') ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.replay,
                                      color: Colors.amberAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Retry sending',
                                    onPressed: () async {
                                      await ApiService.retryMessage(msg.id);
                                      _loadData();
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 4: WEBHOOKS
  Widget _buildWebhooksTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Webhook Subscriptions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Webhook'),
                onPressed: _showAddWebhookDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Webhook list
                Expanded(
                  flex: 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _webhooks.isEmpty
                          ? const Center(
                              child: Text('No webhooks registered yet.'),
                            )
                          : ListView.separated(
                              itemCount: _webhooks.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: Color(0xFF282C35),
                              ),
                              itemBuilder: (context, idx) {
                                final hook = _webhooks[idx];
                                return ListTile(
                                  title: Text(
                                    hook.url,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Events: ${hook.events.join(', ')}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.play_arrow,
                                          size: 16,
                                        ),
                                        label: const Text('Test'),
                                        onPressed: () async {
                                          await ApiService.testWebhook(hook.id);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Test webhook fired!',
                                                ),
                                              ),
                                            );
                                          }
                                          _loadData();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          await ApiService.deleteWebhook(
                                            hook.id,
                                          );
                                          _loadData();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Webhook logs
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Deliveries',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _webhookLogs.isEmpty
                                ? const Center(
                                    child: Text('No delivery logs yet.'),
                                  )
                                : ListView.separated(
                                    itemCount: _webhookLogs.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: Color(0xFF282C35),
                                    ),
                                    itemBuilder: (context, idx) {
                                      final log = _webhookLogs[idx];
                                      final isSuccess =
                                          log.responseStatus != null &&
                                          log.responseStatus! >= 200 &&
                                          log.responseStatus! < 300;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8.0,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  log.event,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        (isSuccess
                                                                ? Colors.green
                                                                : Colors.red)
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${log.responseStatus ?? 'ERR'} (${log.durationMs}ms)',
                                                    style: TextStyle(
                                                      color: isSuccess
                                                          ? Colors.greenAccent
                                                          : Colors.redAccent,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              log.url ?? 'Unknown URL',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddWebhookDialog() {
    final urlController = TextEditingController();
    final secretController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Webhook Endpoint'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Webhook URL',
                  hintText: 'https://my-app.com/api/sms-webhook',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretController,
                decoration: const InputDecoration(
                  labelText: 'Secret (optional, for HMAC signature)',
                  hintText: 'Leave blank to generate automatically',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                await ApiService.createWebhook(
                  url: url,
                  events: [
                    'sms.received',
                    'sms.sent',
                    'sms.delivered',
                    'sms.failed',
                  ],
                  secret: secretController.text.trim().isNotEmpty
                      ? secretController.text.trim()
                      : null,
                );
                _loadData();
              }
            },
            child: const Text('Create Webhook'),
          ),
        ],
      ),
    );
  }

  // TAB 5: API KEYS
  Widget _buildApiKeysTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F62FE).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF0F62FE).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF78A9FF), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Use API keys to authenticate SMS API requests from external applications.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pass the key as X-API-Key header:  curl -H "X-API-Key: fg_xxx..." -X POST /api/v1/sms/send',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Header row
          Row(
            children: [
              Text(
                'API Keys (${_apiKeys.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create API Key'),
                onPressed: _showCreateApiKeyDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_apiKeys.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: const Color(0xFF14161C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF232732)),
              ),
              child: Column(
                children: [
                  Icon(Icons.vpn_key_off_outlined, size: 48, color: Colors.grey.shade600),
                  const SizedBox(height: 12),
                  const Text('No API keys yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Create an API key to allow external apps to send SMS.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          else
            ..._apiKeys.map((key) => _buildApiKeyCard(key)),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard(ApiKey apiKey) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14161C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: apiKey.isActive ? const Color(0xFF232732) : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (apiKey.isActive ? const Color(0xFF0F62FE) : Colors.grey).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.vpn_key,
              color: apiKey.isActive ? const Color(0xFF78A9FF) : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      apiKey.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (apiKey.isActive ? Colors.green : Colors.red).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        apiKey.isActive ? 'Active' : 'Disabled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: apiKey.isActive ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SelectableText(
                      apiKey.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Created: ${_formatDate(apiKey.createdAt)}'
                  '${apiKey.lastUsedAt != null ? '  •  Last used: ${_formatDate(apiKey.lastUsedAt!)}' : '  •  Never used'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              apiKey.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: apiKey.isActive ? Colors.amberAccent : Colors.greenAccent,
            ),
            tooltip: apiKey.isActive ? 'Disable' : 'Enable',
            onPressed: () async {
              try {
                await ApiService.toggleApiKey(apiKey.id);
                _loadData(silent: true);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Delete',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete API Key?'),
                  content: Text('Delete "${apiKey.name}"? Any app using this key will stop working.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ApiService.deleteApiKey(apiKey.id);
                _loadData(silent: true);
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showCreateApiKeyDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Color(0xFF0F62FE)),
            SizedBox(width: 10),
            Text('Create API Key'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Give this key a name so you can identify it later (e.g. "CRM Integration", "Marketing Bot").',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Key Name',
                  hintText: 'e.g. My Integration',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              try {
                final newKey = await ApiService.createApiKey(name);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData(silent: true);
                if (mounted) {
                  _showNewKeyDialog(newKey);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Create Key'),
          ),
        ],
      ),
    );
  }

  void _showNewKeyDialog(ApiKey apiKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('API Key Created'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy your API key now. You can always view it from the API Keys tab.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0F14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF232732)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        apiKey.key,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Usage Example:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    const SizedBox(height: 8),
                    SelectableText(
                      'curl -X POST ${ApiService.baseUrl}/api/v1/sms/send \\\n'
                      '  -H "Content-Type: application/json" \\\n'
                      '  -H "X-API-Key: ${apiKey.key}" \\\n'
                      '  -d \'{"to": "+1234567890", "message": "Hello!"}\'',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey.shade300),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
