import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/data/repositories/supabase_auth_repository.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

// Global database instance
late final AppDatabase database;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize database
  database = AppDatabase();

  // Create repositories
  final pinRepository = PinRepositoryImpl(database.pinDao);
  final authRepository = SupabaseAuthRepository(Supabase.instance.client);

  // Create ViewModels
  final mapViewModel = MapViewModel(pinRepository);
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
  @override
  void initState() {
    super.initState();

    // Initialize AuthViewModel after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = context.read<AuthViewModel>();
      authViewModel.initialize();
    });
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
