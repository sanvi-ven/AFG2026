// this file's structure was made with the help of chatgpt 4.0; prompt: make a flutter app router outline with onGenerateRoute and multiple routs

import 'package:flutter/material.dart';

import '../../features/admin/presentation/team_admin_page.dart';
import '../../features/appointments/presentation/appointments_page.dart';
import '../../features/auth/presentation/claim_account_page.dart';
import '../../features/auth/presentation/client_signup_page.dart';
import '../../features/auth/presentation/employee_signup_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/owner_signin_page.dart';
import '../../features/availability/presentation/availability_page.dart';
import '../../features/clients/presentation/clients_page.dart';
import '../../features/crew_availability/presentation/crew_availability_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/equipment/presentation/equipment_catalog_page.dart';
import '../../features/equipment/presentation/equipment_detail_page.dart';
import '../../features/equipment/presentation/equipment_form_page.dart';
import '../../features/estimates/estimates_page.dart';
import '../../features/estimates/presentation/checklist_templates_page.dart';
import '../../features/estimates/presentation/service_catalog_page.dart';
import '../../features/invoices/presentation/invoices_page.dart';
import '../../features/jobs/presentation/employee_jobs_page.dart';
import '../../features/jobs/presentation/job_detail_page.dart';
import '../../features/jobs/presentation/todays_route_page.dart';
import '../../features/messages/presentation/messages_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/reports/presentation/owner_reports_page.dart';
import '../../features/requests/presentation/request_form_page.dart';
import '../../features/requests/presentation/requests_page.dart';
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
  static const clients = '/admin/clients';
  static const claimAccount = '/claim';
  static const reports = '/reports';
  static const todaysRoute = '/jobs/today';
  static const serviceCatalog = '/estimates/catalog';
  static const notifications = '/notifications';
  static const requests = '/requests';
  static const requestWork = '/requests/new';
  static const checklistTemplates = '/estimates/checklists';
  static const equipmentCatalog = '/equipment';
  static const equipmentDetail = '/equipment/detail';
  static const equipmentForm = '/equipment/form';
  static const crewAvailability = '/crew-availability';
/// generates appropriate page route based on settings and passes role/auth context
  
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = (settings.arguments as Map<String, dynamic>?) ?? {};
    final role = (args['role'] as String?) ?? 'client';
    final authToken = args['authToken'] as String?;
    final highlightId = args['highlightId'] as String?;

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
          builder: (_) => AppointmentsPage(role: role, authToken: authToken, highlightId: highlightId),
          settings: settings,
        );
      case invoices:
        return _NoAnimationPageRoute(
          builder: (_) => InvoicesPage(role: role, authToken: authToken, highlightId: highlightId),
          settings: settings,
        );
      case estimates:
        return _NoAnimationPageRoute(
          builder: (_) => EstimatesPage(
            role: role,
            authToken: authToken,
            highlightId: highlightId,
            initialClientId: args['initialClientId'] as String?,
            initialNotes: args['initialNotes'] as String?,
            convertRequestId: args['convertRequestId'] as String?,
          ),
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
      case clients:
        return _NoAnimationPageRoute(
          builder: (_) => ClientsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case claimAccount:
        return _NoAnimationPageRoute(
          builder: (_) => const ClaimAccountPage(),
          settings: settings,
        );
      case reports:
        return _NoAnimationPageRoute(
          builder: (_) => OwnerReportsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case todaysRoute:
        return _NoAnimationPageRoute(
          builder: (_) => TodaysRoutePage(role: role, authToken: authToken),
          settings: settings,
        );
      case serviceCatalog:
        return _NoAnimationPageRoute(
          builder: (_) => ServiceCatalogPage(role: role, authToken: authToken),
          settings: settings,
        );
      case notifications:
        return _NoAnimationPageRoute(
          builder: (_) => NotificationsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case requestWork:
        return _NoAnimationPageRoute(
          builder: (_) => RequestFormPage(
            clientId: args['clientId'] as String?,
            initialName: (args['initialName'] as String?) ?? '',
            initialEmail: (args['initialEmail'] as String?) ?? '',
            initialPhone: (args['initialPhone'] as String?) ?? '',
            initialAddress: (args['initialAddress'] as String?) ?? '',
          ),
          settings: settings,
        );
      case requests:
        return _NoAnimationPageRoute(
          builder: (_) => RequestsPage(role: role, authToken: authToken),
          settings: settings,
        );
      case checklistTemplates:
        return _NoAnimationPageRoute(
          builder: (_) => ChecklistTemplatesPage(role: role, authToken: authToken),
          settings: settings,
        );
      case equipmentCatalog:
        return _NoAnimationPageRoute(
          builder: (_) => EquipmentCatalogPage(role: role, authToken: authToken),
          settings: settings,
        );
      case equipmentDetail:
        return _NoAnimationPageRoute(
          builder: (_) => EquipmentDetailPage(
            role: role,
            authToken: authToken,
            equipmentId: (args['equipmentId'] as String?) ?? '',
          ),
          settings: settings,
        );
      case equipmentForm:
        return _NoAnimationPageRoute(
          builder: (_) => EquipmentFormPage(
            role: role,
            authToken: authToken,
            existingId: args['existingId'] as String?,
          ),
          settings: settings,
        );
      case crewAvailability:
        return _NoAnimationPageRoute(
          builder: (_) => CrewAvailabilityPage(role: role, authToken: authToken),
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
