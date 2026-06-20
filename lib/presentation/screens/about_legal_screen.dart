import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Attribution + legal credits. Reachable by everyone (including guests) via
/// the map attribution badge, and from Settings for signed-in users.
class AboutLegalScreen extends StatelessWidget {
  const AboutLegalScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Legal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Map data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Some pins are derived from OpenStreetMap and are made available '
              'under the Open Database License (ODbL). © OpenStreetMap '
              'contributors. Our OSM-derived data is republished under ODbL as '
              'a public data dump after each import.',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _open('https://www.openstreetmap.org/copyright'),
              child: const Text('OpenStreetMap copyright & ODbL'),
            ),
            const Divider(height: 32),
            const Text('Basemap', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Basemap tiles © MapTiler © OpenStreetMap contributors.'),
            TextButton(
              onPressed: () => _open('https://www.maptiler.com/copyright/'),
              child: const Text('MapTiler attribution'),
            ),
          ],
        ),
      ),
    );
  }
}
