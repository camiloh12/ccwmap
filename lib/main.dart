import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/data/repositories/supabase_auth_repository.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/sync_manager.dart';
import 'package:ccwmap/data/sync/background_sync.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

// Global database instance
late final AppDatabase database;
// Global network monitor
late final NetworkMonitor networkMonitor;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  // Initialize database
  database = AppDatabase();

  // Initialize network monitor
  networkMonitor = NetworkMonitor();
  await networkMonitor.initialize();

  // Initialize background sync (Iteration 11)
  await initializeBackgroundSync();

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

  // Create repositories
  final pinRepository = PinRepositoryImpl(
    database.pinDao,
    database.syncQueueDao,
    syncManager: syncManager,
  );
  final authRepository = SupabaseAuthRepository(supabaseClient);

  // Create ViewModels
  final mapViewModel = MapViewModel(pinRepository, networkMonitor);
  final authViewModel = AuthViewModel(authRepository);

  runApp(
    CCWMapApp(
      mapViewModel: mapViewModel,
      authViewModel: authViewModel,
    ),
  );
}

class CCWMapApp extends StatelessWidget {
  final MapViewModel mapViewModel;
  final AuthViewModel authViewModel;

  const CCWMapApp({
    super.key,
    required this.mapViewModel,
    required this.authViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: mapViewModel),
        ChangeNotifierProvider.value(value: authViewModel),
      ],
      child: MaterialApp(
        title: 'CCW Map',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE), // Purple primary color
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// Gate that shows LoginScreen or MapScreen based on authentication state
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize AuthViewModel after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = context.read<AuthViewModel>();
      authViewModel.initialize();
      _initializeDeepLinkListener(authViewModel);
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    // Handle initial deep link (cold start - app was closed)
    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('AuthGate: Processing initial deep link: $initialLink');
        await authViewModel.handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('AuthGate: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    // Listen to runtime deep links (app is already open)
    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('AuthGate: Processing runtime deep link: $uri');
        authViewModel.handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('AuthGate: Deep link stream error: $err');
        authViewModel.setError('Failed to process authentication link.');
      },
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, child) {
        // Show loading while initializing
        if (authViewModel.currentUser == null && authViewModel.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Show MapScreen if authenticated, LoginScreen otherwise
        if (authViewModel.isAuthenticated) {
          return const MapScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
