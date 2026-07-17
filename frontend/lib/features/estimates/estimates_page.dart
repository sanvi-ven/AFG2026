//made with help of chatgpt 4.0: create flutter page that shows list of estimates from firestore stream, how to add aprove/deny buttons for client, and convert to invoice button for owner

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/services/checklist_template_service.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/services/estimate_pdf_service.dart';
import '../../core/services/estimate_service.dart';
import '../../core/services/invoice_pdf_service.dart';
import '../../core/services/invoice_service.dart';
import '../../core/services/request_service.dart';
import '../../core/services/scheduled_work_service.dart';
import '../../core/services/service_catalog_service.dart';
import '../../core/state/client_session.dart';
import '../../models/checklist_template.dart';
import '../../models/client_profile.dart';
import '../../models/common_service.dart';
import '../../models/estimate.dart';
import '../../models/invoice.dart';
import '../../shared/utils/list_highlight_controller.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/sort_control.dart';
import '../clients/presentation/quick_add_client_dialog.dart';

/// page for viewing and managing estimates with client approval and owner conversion flows
class EstimatesPage extends StatefulWidget {
  const EstimatesPage({
    required this.role,
    this.authToken,
    this.highlightId,
    this.initialClientId,
    this.initialNotes,
    this.convertRequestId,
    super.key,
  });

  final String role;
  final String? authToken;
  final String? highlightId;
  /// pre-select this client and pre-fill notes when arriving from a
  /// converted Request (see RequestsPage) — null for the normal create flow
  final String? initialClientId;
  final String? initialNotes;
  /// when set, the created estimate is linked back to this Request via
  /// RequestService.markConverted once submitted
  final String? convertRequestId;

  @override
  State<EstimatesPage> createState() => _EstimatesPageState();
}

