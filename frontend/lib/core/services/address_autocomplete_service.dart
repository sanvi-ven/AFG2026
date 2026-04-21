import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressAutocompleteService {
  AddressAutocompleteService._();

  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';

  static Future<List<String>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      return const [];
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '0',
      'limit': '6',
    });
// Used flutter docs to understand how to make http requests: https://docs.flutter.dev/cookbook/networking/fetch-data
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        // Nominatim usage policy requires an identifying user agent.
        'User-Agent': 'AFG2026-ClientSignup/1.0 (contact: local-dev)',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const [];
    }

    final values = decoded
        .whereType<Map<String, dynamic>>()
        .map((item) => (item['display_name'] as String? ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    return values;
  }
}
