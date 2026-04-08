import 'package:intl/intl.dart';

import '../../../core/services/api_client.dart';

class CalendarBookingRepository {
  CalendarBookingRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Map<String, dynamic>>> getAvailableSlots({
    required DateTime date,
    String timeZone = 'America/New_York',
    int startHour = 8,
    int endHour = 21,
    int slotMinutes = 30,
  }) async {
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final encodedTimeZone = Uri.encodeComponent(timeZone);

    final payload = await _apiClient.getJson(
      '/api/v1/calendar/availability/slots?date=$dateValue&start_hour=$startHour&end_hour=$endHour&slot_minutes=$slotMinutes&time_zone=$encodedTimeZone',
    );

    final slots = payload['slots'] as List<dynamic>? ?? [];
    return slots.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> bookSlot({
    required DateTime date,
    required String startTime,
    required String endTime,
    required String summary,
    String? description,
    String timeZone = 'America/New_York',
  }) async {
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final encodedTimeZone = Uri.encodeComponent(timeZone);

    final body = <String, dynamic>{
      'summary': summary,
      'date': dateValue,
      'start_time': startTime,
      'end_time': endTime,
      'description': description,
    };

    return _apiClient.postJson('/api/v1/calendar/book?time_zone=$encodedTimeZone', body);
  }
}