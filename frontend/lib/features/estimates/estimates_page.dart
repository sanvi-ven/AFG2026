//made with help of chatgpt: create flutter page that shows list of estimates from firestore stream, how to add aprove/deny buttons for client, and convert to invoice button for owner

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/client_profile_service.dart';
import '../../core/services/estimate_pdf_service.dart';
import '../../core/services/estimate_service.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/services/invoice_service.dart';
import '../../core/services/scheduled_work_service.dart';
import '../../core/state/client_session.dart';
import '../../models/client_profile.dart';
import '../../models/estimate.dart';
import '../../models/invoice.dart';
import '../../shared/widgets/app_scaffold.dart';

class EstimatesPage extends StatefulWidget {
  const EstimatesPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<EstimatesPage> createState() => _EstimatesPageState();
}

class _EstimatesPageState extends State<EstimatesPage> {
  final _estimateNumberController = TextEditingController();
  final _clientIdController = TextEditingController();
  final List<_ServiceRow> _serviceRows = [
    _ServiceRow(nameController: TextEditingController(), priceController: TextEditingController()),
  ];
  bool _isSubmitting = false;
  String? _convertingEstimateId;
  String? _downloadingEstimateId;
  String? _schedulingEstimateId;
  String? _downloadingEstimatePdfId;
  Timer? _clientSearchDebounce;
  StreamSubscription<List<ClientProfile>>? _clientsSub;
  List<ClientProfile> _knownClients = const [];
  List<ClientProfile> _clientSuggestions = const [];
  ClientProfile? _selectedClient;
  bool _isLoadingClientSuggestions = true;

  @override
  void initState() {
    super.initState();
    _clientsSub = ClientProfileService.watchAllProfiles().listen((profiles) {
      if (!mounted) {
        return;
      }

      final selectedId = _selectedClient?.signupId;
      final query = _clientIdController.text.trim();
      setState(() {
        _knownClients = profiles;
        _isLoadingClientSuggestions = false;

        if (selectedId != null &&
            !profiles.any((profile) => profile.signupId == selectedId)) {
          _selectedClient = null;
        }

        _clientSuggestions = ClientProfileService.searchProfiles(
          profiles: profiles,
          query: query,
          limit: 8,
        );
      });
    });
  }

  @override
  void dispose() {
    _clientSearchDebounce?.cancel();
    _clientsSub?.cancel();
    _estimateNumberController.dispose();
    _clientIdController.dispose();
    for (final row in _serviceRows) {
      row.nameController.dispose();
      row.priceController.dispose();
    }
    super.dispose();
  }

