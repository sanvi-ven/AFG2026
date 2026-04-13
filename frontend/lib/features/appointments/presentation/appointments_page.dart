import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';
import '../../../shared/widgets/google_calendar_booking_button.dart';
import '../data/calendar_booking_repository.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({required this.role, super.key});

  final String role;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const String _calendarUrl =
      'https://calendar.google.com/calendar/embed?mode=WEEK&height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=1&showCalendars=0&showTz=0&src=immc17289%40gmail.com&color=%23039BE5';

  static const String _schedulingUrl =
      'https://calendar.google.com/calendar/appointments/schedules/AcZssZ0vl6GyDUbhfZVYEi-NzQpylnetU7nK0p2b9fgeN4vv_SpQKa-NuMxTtvUVm5wNEeUPBtIYvfrW?gv=true';

  late final CalendarBookingRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = CalendarBookingRepository(ApiClient(baseUrl: AppConfig.apiBaseUrl));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Appointments',
      role: widget.role,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.role == 'owner')
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Set available time slots'),
              subtitle: Text('Client service choices are saved in the booking description.'),
            ),
          if (widget.role == 'client') ...[
            GoogleCalendarBookingButton(scheduleUrl: _schedulingUrl),
            const SizedBox(height: 24),
            Text(
              'Your Calendar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const GoogleCalendarWidget(
              calendarSrc: _AppointmentsPageState._calendarUrl,
              height: 520,
            ),
          ],
          if (widget.role == 'owner') ...[
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.event_available),
              title: Text('Book / manage appointments'),
              subtitle: Text('Create, confirm, cancel, or reschedule'),
            ),
          ]
        ],
      ),
    );
  }
}
