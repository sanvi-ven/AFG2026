import 'package:flutter/material.dart';

import '../../features/appointments/presentation/appointments_page.dart';
import '../../features/auth/presentation/client_signup_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/availability/presentation/availability_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/invoices/presentation/invoices_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';

// PageRoute with no transition animation
class _NoAnimationPageRoute<T> extends PageRoute<T> {
  _NoAnimationPageRoute({required this.builder, required this.settings});

  final WidgetBuilder builder;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  final RouteSettings settings;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 0);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;
}

class AppRouter {
  static const login = '/';
  static const clientSignup = '/signup/client';
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
        return _NoAnimationPageRoute(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case dashboard:
        return _NoAnimationPageRoute(
          builder: (_) => DashboardPage(role: role, authToken: authToken),
          settings: settings,
        );
      case clientSignup:
        return _NoAnimationPageRoute(
          builder: (_) => const ClientSignupPage(),
          settings: settings,
        );
      case appointments:
        return _NoAnimationPageRoute(
          builder: (_) => AppointmentsPage(role: role),
          settings: settings,
        );
      case invoices:
        return _NoAnimationPageRoute(
          builder: (_) => InvoicesPage(role: role),
          settings: settings,
        );
      case messages:
        return _NoAnimationPageRoute(
          builder: (_) => MessagesPage(role: role),
          settings: settings,
        );
      case notifications:
        return _NoAnimationPageRoute(
          builder: (_) => NotificationsPage(role: role),
          settings: settings,
        );
      case availability:
        return _NoAnimationPageRoute(
          builder: (_) => AvailabilityPage(role: role),
          settings: settings,
        );
      default:
        return _NoAnimationPageRoute(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
    }
  }
}
