/// Pure presentation logic for the system-pin provenance caveat. No Flutter
/// imports so it is unit-testable without pumping a widget.
library;

class ProvenanceCaveat {
  /// Short bold line, e.g. "Uncertain — verify locally".
  final String headline;

  /// The explanation, phrased around the pin's ORIGIN (not its current
  /// status) so it stays coherent even after a community member edits it.
  final String body;

  /// Medium/UNCERTAIN pins get stronger visual treatment.
  final bool elevated;

  const ProvenanceCaveat({
    required this.headline,
    required this.body,
    required this.elevated,
  });
}

/// Friendly label for an importer source code.
String sourceLabel(String source) {
  switch (source) {
    case 'nces':
      return 'public school records (NCES)';
    case 'ipeds':
      return 'college records (IPEDS)';
    case 'gsa':
      return 'federal property records (GSA)';
    case 'hifld_courts':
      return 'courthouse records (HIFLD)';
    case 'hifld_military':
      return 'military site records (HIFLD/USACE)';
    case 'faa':
      return 'FAA airport records';
    case 'osm':
      return 'OpenStreetMap';
    default:
      return 'public records';
  }
}

/// Returns the caveat for a system pin, or null for user-created pins.
ProvenanceCaveat? caveatFor({
  required String source,
  String? confidence,
  String? legalCitation,
  String? legalCitationVerifiedDate,
}) {
  if (source == 'user') return null;

  final citation = (legalCitation == null || legalCitation.isEmpty)
      ? null
      : legalCitation;
  final verified =
      (legalCitationVerifiedDate == null || legalCitationVerifiedDate.isEmpty)
      ? null
      : legalCitationVerifiedDate;
  final cite = citation == null ? '' : ' under $citation';
  final asOf = verified == null ? '' : ' (verified $verified)';

  if (confidence == 'medium') {
    return ProvenanceCaveat(
      headline: 'Uncertain — verify locally',
      body:
          'This venue may restrict carry$cite, but we could not confirm it '
          'meets the legal threshold. Treat as uncertain and verify locally.',
      elevated: true,
    );
  }

  return ProvenanceCaveat(
    headline: 'Auto-classified — verify locally',
    body:
        'This location was auto-classified from ${sourceLabel(source)}$cite'
        '$asOf. Laws and posted signage change — verify locally before relying '
        'on this.',
    elevated: false,
  );
}

/// OSM object URL for an osm-sourced pin, or null otherwise.
String? osmObjectUrl({required String source, String? sourceExternalId}) {
  if (source != 'osm') return null;
  final id = sourceExternalId;
  if (id == null || !RegExp(r'^(node|way|relation)/\d+$').hasMatch(id)) {
    return null;
  }
  return 'https://www.openstreetmap.org/$id';
}
