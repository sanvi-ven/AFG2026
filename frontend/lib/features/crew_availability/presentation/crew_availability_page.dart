import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/employee_availability_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/employee_availability.dart';
import '../../../models/employee_profile.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'employee_availability_calendar.dart';

/// crew availability area: employees mark the days they can work, owners
/// browse day by day to see who's available.
class CrewAvailabilityPage extends StatelessWidget {
  const CrewAvailabilityPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Crew Availability',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.crewAvailability,
      body: role == 'owner'
          ? const _OwnerDayView()
          : role == 'employee'
              ? const _EmployeeAvailabilitySection()
              : const Center(
                  child: Text('Crew availability is for employees and business owners.'),
                ),
    );
  }
}

class _EmployeeAvailabilitySection extends StatelessWidget {
  const _EmployeeAvailabilitySection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: EmployeeSession.profile,
      builder: (context, profile, _) {
        if (profile == null) {
          return const Center(child: Text('Log in to manage your availability.'));
        }
        return EmployeeAvailabilityCalendar(employeeId: profile.employeeId);
      },
    );
  }
}

/// owner-only day-by-day browse view: for a selected day, lists only the
/// employees who marked themselves available that day, with prev/next-day
/// controls and a "Today" reset — same shape as EquipmentScheduleTab.
class _OwnerDayView extends StatefulWidget {
  const _OwnerDayView();

  @override
  State<_OwnerDayView> createState() => _OwnerDayViewState();
}

class _OwnerDayViewState extends State<_OwnerDayView> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDay.year == now.year &&
        _selectedDay.month == now.month &&
        _selectedDay.day == now.day;
  }

  void _shiftDay(int deltaDays) {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: deltaDays));
    });
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() => _selectedDay = DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDay);

    return Column(
      children: [
        _buildDayControls(context),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<EmployeeProfile>>(
            stream: EmployeeProfileService.watchAllProfiles(),
            builder: (context, employeeSnapshot) {
              final employees = <String, EmployeeProfile>{
                for (final employee in employeeSnapshot.data ?? const <EmployeeProfile>[])
                  employee.employeeId: employee,
              };

              return StreamBuilder<List<EmployeeAvailability>>(
                stream: EmployeeAvailabilityService.watchAll(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Failed to load availability: ${snapshot.error}'));
                  }

                  final all = snapshot.data ?? const <EmployeeAvailability>[];
                  final forDay = all.where((a) => a.date == dayKey).toList()
                    ..sort((a, b) {
                      final nameA = employees[a.employeeId]?.fullName ?? a.employeeId;
                      final nameB = employees[b.employeeId]?.fullName ?? b.employeeId;
                      return nameA.compareTo(nameB);
                    });

                  if (forDay.isEmpty) {
                    return const Center(
                      child: Text('No one has marked themselves available for this day.'),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final availability in forDay)
                        _OwnerAvailabilityRow(
                          availability: availability,
                          employee: employees[availability.employeeId],
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayControls(BuildContext context) {
    final label = DateFormat('EEE, MMM d, yyyy').format(_selectedDay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: Column(
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (!_isToday)
                  TextButton(onPressed: _resetToToday, child: const Text('Today')),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }
}

class _OwnerAvailabilityRow extends StatelessWidget {
  const _OwnerAvailabilityRow({required this.availability, required this.employee});

  final EmployeeAvailability availability;
  final EmployeeProfile? employee;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final String window;
    if (availability.isAllDay) {
      window = 'All day';
    } else if (availability.startTime != null && availability.endTime != null) {
      window = '${timeFmt.format(availability.startTime!)} – ${timeFmt.format(availability.endTime!)}';
    } else if (availability.startTime != null) {
      window = 'From ${timeFmt.format(availability.startTime!)}';
    } else {
      window = 'Until ${timeFmt.format(availability.endTime!)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(employee?.fullName ?? availability.employeeId),
        subtitle: Text(window),
      ),
    );
  }
}
