import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';
import '../data/calendar_booking_repository.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const String _calendarUrl =
      'https://calendar.google.com/calendar/embed?mode=WEEK&height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=1&showCalendars=0&showTz=0&src=immc17289%40gmail.com&color=%23039BE5';

  static const List<Map<String, String>> _serviceOptions = [
    {'key': 'landscaping', 'label': 'Landscaping'},
    {'key': 'house_cleaning', 'label': 'House Cleaning'},
    {'key': 'mowing', 'label': 'Mowing'},
    {'key': 'gardening', 'label': 'Gardening'},
    {'key': 'power_washing', 'label': 'Power Washing'},
    {'key': 'tree_trimming', 'label': 'Tree Trimming'},
  ];

  late final CalendarBookingRepository _repository;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _availableSlots = const [];
  bool _isLoadingSlots = false;
  bool _isBooking = false;
  String? _selectedStartTime;
  String? _selectedEndTime;
  final Set<String> _selectedServices = <String>{};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = CalendarBookingRepository(ApiClient(baseUrl: AppConfig.apiBaseUrl));
    if (widget.role == 'client') {
      _loadSlots();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _serviceLabels() {
    final labels = _selectedServices
        .map(
          (key) => _serviceOptions.firstWhere((option) => option['key'] == key)['label']!,
        )
        .toList();
    return labels.isEmpty ? 'None' : labels.join(', ');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _selectedStartTime = null;
      _selectedEndTime = null;
      _availableSlots = const [];
    });
    await _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() => _isLoadingSlots = true);
    try {
      final slots = await _repository.getAvailableSlots(date: _selectedDate);
      if (!mounted) {
        return;
      }
      setState(() => _availableSlots = slots);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load slots: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  Future<void> _bookSelectedSlot() async {
    final startTime = _selectedStartTime;
    final endTime = _selectedEndTime;
    if (startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot.')),
      );
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final selectedServices = _selectedServices.toList();
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name and email.')),
      );
      return;
    }
    if (selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one service.')),
      );
      return;
    }

    setState(() => _isBooking = true);
    try {
      final bookingResult = await _repository.bookSlot(
        date: _selectedDate,
        startTime: startTime,
        endTime: endTime,
        summary: 'Appointment - $name',
        description: 'Booked via Anchor. Client: $name ($email)',
        services: selectedServices,
      );

      if (!mounted) {
        return;
      }

      final eventId = bookingResult['event_id']?.toString() ?? '';
      final eventLink = bookingResult['html_link']?.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            eventId.isNotEmpty
                ? 'Booked! Event ID: $eventId'
                : 'Appointment booked successfully.',
          ),
          action: (eventLink != null && eventLink.isNotEmpty)
              ? SnackBarAction(
                  label: 'Open',
                  onPressed: () async {
                    final uri = Uri.tryParse(eventLink);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                )
              : null,
        ),
      );
      await _loadSlots();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBooking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Appointments',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.role == 'owner')
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Set available time slots'),
              subtitle: Text('Client service choices are saved in the booking description.'),
            ),
          if (widget.role == 'client') ...[
            _buildBookingCard(context),
            const SizedBox(height: 12),
          ],
          const ListTile(
            leading: Icon(Icons.event_available),
            title: Text('Book / manage appointments'),
            subtitle: Text('Create, confirm, cancel, or reschedule'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request your service', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'Select the services you want, then choose the best date and time.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._serviceOptions.map((service) {
              final key = service['key']!;
              final label = service['label']!;
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(label),
                value: _selectedServices.contains(key),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedServices.add(key);
                    } else {
                      _selectedServices.remove(key);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 12),
            Text(
              'Selected services: ${_serviceLabels()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Date: ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}'),
                ),
                OutlinedButton(
                  onPressed: _pickDate,
                  child: const Text('Change date'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingSlots)
              const Center(child: CircularProgressIndicator())
            else if (_availableSlots.isEmpty)
              const Text('No available slots for this date.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSlots.map((slot) {
                  final start = slot['start_time'] as String? ?? '';
                  final end = slot['end_time'] as String? ?? '';
                  final selected = _selectedStartTime == start && _selectedEndTime == end;
                  return ChoiceChip(
                    label: Text('$start - $end'),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedStartTime = start;
                        _selectedEndTime = end;
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Your Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isBooking ? null : _bookSelectedSlot,
                child: _isBooking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Request'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('Calendar', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text(
              'Review the calendar below, then submit the form above to book the selected slot.',
            ),
            const SizedBox(height: 12),
            const GoogleCalendarWidget(calendarSrc: _AppointmentsPageState._calendarUrl, height: 520),
          ],
        ),
      ),
    );
  }
}
