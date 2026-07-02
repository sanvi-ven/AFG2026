// this file's structure was made with the help of chatgpt 4.0; prompt: make a flutter app router outline with onGenerateRoute and multiple routs

import 'package:flutter/material.dart';

import '../../features/admin/presentation/team_admin_page.dart';
import '../../features/appointments/presentation/appointments_page.dart';
import '../../features/auth/presentation/client_signup_page.dart';
import '../../features/auth/presentation/employee_signup_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/owner_signin_page.dart';
import '../../features/availability/presentation/availability_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/estimates/estimates_page.dart';
import '../../features/invoices/presentation/invoices_page.dart';
import '../../features/jobs/presentation/employee_jobs_page.dart';
import '../../features/jobs/presentation/job_detail_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/time/presentation/my_hours_page.dart';

/// custom page route that disables transtion animations for instant navigation.
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

/// central routing handler for the application.
class AppRouter {
  static const login = '/';
  static const clientSignup = '/signup/client';
  static const employeeSignup = '/signup/employee';
  static const ownerSignin = '/signin/owner';
  static const dashboard = '/dashboard';
  static const appointments = '/appointments';
  static const invoices = '/invoices';
  static const estimates = '/estimates';
  static const messages = '/messages';
  static const availability = '/availability';
  static const myJobs = '/jobs';
  static const jobDetail = '/jobs/detail';
  static const myHours = '/hours';
  static const teamAdmin = '/admin/team';
/// generates appropriate page route based on settings and passes role/auth context
  
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
      case employeeSignup:
        return _NoAnimationPageRoute(
          builder: (_) => const EmployeeSignupPage(),
          settings: settings,
        );
      case ownerSignin:
        return _NoAnimationPageRoute(
          builder: (_) => const OwnerSigninPage(),
          settings: settings,
        );
      case appointments:
        return _NoAnimationPageRoute(
          builder: (_) => AppointmentsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case invoices:
        return _NoAnimationPageRoute(
          builder: (_) => InvoicesPage(role: role, authToken: authToken),
          settings: settings,
        );
      case estimates:
        return _NoAnimationPageRoute(
          builder: (_) => EstimatesPage(role: role, authToken: authToken),
          settings: settings,
        );
      case messages:
        return _NoAnimationPageRoute(
          builder: (_) => MessagesPage(role: role, authToken: authToken),
          settings: settings,
        );
      case availability:
        return _NoAnimationPageRoute(
          builder: (_) => AvailabilityPage(role: role, authToken: authToken),
          settings: settings,
        );
      case myJobs:
        return _NoAnimationPageRoute(
          builder: (_) => EmployeeJobsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case jobDetail:
        return _NoAnimationPageRoute(
          builder: (_) => JobDetailPage(
            role: role,
            authToken: authToken,
            workId: (args['workId'] as String?) ?? '',
          ),
          settings: settings,
        );
      case myHours:
        return _NoAnimationPageRoute(
          builder: (_) => MyHoursPage(role: role, authToken: authToken),
          settings: settings,
        );
      case teamAdmin:
        return _NoAnimationPageRoute(
          builder: (_) => TeamAdminPage(role: role, authToken: authToken),
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