class _EstimatesPageState extends State<EstimatesPage> {
  final _estimateNumberController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _notesController = TextEditingController();
  final _termsController = TextEditingController();
  final List<_ServiceRowController> _serviceRows = [_ServiceRowController()];
  StreamSubscription<List<CommonService>>? _catalogSub;
  List<CommonService> _knownCatalog = const [];
  bool _isSubmitting = false;
  String? _convertingEstimateId;
  String? _downloadingEstimateId;
  String? _schedulingEstimateId;
  String? _downloadingEstimatePdfId;
  String? _requestingChangesEstimateId;
  String? _revisingEstimateId;
  String? _archivingEstimateId;
  String? _deletingEstimateId;
  Timer? _clientSearchDebounce;
  StreamSubscription<List<ClientProfile>>? _clientsSub;
  List<ClientProfile> _knownClients = const [];
  List<ClientProfile> _clientSuggestions = const [];
  ClientProfile? _selectedClient;
  bool _isLoadingClientSuggestions = true;
  ListSortMode _sortMode = ListSortMode.newestFirst;
  late final ListHighlightController _highlight = ListHighlightController(widget.highlightId);
  bool _appliedInitialClient = false;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'owner') {
      EstimateService.peekNextEstimateNumber().then((preview) {
        if (mounted && _estimateNumberController.text.trim().isEmpty) {
          setState(() => _estimateNumberController.text = preview);
        }
      });
    }
    if (widget.initialNotes != null) {
      _notesController.text = widget.initialNotes!;
    }
    if (widget.initialClientId != null) {
      _clientIdController.text = widget.initialClientId!;
    }
    _catalogSub = ServiceCatalogService.watchAllServices().listen((services) {
      if (!mounted) return;
      setState(() => _knownCatalog = services);
    });
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
          profiles: profiles.where((profile) => !profile.archived).toList(),
          query: query,
          limit: 8,
        );

        if (!_appliedInitialClient && widget.initialClientId != null) {
          _appliedInitialClient = true;
          final match = profiles.where((profile) => profile.signupId == widget.initialClientId).toList();
          if (match.isNotEmpty) {
            _selectedClient = match.first;
            _clientSuggestions = const [];
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _clientSearchDebounce?.cancel();
    _clientsSub?.cancel();
    _catalogSub?.cancel();
    _estimateNumberController.dispose();
    _clientIdController.dispose();
    _notesController.dispose();
    _termsController.dispose();
    for (final row in _serviceRows) {
      row.dispose();
    }
    super.dispose();
  }

///https://api.flutter.dev/flutter/widgets/TextEditingController-class.html
  void _addServiceRow() {
    setState(() {
      _serviceRows.add(_ServiceRowController());
    });
  }

  void _removeServiceRow(int index) {
    if (_serviceRows.length == 1) {
      return;
    }
    setState(() {
      final row = _serviceRows.removeAt(index);
      row.dispose();
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
          profiles: _knownClients.where((profile) => !profile.archived).toList(),
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

  Future<void> _openQuickAddClient() async {
    final profile = await showQuickAddClientDialog(context);
    if (profile == null || !mounted) return;
    _clientIdController.text = profile.signupId;
    setState(() {
      _selectedClient = profile;
      _clientSuggestions = const [];
    });
  }

  void _viewInAppointments(Estimate estimate) {
    final workId = estimate.scheduledWorkId;
    if (workId == null || workId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppRouter.appointments,
      arguments: {'role': widget.role, 'authToken': widget.authToken, 'highlightId': workId},
    );
  }

  Future<void> _approveByOwner(Estimate estimate) async {
    final result = await showDialog<_OwnerApprovalResult>(
      context: context,
      builder: (_) => const _OwnerApprovalDialog(),
    );
    if (result == null) return;

    try {
      await EstimateService.approveByOwner(
        estimateId: estimate.id,
        method: result.method,
        note: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate approved on the client\'s behalf.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve estimate: $error')),
      );
    }
  }

  Future<void> _submitEstimate() async {
    final clientId = _clientIdController.text.trim();

    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client ID is required.')),
      );
      return;
    }

    final services = <InvoiceServiceItem>[];
    for (final row in _serviceRows) {
      final item = row.toServiceItem();
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Each service needs a name and price greater than 0.')),
        );
        return;
      }
      services.add(item);
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

      // Always advance the counter once per estimate created, regardless of
      // whether the owner overrode the suggested number below.
      final consumedNumber = await EstimateService.consumeNextEstimateNumber();
      final estimateNumber = _estimateNumberController.text.trim().isEmpty
          ? consumedNumber
          : _estimateNumberController.text.trim();

      final newEstimateId = await EstimateService.createEstimate(
        estimateNumber: estimateNumber,
        clientId: clientId,
        services: services,
        notes: _notesController.text.trim(),
        terms: _termsController.text.trim(),
      );
      if (widget.convertRequestId != null) {
        await RequestService.markConverted(requestId: widget.convertRequestId!, estimateId: newEstimateId);
      }
      if (!mounted) {
        return;
      }

      final nextPreview = await EstimateService.peekNextEstimateNumber();
      _clientIdController.clear();
      _notesController.clear();
      _termsController.clear();
      for (final row in _serviceRows) {
        row.dispose();
      }
      _serviceRows
        ..clear()
        ..add(_ServiceRowController());
      if (!mounted) {
        return;
      }
      setState(() {
        _estimateNumberController.text = nextPreview;
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

  Future<void> _requestEstimateChanges(Estimate estimate) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _RequestEstimateChangesDialog(),
    );
    if (message == null) {
      return;
    }

    setState(() => _requestingChangesEstimateId = estimate.id);
    try {
      await EstimateService.requestChanges(
        estimateId: estimate.id,
        message: message,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change request sent to owner.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request changes: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _requestingChangesEstimateId = null);
      }
    }
  }

  Future<void> _reviseAndResendEstimate(Estimate estimate) async {
    final revisedServices = await showDialog<List<InvoiceServiceItem>>(
      context: context,
      builder: (_) => _ReviseEstimateDialog(
        estimateNumber: estimate.estimateNumber,
        currentVersion: estimate.revisionNumber,
        initialServices: estimate.services,
      ),
    );
    if (revisedServices == null) {
      return;
    }

    setState(() => _revisingEstimateId = estimate.id);
    try {
      await EstimateService.reviseAndResendEstimate(
        estimate: estimate,
        services: revisedServices,
      );
      if (!mounted) {
        return;
      }
      final nextVersion = estimate.revisionNumber + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estimate revised to v$nextVersion and re-sent to client.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to revise estimate: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _revisingEstimateId = null);
      }
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

    final recurrence = await showDialog<_RecurrenceChoice>(
      context: context,
      builder: (_) => const _RecurrenceDialog(),
    );
    if (recurrence == null || !mounted) return;

    final checklistTemplate = await showDialog<ChecklistTemplate>(
      context: context,
      builder: (_) => const _ChecklistTemplatePickerDialog(),
    );
    if (!mounted) return;
    final checklistItems = checklistTemplate == null
        ? const <ChecklistItem>[]
        : checklistTemplate.items.map((label) => ChecklistItem(label: label)).toList();

    setState(() => _schedulingEstimateId = estimate.id);
    try {
      // Denormalize the client's address/phone onto the job record so employee
      // screens never need read access to the client_signups collection.
      final client = await ClientProfileService.fetchBySignupId(estimate.clientId);
      final address = client?.address ?? '';
      final phoneNumber = client?.phoneNumber ?? '';

      if (recurrence.cadence == _RecurrenceCadence.none) {
        final workId = await ScheduledWorkService.createScheduledWork(
          estimateId: estimate.id,
          estimateNumber: estimate.estimateNumber,
          clientId: estimate.clientId,
          services: estimate.services,
          total: estimate.total,
          scheduledDate: scheduledDateTime,
          address: address,
          phoneNumber: phoneNumber,
          checklistItems: checklistItems,
        );
        await EstimateService.markScheduled(estimateId: estimate.id, scheduledWorkId: workId);
      } else {
        final groupId = ScheduledWorkService.newRecurringGroupId();
        for (var n = 0; n < recurrence.occurrences; n++) {
          final occurrenceDate = recurrence.cadence == _RecurrenceCadence.monthly
              ? DateTime(
                  scheduledDateTime.year,
                  scheduledDateTime.month + n,
                  scheduledDateTime.day,
                  scheduledDateTime.hour,
                  scheduledDateTime.minute,
                )
              : scheduledDateTime.add(Duration(days: recurrence.cadenceDays! * n));

          final workId = await ScheduledWorkService.createScheduledWork(
            estimateId: estimate.id,
            estimateNumber: estimate.estimateNumber,
            clientId: estimate.clientId,
            services: estimate.services,
            total: estimate.total,
            scheduledDate: occurrenceDate,
            address: address,
            phoneNumber: phoneNumber,
            recurringGroupId: groupId,
            checklistItems: checklistItems,
          );
          if (n == 0) {
            await EstimateService.markScheduled(estimateId: estimate.id, scheduledWorkId: workId);
          }
        }
      }

      if (!mounted) return;
      final formatted = DateFormat('MMM d, yyyy · h:mm a').format(scheduledDateTime);
      final message = recurrence.cadence == _RecurrenceCadence.none
          ? 'Work scheduled for $formatted.'
          : '${recurrence.occurrences} jobs scheduled starting $formatted.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _archiveEstimate(Estimate estimate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Estimate'),
        content: Text(
          'Archive ${estimate.estimateNumber}? It will be removed from the client\'s view and moved to your archived section.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _archivingEstimateId = estimate.id);
    try {
      await EstimateService.archiveEstimate(estimate.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${estimate.estimateNumber} archived.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to archive estimate: $error')),
      );
    } finally {
      if (mounted) setState(() => _archivingEstimateId = null);
    }
  }

  Future<void> _deleteEstimatePermanently(Estimate estimate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Estimate Permanently'),
        content: Text("Permanently delete ${estimate.estimateNumber}? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingEstimateId = estimate.id);
    try {
      await EstimateService.deleteEstimatePermanently(estimate.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingEstimateId = null);
    }
  }

  Future<void> _convertToInvoice(Estimate estimate) async {
    if (!estimate.isConvertible) {
      return;
    }

    setState(() => _convertingEstimateId = estimate.id);
    try {
      final invoiceId = await InvoiceService.createInvoiceFromEstimate(
        invoiceNumber: estimate.estimateNumber,
        clientId: estimate.clientId,
        services: estimate.services,
        sourceEstimateId: estimate.id,
        notes: estimate.notes,
        terms: estimate.terms,
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
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRouter.serviceCatalog,
                      arguments: {'role': widget.role, 'authToken': widget.authToken},
                    ),
                    icon: const Icon(Icons.list_alt_outlined),
                    label: const Text('Manage Common Services'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRouter.checklistTemplates,
                      arguments: {'role': widget.role, 'authToken': widget.authToken},
                    ),
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('Manage Checklist Templates'),
                  ),
                ],
              ),
            ),
            _OwnerEstimateForm(
              estimateNumberController: _estimateNumberController,
              clientIdController: _clientIdController,
              selectedClient: _selectedClient,
              isLoadingClientSuggestions: _isLoadingClientSuggestions,
              clientSuggestions: _clientSuggestions,
              onClientIdChanged: _onClientSearchChanged,
              onClientSuggestionSelected: _pickClientSuggestion,
              onCreateClient: _openQuickAddClient,
              serviceRows: _serviceRows,
              catalog: _knownCatalog,
              notesController: _notesController,
              termsController: _termsController,
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

                final allEstimates = snapshot.data ?? const <Estimate>[];
                var estimates = allEstimates.where((e) => !e.isArchived).toList();
                var archived = allEstimates.where((e) => e.isArchived).toList();

                void applySort(List<Estimate> list) {
                  switch (_sortMode) {
                    case ListSortMode.newestFirst:
                      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      break;
                    case ListSortMode.oldestFirst:
                      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                      break;
                    case ListSortMode.client:
                      list.sort((a, b) => ClientProfileService.displayNameFor(_knownClients, a.clientId)
                          .toLowerCase()
                          .compareTo(ClientProfileService.displayNameFor(_knownClients, b.clientId).toLowerCase()));
                      break;
                  }
                }

                applySort(estimates);
                applySort(archived);

                _highlight.maybeScrollTo(
                  allEstimates.map((e) => e.id).toList(),
                  () {
                    if (mounted) setState(() {});
                  },
                );

                if (estimates.isEmpty && archived.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.role == 'owner'
                          ? 'No estimates yet. Create one above.'
                          : 'No estimates available for your client ID yet.'),
                    ),
                  );
                }

                Widget estimateCard(Estimate estimate) => KeyedSubtree(
                      key: _highlight.keyFor(estimate.id),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EstimateCard(
                          estimate: estimate,
                          role: widget.role,
                          isHighlighted: _highlight.isHighlighted(estimate.id),
                          isConverting: _convertingEstimateId == estimate.id,
                          isDownloadingPdf: _downloadingEstimateId == estimate.id,
                          isScheduling: _schedulingEstimateId == estimate.id,
                          isDownloadingEstimatePdf: _downloadingEstimatePdfId == estimate.id,
                          isRequestingChanges: _requestingChangesEstimateId == estimate.id,
                          isRevising: _revisingEstimateId == estimate.id,
                          isArchiving: _archivingEstimateId == estimate.id,
                          isDeleting: _deletingEstimateId == estimate.id,
                          onApprove: () => _setEstimateStatus(estimate.id, InvoiceStatus.approved),
                          onRequestChanges: () => _requestEstimateChanges(estimate),
                          onConvert: () => _convertToInvoice(estimate),
                          onDownloadPdf: () => _downloadConvertedInvoicePdf(estimate),
                          onScheduleWork: () => _scheduleWork(estimate),
                          onDownloadEstimatePdf: () => _downloadEstimatePdf(estimate),
                          onReviseAndResend: () => _reviseAndResendEstimate(estimate),
                          onArchive: widget.role == 'owner' ? () => _archiveEstimate(estimate) : null,
                          onDeletePermanently:
                              widget.role == 'owner' ? () => _deleteEstimatePermanently(estimate) : null,
                          onViewInAppointments: () => _viewInAppointments(estimate),
                          onOwnerApprove: () => _approveByOwner(estimate),
                        ),
                      ),
                    );

                return Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SortControl(
                        value: _sortMode,
                        onChanged: (mode) => setState(() => _sortMode = mode),
                      ),
                    ),
                    for (final estimate in estimates) estimateCard(estimate),
                    if (widget.role == 'owner' && archived.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ExpansionTile(
                        title: Text(
                          'Archived (${archived.length})',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          for (final estimate in archived) estimateCard(estimate),
                        ],
                      ),
                    ],
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
    required this.onCreateClient,
    required this.serviceRows,
    required this.catalog,
    required this.notesController,
    required this.termsController,
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
  final VoidCallback onCreateClient;
  final List<_ServiceRowController> serviceRows;
  final List<CommonService> catalog;
  final TextEditingController notesController;
  final TextEditingController termsController;
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
                labelText: 'Estimate number',
                border: OutlineInputBorder(),
                hintText: 'EST-0001',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
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
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onCreateClient,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('New Client'),
                ),
              ],
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
            for (var i = 0; i < serviceRows.length; i++)
              _ServiceRowEditor(
                key: ObjectKey(serviceRows[i]),
                row: serviceRows[i],
                onRemove: () => onRemoveService(i),
                catalog: catalog,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddService,
                icon: const Icon(Icons.add),
                label: const Text('Add service'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: termsController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Terms (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isSubmitting ? null : onSubmit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Estimate'),
              ),
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
    required this.isHighlighted,
    required this.isConverting,
    required this.isDownloadingPdf,
    required this.isScheduling,
    required this.isDownloadingEstimatePdf,
    required this.isRequestingChanges,
    required this.isRevising,
    required this.onApprove,
    required this.onRequestChanges,
    required this.onConvert,
    required this.onDownloadPdf,
    required this.onScheduleWork,
    required this.onDownloadEstimatePdf,
    required this.onReviseAndResend,
    required this.onViewInAppointments,
    required this.onOwnerApprove,
    required this.isArchiving,
    required this.isDeleting,
    this.onArchive,
    this.onDeletePermanently,
  });

  final Estimate estimate;
  final String role;
  final bool isHighlighted;
  final bool isConverting;
  final bool isDownloadingPdf;
  final bool isScheduling;
  final bool isDownloadingEstimatePdf;
  final bool isRequestingChanges;
  final bool isRevising;
  final bool isArchiving;
  final bool isDeleting;
  final VoidCallback onApprove;
  final VoidCallback onRequestChanges;
  final VoidCallback onConvert;
  final VoidCallback onDownloadPdf;
  final VoidCallback onScheduleWork;
  final VoidCallback onDownloadEstimatePdf;
  final VoidCallback onReviseAndResend;
  final VoidCallback onViewInAppointments;
  final VoidCallback onOwnerApprove;
  final VoidCallback? onArchive;
  final VoidCallback? onDeletePermanently;

  String _displayStatus(String status) {
    final statusKey = status.trim().toLowerCase();
    if (statusKey.isEmpty) {
      return 'Pending';
    }
    return statusKey[0].toUpperCase() + statusKey.substring(1).replaceAll('_', ' ');
  }

  Widget _versionColumn(
    BuildContext context, {
    required String title,
    required List<InvoiceServiceItem> services,
    required double total,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Status: ${_displayStatus(status)}'),
          const SizedBox(height: 6),
          for (final item in services)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('\$${item.price.toStringAsFixed(2)}'),
                ],
              ),
            ),
          const Divider(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusKey = estimate.status.trim().toLowerCase();
    final statusColor = switch (statusKey) {
      InvoiceStatus.approved => Colors.green,
      InvoiceStatus.denied => Colors.red,
      InvoiceStatus.changesRequested => Colors.deepOrange,
      _ => Colors.orange,
    };
    final statusText = switch (statusKey) {
      InvoiceStatus.approved => 'Approved',
      InvoiceStatus.denied => 'Denied',
      InvoiceStatus.changesRequested => 'Changes requested',
      InvoiceStatus.pending => 'Pending',
      _ => statusKey.isEmpty
          ? 'Pending'
          : '${statusKey[0].toUpperCase()}${statusKey.substring(1)}',
    };

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Card(
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
                if (!estimate.isArchived && onArchive != null) ...[
                  const SizedBox(width: 4),
                  isArchiving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: onArchive,
                          icon: const Icon(Icons.archive_outlined),
                          tooltip: 'Archive estimate',
                          color: Theme.of(context).colorScheme.outline,
                          iconSize: 20,
                        ),
                ] else if (estimate.isArchived && onDeletePermanently != null) ...[
                  const SizedBox(width: 4),
                  isDeleting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: onDeletePermanently,
                          icon: const Icon(Icons.delete_forever_outlined),
                          tooltip: 'Delete permanently',
                          color: Theme.of(context).colorScheme.error,
                          iconSize: 20,
                        ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text('Client ID: ${estimate.clientId}'),
            if (estimate.revisionNumber > 1) ...[
              const SizedBox(height: 4),
              Text(
                'Revision: v${estimate.revisionNumber}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (estimate.changeRequestMessage != null && estimate.changeRequestMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Client requested changes: ${estimate.changeRequestMessage!}'),
              ),
            ],
            if (estimate.approvedByOwner) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Approved by owner — confirmed via ${estimate.ownerApprovalMethod ?? 'phone/text'}'
                  '${(estimate.ownerApprovalNote?.isNotEmpty ?? false) ? ': ${estimate.ownerApprovalNote}' : ''}',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in estimate.services)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(item.name)),
                        Text('\$${item.price.toStringAsFixed(2)}'),
                      ],
                    ),
                    if (item.description.isNotEmpty)
                      Text(item.description, style: Theme.of(context).textTheme.bodySmall),
                    if (item.isPerUnit)
                      Text(
                        '${item.quantity} ${item.unit?.isEmpty ?? true ? 'unit(s)' : item.unit} × \$${item.unitPrice!.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
            if (estimate.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Notes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(estimate.notes),
            ],
            if (estimate.terms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Terms', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(estimate.terms),
            ],
            if (estimate.originalVersion != null && estimate.revisionNumber > 1) ...[
              const SizedBox(height: 12),
              Text('Compare revisions', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final oldVersion = estimate.originalVersion!;
                  final oldTitle = 'v${oldVersion.version} (original)';
                  final newTitle = 'v${estimate.revisionNumber} (current)';
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        _versionColumn(
                          context,
                          title: oldTitle,
                          services: oldVersion.services,
                          total: oldVersion.total,
                          status: oldVersion.status,
                        ),
                        const SizedBox(height: 10),
                        _versionColumn(
                          context,
                          title: newTitle,
                          services: estimate.services,
                          total: estimate.total,
                          status: estimate.status,
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _versionColumn(
                          context,
                          title: oldTitle,
                          services: oldVersion.services,
                          total: oldVersion.total,
                          status: oldVersion.status,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _versionColumn(
                          context,
                          title: newTitle,
                          services: estimate.services,
                          total: estimate.total,
                          status: estimate.status,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            if (role == 'client' && estimate.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isRequestingChanges ? null : onRequestChanges,
                      icon: isRequestingChanges
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.edit_note_outlined),
                      label: const Text('Request Changes'),
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
            if (role == 'client' && estimate.isChangesRequested) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.schedule, size: 16),
                  SizedBox(width: 6),
                  Expanded(child: Text('Change request sent. Waiting for revised estimate from owner.')),
                ],
              ),
            ],
            if (role == 'owner') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isDownloadingEstimatePdf ? null : onDownloadEstimatePdf,
                icon: isDownloadingEstimatePdf
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: const Text('Download Estimate PDF'),
              ),
              const SizedBox(height: 10),
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
                if (estimate.isChangesRequested) ...[
                  FilledButton.icon(
                    onPressed: isRevising ? null : onReviseAndResend,
                    icon: isRevising
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.edit_outlined),
                    label: const Text('Revise & Re-send'),
                  ),
                ] else if (estimate.isApproved) ...[
                  if (estimate.isScheduled)
                    OutlinedButton.icon(
                      onPressed: onViewInAppointments,
                      icon: const Icon(Icons.event_available, size: 16, color: Colors.green),
                      label: const Text('View in Appointments'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: isScheduling ? null : onScheduleWork,
                      icon: isScheduling
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.event_outlined),
                      label: const Text('Schedule Work'),
                    ),
                ] else if (estimate.isPending) ...[
                  FilledButton.icon(
                    onPressed: onOwnerApprove,
                    icon: const Icon(Icons.phone_in_talk_outlined),
                    label: const Text('Approve (Phone/Text Confirmed)'),
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
      ),
    );
  }
}

