import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../data/calendar_booking_repository.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_widget.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({required this.role, super.key});

  final String role;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  late final CalendarBookingRepository _repository;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _availableSlots = const [];
  bool _isLoadingSlots = false;
  bool _isBooking = false;
  String? _selectedStartTime;
  String? _selectedEndTime;
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
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name and email.')),
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
          description: 'Booked via Small Biz Manager. Client: $name ($email)',
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
    const calendarUrl =
        'https://calendar.google.com/calendar/embed?height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=0&showCalendars=0&showTz=0&src=91d01c09dd4283d77beb10f68e45025941f605469166cfef41609db2a78932bd%40group.calendar.google.com&color=%23039BE5';

    return AppScaffold(
      title: 'Appointments',
      role: widget.role,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.role == 'owner')
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Set available time slots'),
              subtitle: Text('Define working hours and open slots'),
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
          const Card(
            child: ListTile(
              leading: Icon(Icons.calendar_month_outlined),
              title: Text('Bookings Calendar'),
              subtitle: Text('Live Google Calendar view for both owner and client.'),
            ),
          ),
          const SizedBox(height: 12),
          const GoogleCalendarWidget(calendarSrc: calendarUrl, height: 520),
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
            Text('Book from Google Calendar slots', style: Theme.of(context).textTheme.titleMedium),
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
                    : const Text('Book Slot'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
