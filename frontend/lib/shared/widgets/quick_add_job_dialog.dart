import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/client_profile_service.dart';
import '../../core/services/estimate_service.dart';
import '../../core/services/scheduled_work_service.dart';
import '../../models/client_profile.dart';
import '../../models/invoice.dart';

/// owner-only dialog: schedule a job directly, with no estimate/approval
/// step — for work that's already agreed with the client (in person, by
/// phone) or approved on the fly. Behind the scenes this still creates a
/// real, already-approved estimate via [EstimateService.createApprovedEstimate]
/// and schedules it the normal way, so invoicing, "View Estimate" links, and
/// reporting all work exactly as they do for a job scheduled from a regular
/// estimate — nothing downstream needs to know this job skipped that step.
///
/// Returns `true` via [Navigator.pop] once the job is created, so callers can
/// show their own confirmation; returns `null`/`false` if cancelled.
class QuickAddJobDialog extends StatefulWidget {
  const QuickAddJobDialog({super.key});

  @override
  State<QuickAddJobDialog> createState() => _QuickAddJobDialogState();
}

class _QuickAddJobDialogState extends State<QuickAddJobDialog> {
  final _clientController = TextEditingController();
  final _serviceController = TextEditingController();
  final _priceController = TextEditingController();

  StreamSubscription<List<ClientProfile>>? _clientsSub;
  List<ClientProfile> _knownClients = const [];
  List<ClientProfile> _clientSuggestions = const [];
  ClientProfile? _selectedClient;
  bool _isLoadingClients = true;

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 1)),
  );

  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clientsSub = ClientProfileService.watchAllProfiles().listen((profiles) {
      if (!mounted) return;
      setState(() {
        _knownClients = profiles;
        _isLoadingClients = false;
      });
    });
  }

  @override
  void dispose() {
    _clientsSub?.cancel();
    _clientController.dispose();
    _serviceController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onClientQueryChanged(String value) {
    if (_selectedClient != null && value.trim() != _selectedClient!.fullName) {
      setState(() => _selectedClient = null);
    }
    setState(() {
      _clientSuggestions = ClientProfileService.searchProfiles(
        profiles: _knownClients.where((profile) => !profile.archived).toList(),
        query: value,
      );
    });
  }

  void _selectClient(ClientProfile profile) {
    setState(() {
      _selectedClient = profile;
      _clientController.text = profile.fullName;
      _clientSuggestions = const [];
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    final client = _selectedClient;
    final serviceName = _serviceController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (client == null) {
      setState(() => _error = 'Select a client from the suggestions.');
      return;
    }
    if (serviceName.isEmpty) {
      setState(() => _error = 'Enter a service.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a price greater than 0.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final scheduledDateTime = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );
      final services = [InvoiceServiceItem(name: serviceName, price: price)];

      final estimateNumber = await EstimateService.consumeNextEstimateNumber();
      final estimateId = await EstimateService.createApprovedEstimate(
        estimateNumber: estimateNumber,
        clientId: client.signupId,
        services: services,
      );
      final workId = await ScheduledWorkService.createScheduledWork(
        estimateId: estimateId,
        estimateNumber: estimateNumber,
        clientId: client.signupId,
        services: services,
        total: price,
        scheduledDate: scheduledDateTime,
        address: client.address,
        phoneNumber: client.phoneNumber,
      );
      await EstimateService.markScheduled(
          estimateId: estimateId, scheduledWorkId: workId);

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to add job: $error';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Add Job'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Already approved / approved on the fly — no estimate review, "
                'it goes straight onto the schedule.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _clientController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Client',
                  hintText: 'Search by name, email, or address',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onClientQueryChanged,
              ),
              if (_isLoadingClients)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                )
              else if (_clientSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _clientSuggestions.length,
                    itemBuilder: (context, index) {
                      final profile = _clientSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(profile.fullName),
                        subtitle: Text(profile.address),
                        onTap: () => _selectClient(profile),
                      );
                    },
                  ),
                ),
              if (_selectedClient != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Selected: ${_selectedClient!.fullName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('MMM d, yyyy').format(_date)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _pickTime,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_time.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _serviceController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Service',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Job'),
        ),
      ],
    );
  }
}