class _OwnerApprovalResult {
  const _OwnerApprovalResult({required this.method, required this.note});

  final String method;
  final String note;
}

enum _RecurrenceCadence { none, weekly, biweekly, monthly }

class _RecurrenceChoice {
  const _RecurrenceChoice({required this.cadence, required this.occurrences});

  final _RecurrenceCadence cadence;
  /// ignored when cadence == none
  final int occurrences;

  int? get cadenceDays => switch (cadence) {
        _RecurrenceCadence.weekly => 7,
        _RecurrenceCadence.biweekly => 14,
        _ => null, // monthly is computed via DateTime month-add, not a fixed day count
      };
}

class _RecurrenceDialog extends StatefulWidget {
  const _RecurrenceDialog();

  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  _RecurrenceCadence _cadence = _RecurrenceCadence.none;
  int _occurrences = 4;

  void _submit() {
    Navigator.of(context).pop(
      _RecurrenceChoice(cadence: _cadence, occurrences: _occurrences),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Repeat This Job?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Schedule this as a one-time job, or set up a recurring cadence.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<_RecurrenceCadence>(
              initialValue: _cadence,
              decoration: const InputDecoration(labelText: 'Repeat', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: _RecurrenceCadence.none, child: Text("Don't repeat")),
                DropdownMenuItem(value: _RecurrenceCadence.weekly, child: Text('Weekly')),
                DropdownMenuItem(value: _RecurrenceCadence.biweekly, child: Text('Every 2 weeks')),
                DropdownMenuItem(value: _RecurrenceCadence.monthly, child: Text('Monthly')),
              ],
              onChanged: (value) => setState(() => _cadence = value ?? _RecurrenceCadence.none),
            ),
            if (_cadence != _RecurrenceCadence.none) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _occurrences,
                decoration: const InputDecoration(labelText: 'Number of occurrences', border: OutlineInputBorder()),
                items: [
                  for (final count in [2, 4, 6, 8, 12, 16, 26, 52])
                    DropdownMenuItem(value: count, child: Text('$count')),
                ],
                onChanged: (value) => setState(() => _occurrences = value ?? _occurrences),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// optional step in the "Schedule Work" flow: pick a checklist template to
/// snapshot onto the new job, or skip entirely
class _ChecklistTemplatePickerDialog extends StatelessWidget {
  const _ChecklistTemplatePickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Attach a Checklist? (optional)'),
      content: SizedBox(
        width: 380,
        child: StreamBuilder<List<ChecklistTemplate>>(
          stream: ChecklistTemplateService.watchAllTemplates(),
          builder: (context, snapshot) {
            final templates = snapshot.data ?? const <ChecklistTemplate>[];
            if (templates.isEmpty) {
              return const Text('No checklist templates saved yet.');
            }
            return SizedBox(
              height: 240,
              child: ListView.builder(
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return ListTile(
                    title: Text(template.name),
                    subtitle: Text(template.items.join(' · ')),
                    onTap: () => Navigator.of(context).pop(template),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
      ],
    );
  }
}

class _OwnerApprovalDialog extends StatefulWidget {
  const _OwnerApprovalDialog();

  @override
  State<_OwnerApprovalDialog> createState() => _OwnerApprovalDialogState();
}

class _OwnerApprovalDialogState extends State<_OwnerApprovalDialog> {
  final _noteController = TextEditingController();
  String _method = 'phone';

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_OwnerApprovalResult(method: _method, note: _noteController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve on Client\'s Behalf'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How did the client confirm approval?'),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'phone', label: Text('Phone call')),
                ButtonSegment(value: 'text', label: Text('Text message')),
              ],
              selected: {_method},
              onSelectionChanged: (selection) => setState(() => _method = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Example: Called client 6/12, confirmed verbally.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _RequestEstimateChangesDialog extends StatefulWidget {
  const _RequestEstimateChangesDialog();

  @override
  State<_RequestEstimateChangesDialog> createState() => _RequestEstimateChangesDialogState();
}

class _RequestEstimateChangesDialogState extends State<_RequestEstimateChangesDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Estimate Changes'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'What should be changed?',
              hintText: 'Example: Remove pressure washing and add window cleaning.',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) {
                return 'Please describe the requested changes.';
              }
              if (text.length < 8) {
                return 'Please add a bit more detail.';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Send Request'),
        ),
      ],
    );
  }
}

class _ReviseEstimateDialog extends StatefulWidget {
  const _ReviseEstimateDialog({
    required this.estimateNumber,
    required this.currentVersion,
    required this.initialServices,
  });

  final String estimateNumber;
  final int currentVersion;
  final List<InvoiceServiceItem> initialServices;

  @override
  State<_ReviseEstimateDialog> createState() => _ReviseEstimateDialogState();
}

class _ReviseEstimateDialogState extends State<_ReviseEstimateDialog> {
  final List<_ServiceRowController> _rows = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialServices.isEmpty) {
      _rows.add(_ServiceRowController());
      return;
    }

    for (final item in widget.initialServices) {
      _rows.add(_ServiceRowController.fromItem(item));
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_ServiceRowController()));
  }

  void _removeRow(int index) {
    if (_rows.length == 1) {
      return;
    }
    setState(() {
      final row = _rows.removeAt(index);
      row.dispose();
    });
  }

  void _submit() {
    final parsed = <InvoiceServiceItem>[];
    for (final row in _rows) {
      final item = row.toServiceItem();
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Each revised service must have a name and price > 0.')),
        );
        return;
      }
      parsed.add(item);
    }

    setState(() => _isSaving = true);
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final nextVersion = widget.currentVersion + 1;
    return AlertDialog(
      title: Text('Revise ${widget.estimateNumber} (v$nextVersion)'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: StreamBuilder<List<CommonService>>(
            stream: ServiceCatalogService.watchAllServices(),
            builder: (context, snapshot) {
              final catalog = snapshot.data ?? const <CommonService>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _rows.length; i++)
                    _ServiceRowEditor(
                      key: ObjectKey(_rows[i]),
                      row: _rows[i],
                      onRemove: () => _removeRow(i),
                      catalog: catalog,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _isSaving ? null : _addRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Add service'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Re-send Estimate'),
        ),
      ],
    );
  }
}

