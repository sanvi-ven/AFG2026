import 'package:http/http.dart' as http;
import 'dart:convert';

import 'firebase_service.dart';

class GoogleCalendarEvent {
  final String id;
  final String summary;
  final String? description;
  final DateTime start;
  final DateTime end;

  GoogleCalendarEvent({
    required this.id,
    required this.summary,
    this.description,
    required this.start,
    required this.end,
  });

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    return GoogleCalendarEvent(
      id: json['id'] as String,
      summary: json['summary'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      start: DateTime.parse(json['start']['dateTime'] as String? ?? json['start']['date'] as String),
      end: DateTime.parse(json['end']['dateTime'] as String? ?? json['end']['date'] as String),
    );
  }
}

class GoogleCalendarService {
  static const String _calendarApiUrl = 'https://www.googleapis.com/calendar/v3';

  static Future<List<GoogleCalendarEvent>> getEvents({
    int maxResults = 10,
    bool upcomingOnly = true,
  }) async {
    final accessToken = FirebaseService.getAccessToken();
    if (accessToken == null) {
      throw Exception('No Google access token. User not authenticated.');
    }

    final now = DateTime.now().toUtc();
    final timeMin = upcomingOnly ? now.toIso8601String() : null;

    final url = Uri.parse(
      '$_calendarApiUrl/calendars/primary/events'
      '?maxResults=$maxResults'
      '${timeMin != null ? '&timeMin=$timeMin' : ''}'
      '&orderBy=startTime'
      '&singleEvents=true',
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items
          .map((item) => GoogleCalendarEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to fetch calendar events: ${response.statusCode}');
    }
  }

  static Future<GoogleCalendarEvent> createEvent({
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
  }) async {
    final accessToken = FirebaseService.getAccessToken();
    if (accessToken == null) {
      throw Exception('No Google access token. User not authenticated.');
    }

    final url = Uri.parse('$_calendarApiUrl/calendars/primary/events');

    final body = {
      'summary': summary,
      'description': description,
      'start': {'dateTime': start.toIso8601String()},
      'end': {'dateTime': end.toIso8601String()},
    };

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return GoogleCalendarEvent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw Exception('Failed to create event: ${response.statusCode} - ${response.body}');
    }
  }

  static Future<void> deleteEvent(String eventId) async {
    final accessToken = FirebaseService.getAccessToken();
    if (accessToken == null) {
      throw Exception('No Google access token. User not authenticated.');
    }

    final url = Uri.parse('$_calendarApiUrl/calendars/primary/events/$eventId');

    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete event: ${response.statusCode}');
    }
  }

  static Future<GoogleCalendarEvent> updateEvent({
    required String eventId,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
  }) async {
    final accessToken = FirebaseService.getAccessToken();
    if (accessToken == null) {
      throw Exception('No Google access token. User not authenticated.');
    }

    final url = Uri.parse('$_calendarApiUrl/calendars/primary/events/$eventId');

    final body = {
      'summary': summary,
      'description': description,
      'start': {'dateTime': start.toIso8601String()},
      'end': {'dateTime': end.toIso8601String()},
    };

    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return GoogleCalendarEvent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw Exception('Failed to update event: ${response.statusCode} - ${response.body}');
    }
  }
}
