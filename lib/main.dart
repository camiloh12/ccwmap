import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:app_links/app_links.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:ccwmap/presentation/screens/reset_password_screen.dart';
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
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/presentation/widgets/eula_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccwmap/presentation/utils/terms_url.dart';

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
  final authRepository = SupabaseAuthRepository(
    supabaseClient,
    syncManager: syncManager,
  );

  // Create ViewModels
  final mapViewModel = MapViewModel(
    pinRepository,
    networkMonitor,
    blocklistService,
  );
  final authViewModel = AuthViewModel(authRepository);

  runApp(
    CCWMapApp(
      mapViewModel: mapViewModel,
      authViewModel: authViewModel,
      blocklistService: blocklistService,
      agreementsRepository: agreementsRepository,
      moderationRepository: moderationRepository,
    ),
  );
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
  static const _eulaFlagKey = 'eula_acknowledged_v1';

  StreamSubscription<Uri>? _deepLinkSubscription;
  bool _passiveEulaShown = false;
  bool _retroactiveEulaChecked = false;
  bool _resetScreenPushed = false;
  User? _lastAuthUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthViewModel>();
      auth.initialize();
      _initializeDeepLinkListener(auth);
      await _maybeShowPassiveEula();
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    Future<void> processAndMaybeShowError(Uri uri) async {
      await authViewModel.handleDeepLink(uri);
      if (!mounted) return;
      final err = authViewModel.error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 6),
          ),
        );
        authViewModel.clearError();
      }
    }

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('_AppRoot: Processing initial deep link: $initialLink');
        await processAndMaybeShowError(initialLink);
      }
    } catch (e) {
      debugPrint('_AppRoot: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('_AppRoot: Processing runtime deep link: $uri');
        processAndMaybeShowError(uri);
      },
      onError: (err) {
        debugPrint('_AppRoot: Deep link stream error: $err');
        authViewModel.setError('Failed to process authentication link.');
      },
    );
  }

  Future<void> _maybeShowPassiveEula() async {
    if (_passiveEulaShown) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_eulaFlagKey) == true) {
      _passiveEulaShown = true;
      return;
    }
    _passiveEulaShown = true;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EulaModal(
        mode: EulaModalMode.passiveFirstLaunch,
        onAccept: () async {
          await prefs.setBool(_eulaFlagKey, true);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
        onReadTerms: openTermsUrl,
      ),
    );
  }

  Future<void> _maybeShowRetroactiveEula(User user) async {
    if (_retroactiveEulaChecked) return;
    _retroactiveEulaChecked = true;

    final agreements = context.read<AgreementsRepository>();
    final blocklist = context.read<BlocklistService>();
    final auth = context.read<AuthViewModel>();

    // Refresh blocklist now that a user is signed in.
    try {
      await blocklist.refresh();
    } catch (_) {
      /* non-fatal */
    }

    bool accepted;
    try {
      accepted = await agreements.hasAcceptedAgreement(
        userId: user.id,
        version: AgreementsRepository.currentAgreementVersion,
      );
    } catch (_) {
      return; // don't block on transient errors
    }
    if (accepted) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: EulaModal(
          mode: EulaModalMode.retroactiveBlocking,
          onAccept: () async {
            try {
              await agreements.recordAgreementAcceptance(
                userId: user.id,
                version: AgreementsRepository.currentAgreementVersion,
              );
            } catch (_) {
              /* non-fatal */
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          onReadTerms: openTermsUrl,
          onSignOut: () async {
            if (ctx.mounted) Navigator.of(ctx).pop();
            await auth.signOut();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Trigger the retroactive check when an authenticated user becomes
    // available (post-initialize or post-signin). Firing here instead of
    // in initState lets us observe the auth-state change cleanly.
    final auth = context.watch<AuthViewModel>();
    final current = auth.currentUser;
    if (current != null && current != _lastAuthUser) {
      _lastAuthUser = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _retroactiveEulaChecked = false; // re-check on each new sign-in
        _maybeShowRetroactiveEula(current);
      });
    }
    if (current == null && _lastAuthUser != null) {
      // User signed out — clear cached blocklist and reset retroactive flag.
      context.read<BlocklistService>().clear();
      _lastAuthUser = null;
      _retroactiveEulaChecked = false;
    }

    // When a password-recovery deep link is processed, the AuthViewModel
    // flips isInPasswordRecovery to true. Push the ResetPasswordScreen on
    // the root navigator and block further pushes until the screen pops
    // (whether via successful update or Cancel).
    if (auth.isInPasswordRecovery && !_resetScreenPushed) {
      _resetScreenPushed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute<void>(
              builder: (_) => const ResetPasswordScreen(),
            ))
            .then((_) {
          _resetScreenPushed = false;
        });
      });
    }

    return const MapScreen();
  }
}
