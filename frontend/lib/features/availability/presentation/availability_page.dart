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
        "https://calendar.google.com/calendar/embed?mode=WEEK&height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=1&src=immc17289%40gmail.com&color=%23039be5";

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
