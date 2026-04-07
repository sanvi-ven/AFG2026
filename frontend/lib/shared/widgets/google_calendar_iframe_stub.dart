import 'package:flutter/material.dart';

Widget buildGoogleCalendarIFrame({
  required String src,
  required double height,
}) {
  return SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendar iframe is available on web builds.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('Open this Google Calendar URL in a browser tab:'),
          const SizedBox(height: 8),
          SelectableText(src),
        ],
      ),
    ),
  );
}