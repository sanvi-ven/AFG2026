import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';
import '../../../shared/widgets/google_calendar_booking_button.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const String _calendarUrl =
      'https://calendar.google.com/calendar/embed?mode=WEEK&height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=1&showCalendars=0&showTz=0&src=immc17289%40gmail.com&color=%23039BE5';

  static const String _schedulingUrl =
      'https://calendar.google.com/calendar/appointments/schedules/AcZssZ0vl6GyDUbhfZVYEi-NzQpylnetU7nK0p2b9fgeN4vv_SpQKa-NuMxTtvUVm5wNEeUPBtIYvfrW?gv=true';

  Future<void> _openGoogleCalendar() async {
    const url = 'https://calendar.google.com/calendar/u/0/r/week';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Appointments',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.role == 'client') ...[
            GoogleCalendarBookingButton(scheduleUrl: _schedulingUrl),
            const SizedBox(height: 24),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.role == 'client' ? 'Your Calendar' : 'Appointments Calendar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.role == 'owner')
                FilledButton.icon(
                  onPressed: _openGoogleCalendar,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in Google'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const GoogleCalendarWidget(
            calendarSrc: _AppointmentsPageState._calendarUrl,
            height: 520,
          ),
        ],
      ),
    );
  }
}
