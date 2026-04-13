import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleCalendarBookingButton extends StatelessWidget {
  const GoogleCalendarBookingButton({
    required this.scheduleUrl,
    this.label = 'Book an appointment',
    this.color = '#039BE5',
    this.height = 60,
    super.key,
  });

  final String scheduleUrl;
  final String label;
  final String color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () async {
          final uri = Uri.tryParse(scheduleUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: const Icon(Icons.calendar_today),
        label: Text(label),
      ),
    );
  }
}
