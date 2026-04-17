//https://calendar.google.com/calendar/u/0/r/week

import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final Set<String> _registeredViewTypes = <String>{};

Widget buildGoogleCalendarBookingButton({
  required String scheduleUrl,
  required String label,
  required String color,
  required double height,
}) {
  final viewType = 'google-calendar-booking-button-${scheduleUrl.hashCode}';

  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final container = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '${height}px'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.padding = '12px';

      // Load stylesheet
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'stylesheet';
      link.href = 'https://calendar.google.com/calendar/scheduling-button-script.css';
      web.document.head?.appendChild(link);

      // Load Google Calendar script
      final script = web.document.createElement('script') as web.HTMLScriptElement;
      script.src = 'https://calendar.google.com/calendar/scheduling-button-script.js';
      script.async = true;
      web.document.body?.appendChild(script);

      // Initialize button with delay to ensure script is loaded
      final initScript = web.document.createElement('script') as web.HTMLScriptElement;
      initScript.text = '''
        window.addEventListener('load', function() {
          setTimeout(function() {
            if (window.calendar && window.calendar.schedulingButton) {
              calendar.schedulingButton.load({
                url: '$scheduleUrl',
                color: '$color',
                label: '$label',
                target: document.querySelector('[data-booking-button]'),
              });
            }
          }, 500);
        });
      ''';
      web.document.body?.appendChild(initScript);

      container.setAttribute('data-booking-button', '');

      return container;
    });
    _registeredViewTypes.add(viewType);
  }

  return SizedBox(
    height: height,
    width: double.infinity,
    child: HtmlElementView(viewType: viewType),
  );
}
