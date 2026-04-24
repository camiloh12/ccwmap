import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/data/repositories/supabase_auth_repository.dart';
import 'package:ccwmap/data/repositories/supabase_agreements_repository.dart';
import 'package:ccwmap/data/repositories/supabase_moderation_repository.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/sync_manager.dart';
import 'package:ccwmap/data/sync/background_sync.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
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
  final moderationRepository = SupabaseModerationRepository(remoteDataSource);
  final agreementsRepository = SupabaseAgreementsRepository(remoteDataSource);
  final blocklistService = BlocklistService(moderationRepository);

  // Create sync manager
  final syncManager = SyncManager(
    syncQueueDao: database.syncQueueDao,
    pinDao: database.pinDao,
    tombstoneDao: database.pinTombstoneDao,
    remoteDataSource: remoteDataSource,
    networkMonitor: networkMonitor,
  );

  // Create repositories
  final pinRepository = PinRepositoryImpl(
    database.pinDao,
    database.syncQueueDao,
    database.pinTombstoneDao,
    syncManager: syncManager,
  );
  final authRepository = SupabaseAuthRepository(supabaseClient);

  // Create ViewModels
  final mapViewModel = MapViewModel(pinRepository, networkMonitor, blocklistService);
  final authViewModel = AuthViewModel(authRepository);

  runApp(CCWMapApp(
    mapViewModel: mapViewModel,
    authViewModel: authViewModel,
    blocklistService: blocklistService,
    agreementsRepository: agreementsRepository,
    moderationRepository: moderationRepository,
  ));
}

class CCWMapApp extends StatelessWidget {
  final MapViewModel mapViewModel;
  final AuthViewModel authViewModel;
  final BlocklistService blocklistService;
  final AgreementsRepository agreementsRepository;
  final ModerationRepository moderationRepository;

  const CCWMapApp({
    super.key,
    required this.mapViewModel,
    required this.authViewModel,
    required this.blocklistService,
    required this.agreementsRepository,
    required this.moderationRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: mapViewModel),
        ChangeNotifierProvider.value(value: authViewModel),
        ChangeNotifierProvider.value(value: blocklistService),
        Provider<AgreementsRepository>.value(value: agreementsRepository),
        Provider<ModerationRepository>.value(value: moderationRepository),
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
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: const _AppRoot(),
      ),
    );
  }
}

/// Root widget. Owns auth-state initialization and deep-link listening but
/// does NOT gate routing on auth — the map is visible to everyone. Auth-
/// sensitive affordances (create/edit/delete pins, sign out) are decided
/// inside [MapScreen] by reading [AuthViewModel] directly.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = context.read<AuthViewModel>();
      authViewModel.initialize();
      _initializeDeepLinkListener(authViewModel);
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('_AppRoot: Processing initial deep link: $initialLink');
        await authViewModel.handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('_AppRoot: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('_AppRoot: Processing runtime deep link: $uri');
        authViewModel.handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('_AppRoot: Deep link stream error: $err');
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
  Widget build(BuildContext context) => const MapScreen();
}
