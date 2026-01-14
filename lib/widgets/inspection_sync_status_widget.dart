import 'package:flutter/material.dart';
import '../services/inspection_sync_service.dart';

/// Widget displaying inspection sync status for the dispatch dashboard integration
class InspectionSyncStatusWidget extends StatefulWidget {
  const InspectionSyncStatusWidget({super.key});

  @override
  State<InspectionSyncStatusWidget> createState() =>
      _InspectionSyncStatusWidgetState();
}

class _InspectionSyncStatusWidgetState extends State<InspectionSyncStatusWidget> {
  final _syncService = InspectionSyncService();
  late Future<Map<String, dynamic>> _statusFuture;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  void _refreshStatus() {
    setState(() {
      _statusFuture = _syncService.getSyncStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final status = snapshot.data!;
        final isOnline = status['isOnline'] as bool;
        final isSyncing = status['isSyncing'] as bool;
        final totalInspections = status['totalInspections'] as int;
        final syncedCount = status['syncedCount'] as int;
        final pendingCount = status['pendingCount'] as int;
        final errorCount = status['errorCount'] as int;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status
              Card(
                color: isOnline ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        isOnline ? Icons.cloud_done : Icons.cloud_off,
                        color: isOnline ? Colors.green : Colors.red,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isOnline ? Colors.green : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOnline
                                  ? 'Connected to dispatch dashboard'
                                  : 'Syncing will resume when online',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Sync Statistics
              Text(
                'Inspection Sync Status',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // Stats Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _buildStatCard(
                    'Total Inspections',
                    totalInspections.toString(),
                    Colors.blue,
                  ),
                  _buildStatCard(
                    'Synced',
                    syncedCount.toString(),
                    Colors.green,
                  ),
                  _buildStatCard(
                    'Pending',
                    pendingCount.toString(),
                    Colors.orange,
                  ),
                  _buildStatCard(
                    'Errors',
                    errorCount.toString(),
                    Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Sync Progress
              if (isSyncing)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Syncing...',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sending $pendingCount inspection(s) to dashboard',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (pendingCount > 0 && isOnline)
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$pendingCount inspection(s) ready to sync',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isOnline && !isSyncing
                      ? () async {
                          await _syncService.syncNow();
                          _refreshStatus();
                        }
                      : null,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.green[700],
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Inspections automatically sync to the dispatch dashboard when the device is online. '
                'Tap "Sync Now" to manually trigger syncing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
