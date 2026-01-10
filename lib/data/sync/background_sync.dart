import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../database/database.dart';
import '../datasources/supabase_remote_data_source.dart';
import '../services/network_monitor.dart';
import 'sync_manager.dart';

/// Background sync task name
const String syncTaskName = 'syncPinsTask';

/// Background sync unique name
const String syncTaskUniqueName = 'sync-pins';

/// Top-level callback dispatcher for WorkManager
///
/// IMPORTANT: This function must be a top-level function (not a class method)
/// because it runs in a separate isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('[BackgroundSync] Starting background sync task: $task');

      // Load environment variables
      await dotenv.load(fileName: ".env");

      // Initialize Supabase
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      // Initialize database
      final database = AppDatabase();

      // Initialize network monitor
      final networkMonitor = NetworkMonitor();
      await networkMonitor.initialize();

      // Check if we're online
      if (!networkMonitor.isOnline) {
        print('[BackgroundSync] Device is offline, skipping sync');
        networkMonitor.dispose();
        await database.close();
        return Future.value(true); // Return success even if offline
      }

      // Create data sources
      final supabaseClient = Supabase.instance.client;
      final remoteDataSource = SupabaseRemoteDataSource(supabaseClient);

      // Create sync manager
      final syncManager = SyncManager(
        syncQueueDao: database.syncQueueDao,
        pinDao: database.pinDao,
        remoteDataSource: remoteDataSource,
        networkMonitor: networkMonitor,
      );

      // Perform sync
      final result = await syncManager.sync();

      print('[BackgroundSync] Sync complete: uploaded=${result.uploaded}, '
          'downloaded=${result.downloaded}, errors=${result.errors}');

      // Cleanup
      networkMonitor.dispose();
      await database.close();

      // Return true on success, false on failure
      return Future.value(result.isSuccess);
    } catch (e) {
      print('[BackgroundSync] Error during background sync: $e');
      return Future.value(false);
    }
  });
}

/// Initialize and register background sync with WorkManager
Future<void> initializeBackgroundSync() async {
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    // Register periodic sync task (minimum 15 minutes on Android)
    await Workmanager().registerPeriodicTask(
      syncTaskUniqueName,
      syncTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 10),
    );

    print('[BackgroundSync] Periodic sync registered (every 15 minutes)');
  } catch (e) {
    print('[BackgroundSync] Failed to initialize background sync: $e');
  }
}

/// Cancel background sync
Future<void> cancelBackgroundSync() async {
  try {
    await Workmanager().cancelByUniqueName(syncTaskUniqueName);
    print('[BackgroundSync] Background sync cancelled');
  } catch (e) {
    print('[BackgroundSync] Failed to cancel background sync: $e');
  }
}
