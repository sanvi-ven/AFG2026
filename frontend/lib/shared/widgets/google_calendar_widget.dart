import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'google_calendar_iframe_stub.dart'
  if (dart.library.html) 'google_calendar_iframe_web.dart' as calendar_iframe;

class GoogleCalendarWidget extends StatefulWidget {
  const GoogleCalendarWidget({
    required this.calendarSrc,
    this.height = 600,
    this.width = 800,
    super.key,
  });

  final String calendarSrc;
  final double height;
  final double width;

  @override
  State<GoogleCalendarWidget> createState() => _GoogleCalendarWidgetState();
}

class _GoogleCalendarWidgetState extends State<GoogleCalendarWidget> {
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(_buildHtmlContent());
    }
  }

  String _buildHtmlContent() {
    return '''
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body, html {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
          }
          iframe {
            border: solid 1px #777;
            width: 100%;
            height: 100%;
            display: block;
          }
        </style>
      </head>
      <body>
        <iframe src="${widget.calendarSrc}" frameborder="0" scrolling="no"></iframe>
      </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: calendar_iframe.buildGoogleCalendarIFrame(
            src: widget.calendarSrc,
            height: widget.height,
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Card(
        elevation: 2,
        child: WebViewWidget(controller: _webViewController!),
      ),
    );
  }
}