class _ServiceRowController {
  _ServiceRowController({
    String name = '',
    String description = '',
    String price = '',
    String quantity = '',
    String unit = '',
    this.isPerUnit = false,
  })  : nameController = TextEditingController(text: name),
        descriptionController = TextEditingController(text: description),
        priceController = TextEditingController(text: price),
        quantityController = TextEditingController(text: quantity),
        unitController = TextEditingController(text: unit);

  /// reconstruct a row from an existing service item (used by the revise dialog)
  factory _ServiceRowController.fromItem(InvoiceServiceItem item) {
    return _ServiceRowController(
      name: item.name,
      description: item.description,
      price: item.isPerUnit ? item.unitPrice!.toStringAsFixed(2) : item.price.toStringAsFixed(2),
      quantity: item.quantity?.toString() ?? '',
      unit: item.unit ?? '',
      isPerUnit: item.isPerUnit,
    );
  }

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  /// flat price, or price-per-unit when [isPerUnit] is true
  final TextEditingController priceController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  bool isPerUnit;

  double? get computedPrice {
    if (isPerUnit) {
      final unitPrice = double.tryParse(priceController.text.trim());
      final qty = double.tryParse(quantityController.text.trim());
      if (unitPrice == null || qty == null) return null;
      return unitPrice * qty;
    }
    return double.tryParse(priceController.text.trim());
  }