  String _defaultEstimateNumber() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'EST-${ts.substring(ts.length - 6)}';
  }

  String _defaultInvoiceNumber() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'INV-${ts.substring(ts.length - 6)}';
  }

  void _addServiceRow() {
    setState(() {
      _serviceRows.add(
        _ServiceRow(nameController: TextEditingController(), priceController: TextEditingController()),
      );
    });
  }

  void _removeServiceRow(int index) {
    if (_serviceRows.length == 1) {
      return;
    }
    setState(() {
      final row = _serviceRows.removeAt(index);
      row.nameController.dispose();
      row.priceController.dispose();
    });
  }

  void _onClientSearchChanged(String value) {
    _clientSearchDebounce?.cancel();

    if (_selectedClient != null && value.trim() != _selectedClient!.signupId) {
      setState(() {
        _selectedClient = null;
      });
    }

    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _clientSuggestions = const [];
      });
      return;
    }

    _clientSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _clientSuggestions = ClientProfileService.searchProfiles(
          profiles: _knownClients,
          query: query,
          limit: 8,
        );
      });
    });
  }

  void _pickClientSuggestion(ClientProfile profile) {
    _clientIdController.text = profile.signupId;
    setState(() {
      _selectedClient = profile;
      _clientSuggestions = const [];
    });
  }

  Future<void> _submitEstimate() async {
    final estimateNumber = _estimateNumberController.text.trim().isEmpty
        ? _defaultEstimateNumber()
        : _estimateNumberController.text.trim();
    final clientId = _clientIdController.text.trim();

    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client ID is required.')),
      );
      return;
    }

    final services = <InvoiceServiceItem>[];
    for (final row in _serviceRows) {
      final name = row.nameController.text.trim();
      final price = double.tryParse(row.priceController.text.trim());
      if (name.isEmpty || price == null || price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Each service needs a name and price greater than 0.')),
        );
        return;
      }
      services.add(InvoiceServiceItem(name: name, price: price));
    }

    setState(() => _isSubmitting = true);
    try {
      final existingClient = await ClientProfileService.fetchBySignupId(clientId);
      if (existingClient == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select a valid client from suggestions.')),
          );
        }
        return;
      }

      await EstimateService.createEstimate(
        estimateNumber: estimateNumber,
        clientId: clientId,
        services: services,
      );
      if (!mounted) {
        return;
      }

      _estimateNumberController.clear();
      _clientIdController.clear();
      for (final row in _serviceRows) {
        row.nameController.clear();
        row.priceController.clear();
      }
      setState(() {
        _selectedClient = null;
        _clientSuggestions = const [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate sent to client.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create estimate: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _downloadEstimatePdf(Estimate estimate) async {
    setState(() => _downloadingEstimatePdfId = estimate.id);
    try {
      final savedPath = await EstimatePdfService.generateAndDownloadEstimatePdf(estimate: estimate);
      if (!mounted) return;
      final message = savedPath == null ? 'Estimate PDF downloaded.' : 'Estimate PDF saved: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download estimate PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingEstimatePdfId = null);
    }
  }

  Future<void> _scheduleWork(Estimate estimate) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (pickedTime == null || !mounted) return;

    final scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() => _schedulingEstimateId = estimate.id);
    try {
      final workId = await ScheduledWorkService.createScheduledWork(
        estimateId: estimate.id,
        estimateNumber: estimate.estimateNumber,
        clientId: estimate.clientId,
        services: estimate.services,
        total: estimate.total,
        scheduledDate: scheduledDateTime,
      );
      await EstimateService.markScheduled(estimateId: estimate.id, scheduledWorkId: workId);
      if (!mounted) return;
      final formatted = DateFormat('MMM d, yyyy · h:mm a').format(scheduledDateTime);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Work scheduled for $formatted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to schedule work: $error')),
      );
    } finally {
      if (mounted) setState(() => _schedulingEstimateId = null);
    }
  }

  Future<void> _setEstimateStatus(String estimateId, String status) async {
    try {
      await EstimateService.updateStatus(estimateId: estimateId, status: status);
      if (!mounted) {
        return;
      }
      final normalizedStatus = status.trim().toLowerCase();
      final displayStatus = normalizedStatus.isEmpty
          ? 'Pending'
          : '${normalizedStatus[0].toUpperCase()}${normalizedStatus.substring(1)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estimate status set to $displayStatus.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update estimate status: $error')),
      );
    }
  }

  Future<void> _convertToInvoice(Estimate estimate) async {
    if (!estimate.isConvertible) {
      return;
    }

    setState(() => _convertingEstimateId = estimate.id);
    try {
      final invoiceId = await InvoiceService.createInvoiceFromEstimate(
        invoiceNumber: _defaultInvoiceNumber(),
        clientId: estimate.clientId,
        services: estimate.services,
        sourceEstimateId: estimate.id,
      );
      await EstimateService.markConverted(estimateId: estimate.id, invoiceId: invoiceId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${estimate.estimateNumber} converted to invoice and sent to client.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to convert estimate: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _convertingEstimateId = null);
      }
    }
  }

  Future<void> _downloadConvertedInvoicePdf(Estimate estimate) async {
    final invoiceId = estimate.convertedInvoiceId?.trim() ?? '';
    if (invoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No converted invoice found for this estimate.')),
      );
      return;
    }

    setState(() => _downloadingEstimateId = estimate.id);
    try {
      final invoice = await InvoiceService.getInvoiceById(invoiceId);
      if (invoice == null) {
        throw Exception('Converted invoice not found.');
      }

      final savedPath = await InvoicePdfService.generateAndDownloadInvoicePdf(invoice: invoice);
      if (!mounted) {
        return;
      }

      final message = savedPath == null
          ? 'Invoice PDF downloaded.'
          : 'Invoice PDF saved: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download invoice PDF: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingEstimateId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: 'Estimates',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/estimates',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (widget.role == 'owner') ...[
            _OwnerEstimateForm(
              estimateNumberController: _estimateNumberController,
              clientIdController: _clientIdController,
              selectedClient: _selectedClient,
              isLoadingClientSuggestions: _isLoadingClientSuggestions,
              clientSuggestions: _clientSuggestions,
              onClientIdChanged: _onClientSearchChanged,
              onClientSuggestionSelected: _pickClientSuggestion,
              serviceRows: _serviceRows,
              isSubmitting: _isSubmitting,
              onAddService: _addServiceRow,
              onRemoveService: _removeServiceRow,
              onSubmit: _submitEstimate,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.role == 'client' && (clientId == null || clientId.trim().isEmpty))
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Client ID not found. Please log in from the client email flow first.'),
              ),
            )
          else
            StreamBuilder<List<Estimate>>(
              stream: EstimateService.watchEstimates(role: widget.role, clientId: clientId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load estimates: ${snapshot.error}'),
                    ),
                  );
                }

                final estimates = snapshot.data ?? const <Estimate>[];
                if (estimates.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.role == 'owner'
                          ? 'No estimates yet. Create one above.'
                          : 'No estimates available for your client ID yet.'),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final estimate in estimates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EstimateCard(
                          estimate: estimate,
                          role: widget.role,
                          isConverting: _convertingEstimateId == estimate.id,
                          isDownloadingPdf: _downloadingEstimateId == estimate.id,
                          isScheduling: _schedulingEstimateId == estimate.id,
                          isDownloadingEstimatePdf: _downloadingEstimatePdfId == estimate.id,
                          onApprove: () => _setEstimateStatus(estimate.id, InvoiceStatus.approved),
                          onDeny: () => _setEstimateStatus(estimate.id, InvoiceStatus.denied),
                          onConvert: () => _convertToInvoice(estimate),
                          onDownloadPdf: () => _downloadConvertedInvoicePdf(estimate),
                          onScheduleWork: () => _scheduleWork(estimate),
                          onDownloadEstimatePdf: () => _downloadEstimatePdf(estimate),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _OwnerEstimateForm extends StatelessWidget {
  const _OwnerEstimateForm({
    required this.estimateNumberController,
    required this.clientIdController,
    required this.selectedClient,
    required this.isLoadingClientSuggestions,
    required this.clientSuggestions,
    required this.onClientIdChanged,
    required this.onClientSuggestionSelected,
    required this.serviceRows,
    required this.isSubmitting,
    required this.onAddService,
    required this.onRemoveService,
    required this.onSubmit,
  });

  final TextEditingController estimateNumberController;
  final TextEditingController clientIdController;
  final ClientProfile? selectedClient;
  final bool isLoadingClientSuggestions;
  final List<ClientProfile> clientSuggestions;
  final ValueChanged<String> onClientIdChanged;
  final ValueChanged<ClientProfile> onClientSuggestionSelected;
  final List<_ServiceRow> serviceRows;
  final bool isSubmitting;
  final VoidCallback onAddService;
  final void Function(int index) onRemoveService;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create Estimate', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: estimateNumberController,
              decoration: const InputDecoration(
                labelText: 'Estimate number (optional)',
                border: OutlineInputBorder(),
                hintText: 'EST-123456',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: clientIdController,
              decoration: InputDecoration(
                labelText: 'Client (ID, name, or address)',
                border: const OutlineInputBorder(),
                suffixIcon: isLoadingClientSuggestions
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: onClientIdChanged,
            ),
            if (selectedClient != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${selectedClient!.signupId} · ${selectedClient!.fullName}\n${selectedClient!.address.isEmpty ? 'Address unavailable' : selectedClient!.address}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (clientSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: clientSuggestions.length,
                    itemBuilder: (context, index) {
                      final client = clientSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text('${client.signupId} · ${client.fullName}'),
                        subtitle: Text(
                          client.address.isEmpty ? 'Address unavailable' : client.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onClientSuggestionSelected(client),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (var i = 0; i < serviceRows.length; i++) ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: serviceRows[i].nameController,
                      decoration: const InputDecoration(
                        labelText: 'Service name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: serviceRows[i].priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onRemoveService(i),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                TextButton.icon(
                  onPressed: onAddService,
                  icon: const Icon(Icons.add),
                  label: const Text('Add service'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Estimate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.estimate,
    required this.role,
    required this.isConverting,
    required this.isDownloadingPdf,
    required this.isScheduling,
    required this.isDownloadingEstimatePdf,
    required this.onApprove,
    required this.onDeny,
    required this.onConvert,
    required this.onDownloadPdf,
    required this.onScheduleWork,
    required this.onDownloadEstimatePdf,
  });

  final Estimate estimate;
  final String role;
  final bool isConverting;
  final bool isDownloadingPdf;
  final bool isScheduling;
  final bool isDownloadingEstimatePdf;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onConvert;
  final VoidCallback onDownloadPdf;
  final VoidCallback onScheduleWork;
  final VoidCallback onDownloadEstimatePdf;

  @override
  Widget build(BuildContext context) {
    final statusKey = estimate.status.trim().toLowerCase();
    final statusColor = switch (statusKey) {
      InvoiceStatus.approved => Colors.green,
      InvoiceStatus.denied => Colors.red,
      _ => Colors.orange,
    };
    final statusText = switch (statusKey) {
      InvoiceStatus.approved => 'Approved',
      InvoiceStatus.denied => 'Denied',
      InvoiceStatus.pending => 'Pending',
      _ => statusKey.isEmpty
          ? 'Pending'
          : '${statusKey[0].toUpperCase()}${statusKey.substring(1)}',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    estimate.estimateNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Client ID: ${estimate.clientId}'),
            const SizedBox(height: 10),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in estimate.services)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(item.name)),
                    Text('\$${item.price.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('\$${estimate.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if (role == 'client' && estimate.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDeny,
                      icon: const Icon(Icons.close),
                      label: const Text('Deny'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
            if (role == 'owner') ...[
              const SizedBox(height: 12),
              if (estimate.convertedToInvoice)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Converted to invoice${estimate.convertedInvoiceId == null ? '' : ': ${estimate.convertedInvoiceId}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: isDownloadingPdf ? null : onDownloadPdf,
                      icon: isDownloadingPdf
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_outlined),
                      label: const Text('Download Invoice PDF'),
                    ),
                  ],
                )
              else ...[
                if (estimate.isApproved) ...[
                  if (estimate.isScheduled)
                    Row(
                      children: [
                        const Icon(Icons.event_available, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          'Work scheduled — see Appointments',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isDownloadingEstimatePdf ? null : onDownloadEstimatePdf,
                          icon: isDownloadingEstimatePdf
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_outlined),
                          label: const Text('Download'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: isScheduling ? null : onScheduleWork,
                          icon: isScheduling
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.event_outlined),
                          label: const Text('Schedule Work'),
                        ),
                      ],
                    ),
                ] else
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Approval Required'),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceRow {
  _ServiceRow({required this.nameController, required this.priceController});

  final TextEditingController nameController;
  final TextEditingController priceController;
}
