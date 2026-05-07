//to understand how to use json serialization: https://docs.flutter.dev/data-and-backend/serialization/json

import 'dart:convert';

import 'package:http/http.dart' as http;

/// http client for making json requests to the backend api.
/// handles headers, authorization, and error parsing.
class ApiClient {
  ApiClient({required this.baseUrl, this.authToken});

  final String baseUrl;
  final String? authToken;

  /// makes a get request and returns a single json object.
  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: _buildHeaders(),
    );
    _throwIfError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getListJson(String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: _buildHeaders(),
    );
    _throwIfError(response);
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
/// makes a post request with json body and returns a single json object.
  
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _buildHeaders(includeJsonContentType: true),
      body: jsonEncode(body),
    );
    _throwIfError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// constructs http headers with content type and bearer token if available
  Map<String, String> _buildHeaders({bool includeJsonContentType = false}) {
    final headers = <String, String>{};
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// checks response status code and throws exception with parsed error messages from backend
  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String message = 'Request failed (${response.statusCode})';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final parsedErrors = detail
            .whereType<Map<String, dynamic>>()
            .map((item) {
              final location = (item['loc'] as List<dynamic>?)
                      ?.map((part) => part.toString())
                      .where((part) => part != 'body')
                      .join('.') ??
                  'field';
              final text = (item['msg'] as String?)?.trim();
              if (text == null || text.isEmpty) {
                return null;
              }
              return '$location: $text';
            })
            .whereType<String>()
            .toList();
        if (parsedErrors.isNotEmpty) {
          message = parsedErrors.join('\n');
        }
      }
    } catch (_) {
      message = response.body.isNotEmpty ? response.body : message;
    }
    throw Exception(message);
  }
}