  /// populate this row's fields from a saved catalog entry
  void applyCatalogEntry(CommonService entry) {
    nameController.text = entry.name;
    descriptionController.text = entry.description;
    if (entry.isPerUnit) {
      isPerUnit = true;
      priceController.text = entry.unitPrice!.toStringAsFixed(2);
      unitController.text = entry.unit ?? '';
      quantityController.clear();
    } else {
      isPerUnit = false;
      priceController.text = (entry.flatPrice ?? 0).toStringAsFixed(2);
      unitController.clear();
      quantityController.clear();
    }
  }

  InvoiceServiceItem? toServiceItem() {
    final name = nameController.text.trim();
    final total = computedPrice;
    if (name.isEmpty || total == null || total <= 0) return null;
    return InvoiceServiceItem(
      name: name,
      description: descriptionController.text.trim(),
      price: total,
      unitPrice: isPerUnit ? double.tryParse(priceController.text.trim()) : null,
      quantity: isPerUnit ? double.tryParse(quantityController.text.trim()) : null,
      unit: isPerUnit ? unitController.text.trim() : null,
    );
  }

  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    quantityController.dispose();
    unitController.dispose();
  }
}

/// shared per-row editor used by both the create-estimate form and the
/// revise dialog: name (with catalog-search autocomplete), description,
/// flat-vs-per-unit toggle, and a "save to catalog" shortcut.
class _ServiceRowEditor extends StatefulWidget {
  const _ServiceRowEditor({
    super.key,
    required this.row,
    required this.onRemove,
    required this.catalog,
  });

