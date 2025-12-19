import 'package:flutter/material.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';

void main() {
  runApp(const CCWMapApp());
}

class CCWMapApp extends StatelessWidget {
  const CCWMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    );
  }
}
