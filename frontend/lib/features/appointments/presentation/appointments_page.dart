import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';

class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    const calendarUrl =
        "https://calendar.google.com/calendar/embed?height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&src=YW5jaG9yY29ycDNAZ21haWwuY29t&src=YmU4YTA1MjEzMTQ0MGNhYmYyYTQwYjMwMmNkZDYzMjU2OTk0MzczZDRhYmZhNTEwY2UzMDRiMjdjODg3ZTU1NUBncm91cC5jYWxlbmRhci5nb29nbGUuY29t&src=ZW4udXNhI2hvbGlkYXlAZ3JvdXAudi5jYWxlbmRhci5nb29nbGUuY29t&color=%23039be5&color=%23a79b8e&color=%230b8043";

    return AppScaffold(
      title: 'Appointments',
      role: role,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (role == 'owner')
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Set available time slots'),
              subtitle: Text('Define working hours and open slots'),
            ),
          const ListTile(
            leading: Icon(Icons.event_available),
            title: Text('Book / manage appointments'),
            subtitle: Text('Create, confirm, cancel, or reschedule'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Google Calendar Sync',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GoogleCalendarWidget(calendarSrc: calendarUrl),
        ],
      ),
    );
  }
}