  final _ServiceRowController row;
  final VoidCallback onRemove;
  final List<CommonService> catalog;

  @override
  State<_ServiceRowEditor> createState() => _ServiceRowEditorState();
}

class _ServiceRowEditorState extends State<_ServiceRowEditor> {
  Timer? _debounce;
  List<CommonService> _suggestions = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onNameChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _suggestions = ServiceCatalogService.searchServices(
          services: widget.catalog,
          query: query,
          limit: 8,
        );
      });
    });
  }

  void _pickSuggestion(CommonService entry) {
    setState(() {
      widget.row.applyCatalogEntry(entry);
      _suggestions = const [];
    });
  }

  Future<void> _saveToCatalog() async {
    final name = widget.row.nameController.text.trim();
    final price = double.tryParse(widget.row.priceController.text.trim());
    if (name.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a name and price before saving to common services.')),
      );
      return;
    }
    try {
      await ServiceCatalogService.saveService(
        name: name,
        description: widget.row.descriptionController.text.trim(),
        unit: widget.row.isPerUnit ? widget.row.unitController.text.trim() : null,
        unitPrice: widget.row.isPerUnit ? price : null,
        flatPrice: widget.row.isPerUnit ? null : price,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name" to common services.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  decoration: const InputDecoration(labelText: 'Service name', border: OutlineInputBorder()),
                  onChanged: _onNameChanged,
                ),
              ),
              IconButton(
                onPressed: _saveToCatalog,
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: 'Save to common services',
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove service',
              ),
            ],
          ),
          if (_suggestions.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final entry = _suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(entry.name),
                      subtitle: Text(
                        entry.isPerUnit
                            ? '\$${entry.unitPrice!.toStringAsFixed(2)} / ${entry.unit?.isEmpty ?? true ? 'unit' : entry.unit}'
                            : '\$${(entry.flatPrice ?? 0).toStringAsFixed(2)} flat',
                      ),
                      onTap: () => _pickSuggestion(entry),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: row.descriptionController,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Flat price')),
              ButtonSegment(value: true, label: Text('Price per unit')),
            ],
            selected: {row.isPerUnit},
            onSelectionChanged: (selection) => setState(() => row.isPerUnit = selection.first),
          ),
          const SizedBox(height: 8),
          if (row.isPerUnit)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price per unit', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.unitController,
                    decoration: const InputDecoration(labelText: 'Unit (e.g. ft)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            )
          else
            TextField(
              controller: row.priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder()),
            ),
          if (row.isPerUnit) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                row.computedPrice == null ? 'Total: —' : 'Total: \$${row.computedPrice!.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
