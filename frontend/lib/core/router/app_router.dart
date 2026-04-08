import 'package:flutter/material.dart';

import '../../features/appointments/presentation/appointments_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/availability/presentation/availability_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/invoices/presentation/invoices_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';

class AppRouter {
  static const login = '/';
  static const dashboard = '/dashboard';
  static const appointments = '/appointments';
  static const invoices = '/invoices';
  static const messages = '/messages';
  static const notifications = '/notifications';
  static const availability = '/availability';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = (settings.arguments as Map<String, dynamic>?) ?? {};
    final role = (args['role'] as String?) ?? 'client';
    final authToken = args['authToken'] as String?;

    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case dashboard:
        return MaterialPageRoute(
          builder: (_) => DashboardPage(role: role, authToken: authToken),
        );
      case appointments:
        return MaterialPageRoute(builder: (_) => AppointmentsPage(role: role));
      case invoices:
        return MaterialPageRoute(builder: (_) => InvoicesPage(role: role));
      case messages:
        return MaterialPageRoute(builder: (_) => MessagesPage(role: role));
      case notifications:
        return MaterialPageRoute(builder: (_) => NotificationsPage(role: role));
      case availability:
        return MaterialPageRoute(builder: (_) => AvailabilityPage(role: role));
      default:
        return MaterialPageRoute(builder: (_) => const LoginPage());
    }
  }
}
