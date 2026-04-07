import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';

class AvailabilityPage extends StatelessWidget {
  const AvailabilityPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return AppScaffold(
        title: 'Availability',
        role: role,
        selectedRoute: '/availability',
        body: const Center(child: Text('Availability management is for business owners only.')),
      );
    }

    const calendarUrl =
        "https://calendar.google.com/calendar/embed?height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&src=YW5jaG9yY29ycDNAZ21haWwuY29t&src=YmU4YTA1MjEzMTQ0MGNhYmYyYTQwYjMwMmNkZDYzMjU2OTk0MzczZDRhYmZhNTEwY2UzMDRiMjdjODg3ZTU1NUBncm91cC5jYWxlbmRhci5nb29nbGUuY29t&src=ZW4udXNhI2hvbGlkYXlAZ3JvdXAudi5jYWxlbmRhci5nb29nbGUuY29t&color=%23039be5&color=%23a79b8e&color=%230b8043";

    return AppScaffold(
      title: 'Availability',
      role: role,
      selectedRoute: '/availability',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.calendar_today_outlined),
            title: Text('Set recurring weekly hours'),
            subtitle: Text('Example: Mon-Fri, 9:00 AM - 5:00 PM'),
          ),
          const ListTile(
            leading: Icon(Icons.block),
            title: Text('Block unavailable slots'),
            subtitle: Text('Set holidays and one-off unavailable windows'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your Calendar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GoogleCalendarWidget(calendarSrc: calendarUrl),
        ],
      ),
    );
  }
}
