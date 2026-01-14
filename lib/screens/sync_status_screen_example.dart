// Example: Adding Inspection Sync Status to Profile Screen
// 
// Add this to your profile_screen.dart or create a new Settings screen

import 'package:flutter/material.dart';
import '../widgets/inspection_sync_status_widget.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text(
          'Dispatch Sync Status',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: const InspectionSyncStatusWidget(),
    );
  }
}

// Usage in Navigation:
// 
// In your main menu or profile screen, add:
// 
//   ElevatedButton(
//     onPressed: () => Navigator.push(
//       context,
//       MaterialPageRoute(builder: (_) => const SyncStatusScreen()),
//     ),
//     child: const Text('Sync Status'),
//   ),
//
// Or as a drawer item:
//
//   ListTile(
//     leading: const Icon(Icons.cloud_sync),
//     title: const Text('Dispatch Sync'),
//     onTap: () => Navigator.push(
//       context,
//       MaterialPageRoute(builder: (_) => const SyncStatusScreen()),
//     ),
//   ),
