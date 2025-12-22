import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';

// Global database instance
late final AppDatabase database;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize database
  database = AppDatabase();

  // Create repository and ViewModel
  final pinRepository = PinRepositoryImpl(database.pinDao);
  final mapViewModel = MapViewModel(pinRepository);

  runApp(CCWMapApp(mapViewModel: mapViewModel));
}

class CCWMapApp extends StatelessWidget {
  final MapViewModel mapViewModel;

  const CCWMapApp({super.key, required this.mapViewModel});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: mapViewModel,
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
        home: const MapScreen(),
      ),
    );
  }
}
