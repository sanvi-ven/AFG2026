import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildGoogleCalendarBookingButton({
  required String scheduleUrl,
  required String label,
  required String color,
  required double height,
}) {
  return SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton(
        onPressed: () async {
          final uri = Uri.tryParse(scheduleUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Text(label),
      ),
    ),
  );
}
