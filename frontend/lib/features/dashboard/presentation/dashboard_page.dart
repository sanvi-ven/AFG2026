import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/firebase_service.dart';
import '../../../models/appointment.dart';
import '../../../shared/widgets/app_scaffold.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Appointment? _nextAppointment;
  bool _isLoadingUpcoming = true;
  String? _upcomingError;

  @override
  void initState() {
    super.initState();
    _loadUpcomingAppointment();
  }

  Future<void> _loadUpcomingAppointment() async {
    final demoToken = AppConfig.demoAuthToken.trim();
    final firebaseToken = await FirebaseService.getFreshIdToken();
    final token = demoToken.isNotEmpty
      ? demoToken
      : (firebaseToken?.trim().isNotEmpty ?? false)
        ? firebaseToken!.trim()
        : (widget.authToken?.trim().isNotEmpty ?? false)
          ? widget.authToken!.trim()
          : '';

    if (token.isEmpty) {
      setState(() {
        _isLoadingUpcoming = false;
        _nextAppointment = null;
        _upcomingError = null;
      });
      return;
    }

    setState(() {
      _isLoadingUpcoming = true;
      _upcomingError = null;
    });

    try {
      final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
      final rows = await apiClient.getListJson('/api/v1/appointments');
      final nowUtc = DateTime.now().toUtc();
      final upcoming = rows
          .map(Appointment.fromJson)
          .where((appt) => appt.status != 'canceled' && appt.startTime.toUtc().isAfter(nowUtc))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      if (!mounted) {
        return;
      }

      setState(() {
        _nextAppointment = upcoming.isNotEmpty ? upcoming.first : null;
        _isLoadingUpcoming = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingUpcoming = false;
        _nextAppointment = null;
        _upcomingError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _buildUpcomingSubtitle() {
    if (_isLoadingUpcoming) {
      return 'Loading upcoming appointments...';
    }
    if (_upcomingError != null) {
      return 'Unable to load appointments right now';
    }
    if (_nextAppointment == null) {
      return 'No upcoming appointments';
    }

    final formatted = DateFormat('EEE, MMM d • h:mm a').format(_nextAppointment!.startTime.toLocal());
    return 'Next appointment: $formatted';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dashboard',
      role: widget.role,
      selectedRoute: '/dashboard',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome, ${widget.role == 'owner' ? 'Business Owner' : 'Client'}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _linkCard(
            context,
            title: 'Upcoming appointments',
            subtitle: _buildUpcomingSubtitle(),
            route: AppRouter.appointments,
          ),
          if (widget.role == 'client')
            _linkCard(
              context,
              title: 'Book Appointment',
              subtitle: 'Pick an available slot from the bookings calendar',
              route: AppRouter.appointments,
            ),
          _linkCard(context, title: 'Messages', subtitle: 'Unread and recent conversations', route: AppRouter.messages),
          _linkCard(context, title: 'Unpaid invoices', subtitle: 'Pending and overdue invoice balances', route: AppRouter.invoices),
          _linkCard(context, title: 'Estimates', subtitle: 'Review requests and quotes', route: AppRouter.estimates),
          if (widget.role == 'owner')
            _linkCard(
              context,
              title: 'Availability',
              subtitle: 'Manage your working hours and blocked times',
              route: AppRouter.availability,
            ),
        ],
      ),
    );
  }

  Widget _linkCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushNamed(
            context,
            route,
            arguments: {'role': widget.role, 'authToken': widget.authToken},
          );
        },
      ),
    );
  }
}
