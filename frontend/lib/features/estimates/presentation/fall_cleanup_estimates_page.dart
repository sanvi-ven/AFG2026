import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/comms_service.dart';
import '../../../core/services/fall_cleanup_estimate_service.dart';
import '../../../core/services/fall_cleanup_pdf_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/owner_settings_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/fall_cleanup_estimate.dart';
import '../../../models/invoice.dart';
import '../../../shared/utils/list_highlight_controller.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/sort_control.dart';
import '../../clients/presentation/quick_add_client_dialog.dart';
import '../../legal/presentation/legal_document_page.dart';

/// a second, separate estimate flow for the fall cleanup product: a fixed
/// menu of three plans (always shown, with prices) instead of the general
/// Estimates page's dynamic line-item list. See CLAUDE.md "Fall Cleanup
/// Estimate Template" for the full design rationale.
class FallCleanupEstimatesPage extends StatefulWidget {
  const FallCleanupEstimatesPage(
      {required this.role, this.authToken, this.highlightId, super.key});

  final String role;
  final String? authToken;
  final String? highlightId;

  @override
  State<FallCleanupEstimatesPage> createState() =>
      _FallCleanupEstimatesPageState();
}

class _FallCleanupEstimatesPageState extends State<FallCleanupEstimatesPage> {
  final _estimateNumberController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _essentialPriceController = TextEditingController();
  final _premiumPriceController = TextEditingController();
  final _bothPriceController = TextEditingController();
  final _disposalFeeController = TextEditingController();
  final _whereLeavesCanGoController = TextEditingController();
  final _additionalWorkDescriptionController = TextEditingController();
  final _additionalWorkAmountController = TextEditingController();
  final _notesController = TextEditingController();
  final _agreedNoteController = TextEditingController();

  String _disposalChoice = FallCleanupDisposalChoice.woodsOrCurb;
  bool _additionalWorkNeedsQuote = false;
  bool _notifyClientBySms = false;
  bool _clientAlreadyAgreed = false;
  String? _agreedPlan;
  String _agreedMethod = 'phone';
  bool _isSubmitting = false;

  String? _downloadingPdfId;
  String? _schedulingEstimateId;
  String? _convertingEstimateId;
  String? _requestingChangesEstimateId;
  String? _approvingEstimateId;
  String? _editingEstimateId;
  String? _archivingEstimateId;
  String? _deletingEstimateId;

  Timer? _clientSearchDebounce;
  StreamSubscription<List<ClientProfile>>? _clientsSub;
  List<ClientProfile> _knownClients = const [];
  List<ClientProfile> _clientSuggestions = const [];
  ClientProfile? _selectedClient;
  bool _isLoadingClientSuggestions = true;

  ListSortMode _sortMode = ListSortMode.newestFirst;
  late final ListHighlightController _highlight =
      ListHighlightController(widget.highlightId);

  @override
  void initState() {
    super.initState();
    if (widget.role == 'owner') {
      FallCleanupEstimateService.peekNextFallCleanupNumber().then((preview) {
        if (mounted && _estimateNumberController.text.trim().isEmpty) {
          setState(() => _estimateNumberController.text = preview);
        }
      });
      _clientsSub = ClientProfileService.watchAllProfiles().listen((profiles) {
        if (!mounted) return;
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
        });
      });
    } else if (widget.role == 'client') {
      final ownProfile = ClientSession.profile.value;
      if (ownProfile != null) {
        _knownClients = [ownProfile];
      }
      _isLoadingClientSuggestions = false;
    }
  }

  @override
  void dispose() {
    _clientSearchDebounce?.cancel();
    _clientsSub?.cancel();
    _estimateNumberController.dispose();
    _clientIdController.dispose();
    _essentialPriceController.dispose();
    _premiumPriceController.dispose();
    _bothPriceController.dispose();
    _disposalFeeController.dispose();
    _whereLeavesCanGoController.dispose();
    _additionalWorkDescriptionController.dispose();
    _additionalWorkAmountController.dispose();
    _notesController.dispose();
    _agreedNoteController.dispose();
    super.dispose();
  }

  void _onClientSearchChanged(String value) {
    _clientSearchDebounce?.cancel();
    if (_selectedClient != null && value.trim() != _selectedClient!.signupId) {
      setState(() => _selectedClient = null);
    }
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _clientSuggestions = const []);
      return;
    }
    _clientSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
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

  List<InvoiceServiceItem> _synthesizeServiceItems(FallCleanupEstimate estimate) {
    final items = <InvoiceServiceItem>[];
    final plan = estimate.selectedPlan;
    if (plan != null) {
      items.add(InvoiceServiceItem(
        name: '${FallCleanupPlan.displayLabel(plan)} Fall Cleanup',
        price: estimate.priceFor(plan) ?? 0,
      ));
    }
    if (estimate.disposalFee > 0) {
      items.add(InvoiceServiceItem(
        name:
            'Leaf disposal — ${FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice)}',
        price: estimate.disposalFee,
      ));
    }
    final additionalAmount = estimate.additionalWorkAmount;
    if (!estimate.additionalWorkNeedsQuote &&
        additionalAmount != null &&
        additionalAmount > 0) {
      items.add(InvoiceServiceItem(
        name: estimate.additionalWorkDescription.trim().isEmpty
            ? 'Additional work'
            : estimate.additionalWorkDescription.trim(),
        price: additionalAmount,
      ));
    }
    return items;
  }

  Future<bool> _sendFallCleanupReadySms({
    required ClientProfile client,
    required String estimateNumber,
  }) async {
    final phone = client.phoneNumber.trim();
    if (phone.isEmpty || !client.smsOptIn) return false;
    final ownerSettings = await OwnerSettingsService.fetch();
    final businessName = ownerSettings.companyName.trim().isEmpty
        ? 'Your service provider'
        : ownerSettings.companyName.trim();
    return CommsService.sendSms(
      to: phone,
      body: '$businessName: A new fall cleanup estimate ($estimateNumber) is '
          'ready for your review. Log in to your account to view it. '
          'Reply STOP to opt out.',
    );
  }

  void _resetForm() {
    _estimateNumberController.clear();
    _clientIdController.clear();
    _essentialPriceController.clear();
    _premiumPriceController.clear();
    _bothPriceController.clear();
    _disposalFeeController.clear();
    _whereLeavesCanGoController.clear();
    _additionalWorkDescriptionController.clear();
    _additionalWorkAmountController.clear();
    _notesController.clear();
    _agreedNoteController.clear();
    setState(() {
      _selectedClient = null;
      _clientSuggestions = const [];
      _disposalChoice = FallCleanupDisposalChoice.woodsOrCurb;
      _additionalWorkNeedsQuote = false;
      _notifyClientBySms = false;
      _clientAlreadyAgreed = false;
      _agreedPlan = null;
      _agreedMethod = 'phone';
    });
    FallCleanupEstimateService.peekNextFallCleanupNumber().then((preview) {
      if (mounted) setState(() => _estimateNumberController.text = preview);
    });
  }

  Future<void> _submitEstimate() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Client ID is required.')));
      return;
    }

    final essentialPrice =
        double.tryParse(_essentialPriceController.text.trim());
    final premiumPrice = double.tryParse(_premiumPriceController.text.trim());
    final bothPrice = double.tryParse(_bothPriceController.text.trim());
    if (essentialPrice == null && premiumPrice == null && bothPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price at least one plan.')));
      return;
    }

    final disposalFee = _disposalChoice == FallCleanupDisposalChoice.woodsOrCurb
        ? 0.0
        : double.tryParse(_disposalFeeController.text.trim()) ?? 0.0;
    final additionalWorkAmount = _additionalWorkNeedsQuote
        ? null
        : double.tryParse(_additionalWorkAmountController.text.trim());

    if (_clientAlreadyAgreed) {
      final plan = _agreedPlan;
      if (plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pick which plan the client agreed to.')));
        return;
      }
      final priceForPlan = switch (plan) {
        FallCleanupPlan.essential => essentialPrice,
        FallCleanupPlan.premium => premiumPrice,
        FallCleanupPlan.both => bothPrice,
        _ => null,
      };
      if (priceForPlan == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter a price for the plan the client agreed to.')));
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final existingClient = await ClientProfileService.fetchBySignupId(clientId);
      if (existingClient == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Select a valid client from suggestions.')));
        }
        return;
      }

      final consumedNumber =
          await FallCleanupEstimateService.consumeNextFallCleanupNumber();
      final estimateNumber = _estimateNumberController.text.trim().isEmpty
          ? consumedNumber
          : _estimateNumberController.text.trim();

      if (_clientAlreadyAgreed) {
        await FallCleanupEstimateService.createApprovedEstimate(
          estimateNumber: estimateNumber,
          clientId: clientId,
          essentialPrice: essentialPrice,
          premiumPrice: premiumPrice,
          bothPrice: bothPrice,
          selectedPlan: _agreedPlan!,
          disposalChoice: _disposalChoice,
          disposalFee: disposalFee,
          whereLeavesCanGo: _whereLeavesCanGoController.text,
          additionalWorkDescription: _additionalWorkDescriptionController.text,
          additionalWorkAmount: additionalWorkAmount,
          additionalWorkNeedsQuote: _additionalWorkNeedsQuote,
          notes: _notesController.text,
          approvalMethod: _agreedMethod,
          approvalNote: _agreedNoteController.text,
        );
      } else {
        await FallCleanupEstimateService.createEstimate(
          estimateNumber: estimateNumber,
          clientId: clientId,
          essentialPrice: essentialPrice,
          premiumPrice: premiumPrice,
          bothPrice: bothPrice,
          disposalChoice: _disposalChoice,
          disposalFee: disposalFee,
          whereLeavesCanGo: _whereLeavesCanGoController.text,
          additionalWorkDescription: _additionalWorkDescriptionController.text,
          additionalWorkAmount: additionalWorkAmount,
          additionalWorkNeedsQuote: _additionalWorkNeedsQuote,
          notes: _notesController.text,
        );
      }

      if (!mounted) return;

      bool? smsResult;
      if (_notifyClientBySms) {
        smsResult = await _sendFallCleanupReadySms(
          client: existingClient,
          estimateNumber: estimateNumber,
        );
      }
      if (!mounted) return;

      final message = switch (smsResult) {
        null => 'Fall cleanup estimate sent to client.',
        true => 'Fall cleanup estimate sent to client. Text notification sent.',
        false =>
          'Fall cleanup estimate sent to client. Text notification failed to send.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      _resetForm();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to create estimate: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _approvePlan(FallCleanupEstimate estimate, String plan) async {
    setState(() => _approvingEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.approvePlan(estimateId: estimate.id, plan: plan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${FallCleanupPlan.displayLabel(plan)} approved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to approve: $error')));
    } finally {
      if (mounted) setState(() => _approvingEstimateId = null);
    }
  }

  Future<void> _requestChanges(FallCleanupEstimate estimate) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _FallCleanupChangesDialog(),
    );
    if (message == null) return;
    setState(() => _requestingChangesEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.requestChanges(
          estimateId: estimate.id, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Change request sent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to send request: $error')));
    } finally {
      if (mounted) setState(() => _requestingChangesEstimateId = null);
    }
  }

  Future<void> _approveByOwner(FallCleanupEstimate estimate) async {
    final offeredPlans = [
      for (final plan in FallCleanupPlan.all)
        if (estimate.priceFor(plan) != null) plan,
    ];
    if (offeredPlans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price at least one plan before approving.')));
      return;
    }

    final result = await showDialog<_FallCleanupOwnerApprovalResult>(
      context: context,
      builder: (_) => _FallCleanupOwnerApprovalDialog(offeredPlans: offeredPlans),
    );
    if (result == null) return;

    setState(() => _approvingEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.approveByOwner(
        estimateId: estimate.id,
        plan: result.plan,
        method: result.method,
        note: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estimate approved on the client\'s behalf.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to approve estimate: $error')));
    } finally {
      if (mounted) setState(() => _approvingEstimateId = null);
    }
  }

  Future<void> _editEstimate(FallCleanupEstimate estimate) async {
    final result = await showDialog<_FallCleanupEditResult>(
      context: context,
      builder: (_) => _EditFallCleanupEstimateDialog(estimate: estimate),
    );
    if (result == null) return;

    setState(() => _editingEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.updateEstimate(
        estimateId: estimate.id,
        essentialPrice: result.essentialPrice,
        premiumPrice: result.premiumPrice,
        bothPrice: result.bothPrice,
        disposalChoice: result.disposalChoice,
        disposalFee: result.disposalFee,
        whereLeavesCanGo: result.whereLeavesCanGo,
        additionalWorkDescription: result.additionalWorkDescription,
        additionalWorkAmount: result.additionalWorkAmount,
        additionalWorkNeedsQuote: result.additionalWorkNeedsQuote,
        notes: result.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Estimate updated.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update estimate: $error')));
    } finally {
      if (mounted) setState(() => _editingEstimateId = null);
    }
  }

  Future<void> _convertToInvoice(FallCleanupEstimate estimate) async {
    if (!estimate.isConvertible) return;
    setState(() => _convertingEstimateId = estimate.id);
    try {
      final services = _synthesizeServiceItems(estimate);
      final invoiceId = await InvoiceService.createInvoiceFromEstimate(
        invoiceNumber: estimate.estimateNumber,
        clientId: estimate.clientId,
        services: services,
        sourceEstimateId: estimate.id,
        notes: estimate.notes,
        terms: estimate.policyContent,
      );
      await FallCleanupEstimateService.markConverted(
          estimateId: estimate.id, invoiceId: invoiceId);
      if (!mounted) return;
      final limitation = estimate.additionalWorkNeedsQuote
          ? ' Note: additional work is still "quote upon request" and was not '
              'included — finalize its price first if it should be billed.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${estimate.estimateNumber} converted to invoice and sent to client.$limitation')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to convert estimate: $error')));
    } finally {
      if (mounted) setState(() => _convertingEstimateId = null);
    }
  }

  Future<void> _scheduleWork(FallCleanupEstimate estimate) async {
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
      final client = await ClientProfileService.fetchBySignupId(estimate.clientId);
      final address = client?.address ?? '';
      final phoneNumber = client?.phoneNumber ?? '';
      final services = _synthesizeServiceItems(estimate);
      final total = services.fold<double>(0, (sum, item) => sum + item.price);

      final workId = await ScheduledWorkService.createScheduledWork(
        estimateId: estimate.id,
        estimateNumber: estimate.estimateNumber,
        clientId: estimate.clientId,
        services: services,
        total: total,
        scheduledDate: scheduledDateTime,
        address: address,
        phoneNumber: phoneNumber,
      );
      await FallCleanupEstimateService.markScheduled(
          estimateId: estimate.id, scheduledWorkId: workId);

      if (!mounted) return;
      final formatted = DateFormat('MMM d, yyyy · h:mm a').format(scheduledDateTime);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Work scheduled for $formatted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to schedule work: $error')));
    } finally {
      if (mounted) setState(() => _schedulingEstimateId = null);
    }
  }

  Future<void> _downloadPdf(FallCleanupEstimate estimate) async {
    setState(() => _downloadingPdfId = estimate.id);
    try {
      final savedPath =
          await FallCleanupPdfService.generateAndDownloadFallCleanupPdf(estimate: estimate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(savedPath == null ? 'PDF downloaded.' : 'PDF saved: $savedPath')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to generate PDF: $error')));
    } finally {
      if (mounted) setState(() => _downloadingPdfId = null);
    }
  }

  Future<void> _archiveEstimate(FallCleanupEstimate estimate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Estimate'),
        content: Text(
            'Archive ${estimate.estimateNumber}? It will be removed from the client\'s view and moved to your archived section.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _archivingEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.archiveEstimate(estimate.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to archive estimate: $error')));
    } finally {
      if (mounted) setState(() => _archivingEstimateId = null);
    }
  }

  Future<void> _deleteForever(FallCleanupEstimate estimate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text(
            'Permanently delete ${estimate.estimateNumber}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete Forever')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingEstimateId = estimate.id);
    try {
      await FallCleanupEstimateService.deleteEstimatePermanently(estimate.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _deletingEstimateId = null);
    }
  }

  void _viewInAppointments(FallCleanupEstimate estimate) {
    final workId = estimate.scheduledWorkId;
    if (workId == null || workId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppRouter.appointments,
      arguments: {
        'role': widget.role,
        'authToken': widget.authToken,
        'highlightId': workId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: 'Fall Cleanup Estimates',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: AppRouter.fallCleanupEstimates,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (widget.role == 'owner') ...[
            _buildOwnerForm(context),
            const SizedBox(height: 16),
          ],
          if (widget.role == 'client' &&
              (clientId == null || clientId.trim().isEmpty))
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Client ID not found. Please log in from the client email flow first.'),
              ),
            )
          else
            StreamBuilder<List<FallCleanupEstimate>>(
              stream: FallCleanupEstimateService.watchEstimates(
                  role: widget.role, clientId: clientId),
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

                final allEstimates = snapshot.data ?? const <FallCleanupEstimate>[];
                var estimates = allEstimates.where((e) => !e.isArchived).toList();
                var archived = allEstimates.where((e) => e.isArchived).toList();

                void applySort(List<FallCleanupEstimate> list) {
                  switch (_sortMode) {
                    case ListSortMode.newestFirst:
                      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      break;
                    case ListSortMode.oldestFirst:
                      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                      break;
                    case ListSortMode.client:
                      list.sort((a, b) => ClientProfileService.displayNameFor(
                              _knownClients, a.clientId)
                          .toLowerCase()
                          .compareTo(ClientProfileService.displayNameFor(
                                  _knownClients, b.clientId)
                              .toLowerCase()));
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
                          ? 'No fall cleanup estimates yet. Create one above.'
                          : 'No fall cleanup estimates available for your client ID yet.'),
                    ),
                  );
                }

                Widget estimateCard(FallCleanupEstimate estimate) => KeyedSubtree(
                      key: _highlight.keyFor(estimate.id),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCard(estimate),
                      ),
                    );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SortControl(
                        value: _sortMode,
                        onChanged: (mode) => setState(() => _sortMode = mode),
                      ),
                    ),
                    for (final estimate in estimates) estimateCard(estimate),
                    if (widget.role == 'owner' && archived.isNotEmpty)
                      ExpansionTile(
                        title: Text('Archived (${archived.length})'),
                        children: [for (final estimate in archived) estimateCard(estimate)],
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOwnerForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create Fall Cleanup Estimate',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _estimateNumberController,
              decoration: const InputDecoration(
                labelText: 'Estimate number',
                border: OutlineInputBorder(),
                hintText: 'FC-0001',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _clientIdController,
                    decoration: InputDecoration(
                      labelText: 'Client (ID, name, or address)',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isLoadingClientSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                    onChanged: _onClientSearchChanged,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openQuickAddClient,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('New Client'),
                ),
              ],
            ),
            if (_selectedClient != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedClient!.signupId} · ${_selectedClient!.fullName}\n'
                  '${_selectedClient!.address.isEmpty ? 'Address unavailable' : _selectedClient!.address}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (_clientSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _clientSuggestions.length,
                    itemBuilder: (context, index) {
                      final client = _clientSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text('${client.signupId} · ${client.fullName}'),
                        subtitle: Text(
                            client.address.isEmpty ? 'Address unavailable' : client.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => _pickClientSuggestion(client),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Plans', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Leave a plan blank if it isn\'t offered for this property.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _essentialPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Essential price', border: OutlineInputBorder(), prefixText: r'$'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _premiumPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Premium price', border: OutlineInputBorder(), prefixText: r'$'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bothPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Both (two visits) price',
                  border: OutlineInputBorder(),
                  prefixText: r'$'),
            ),
            const SizedBox(height: 16),
            Text('Leaf Disposal', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final choice in FallCleanupDisposalChoice.all)
                  ButtonSegment(
                      value: choice, label: Text(FallCleanupDisposalChoice.displayLabel(choice))),
              ],
              selected: {_disposalChoice},
              onSelectionChanged: (selection) =>
                  setState(() => _disposalChoice = selection.first),
            ),
            if (_disposalChoice != FallCleanupDisposalChoice.woodsOrCurb) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _disposalFeeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Disposal fee', border: OutlineInputBorder(), prefixText: r'$'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _whereLeavesCanGoController,
              decoration: const InputDecoration(
                  labelText: 'Where leaves can go (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. curb is fine, no street blowing in this town'),
            ),
            const SizedBox(height: 16),
            Text('Additional Work', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _additionalWorkDescriptionController,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            if (!_additionalWorkNeedsQuote)
              TextField(
                controller: _additionalWorkAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Additional work price', border: OutlineInputBorder(), prefixText: r'$'),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _additionalWorkNeedsQuote,
              onChanged: (value) =>
                  setState(() => _additionalWorkNeedsQuote = value ?? false),
              title: const Text('Separate quote upon request'),
              subtitle: const Text(
                  'Check this instead of entering a price if extra work needs its own quote.'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)', border: OutlineInputBorder()),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _clientAlreadyAgreed,
              onChanged: (value) => setState(() => _clientAlreadyAgreed = value ?? false),
              title: const Text('Client already agreed to a plan'),
              subtitle:
                  const Text('Record a phone/text approval instead of sending it for review.'),
            ),
            if (_clientAlreadyAgreed) ...[
              const SizedBox(height: 4),
              Text('Which plan?', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  for (final plan in FallCleanupPlan.all)
                    ButtonSegment(value: plan, label: Text(FallCleanupPlan.displayLabel(plan))),
                ],
                selected: _agreedPlan == null ? const {} : {_agreedPlan!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) =>
                    setState(() => _agreedPlan = selection.isEmpty ? null : selection.first),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'phone', label: Text('Phone call')),
                  ButtonSegment(value: 'text', label: Text('Text message')),
                ],
                selected: {_agreedMethod},
                onSelectionChanged: (selection) =>
                    setState(() => _agreedMethod = selection.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _agreedNoteController,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                    labelText: 'Note (optional)', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _notifyClientBySms,
              onChanged: (value) => setState(() => _notifyClientBySms = value ?? false),
              title: const Text('Text the client that this fall cleanup estimate is ready'),
              subtitle: const Text(
                  'Only sent if the client has a phone number on file and has opted in to text reminders.'),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submitEstimate,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send Estimate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(FallCleanupEstimate estimate) {
    final statusColor = switch (estimate.status) {
      FallCleanupStatus.signed => Colors.green,
      FallCleanupStatus.changesRequested => Colors.deepOrange,
      _ => Colors.orange,
    };
    final statusText = switch (estimate.status) {
      FallCleanupStatus.signed => 'Approved',
      FallCleanupStatus.changesRequested => 'Changes requested',
      _ => 'Pending',
    };
    final canActOn = estimate.isPending || estimate.isChangesRequested;
    final isHighlighted = _highlight.isHighlighted(estimate.id);

    return Card(
      color: isHighlighted ? Colors.amber.withValues(alpha: 0.15) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(statusText),
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (widget.role == 'owner') ...[
                  IconButton(
                    tooltip: estimate.isArchived ? 'Delete Forever' : 'Archive',
                    icon: Icon(
                        estimate.isArchived ? Icons.delete_forever_outlined : Icons.archive_outlined),
                    onPressed: (_archivingEstimateId == estimate.id ||
                            _deletingEstimateId == estimate.id)
                        ? null
                        : () => estimate.isArchived
                            ? _deleteForever(estimate)
                            : _archiveEstimate(estimate),
                  ),
                ],
              ],
            ),
            Text(estimate.estimateNumber, style: Theme.of(context).textTheme.titleMedium),
            Text('Client ID: ${estimate.clientId}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('Plans', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final plan in FallCleanupPlan.all)
              _buildPlanRow(estimate, plan, canActOn),
            const Divider(height: 20),
            Text('Leaf Disposal', style: Theme.of(context).textTheme.titleSmall),
            Text(estimate.disposalFee > 0
                ? '${FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice)} — \$${estimate.disposalFee.toStringAsFixed(2)}'
                : FallCleanupDisposalChoice.displayLabel(estimate.disposalChoice)),
            if (estimate.whereLeavesCanGo.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Where leaves can go', style: Theme.of(context).textTheme.titleSmall),
              Text(estimate.whereLeavesCanGo.trim()),
            ],
            const SizedBox(height: 8),
            Text('Additional Work', style: Theme.of(context).textTheme.titleSmall),
            Text(_additionalWorkText(estimate)),
            if (estimate.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notes', style: Theme.of(context).textTheme.titleSmall),
              Text(estimate.notes.trim()),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                estimate.selectedPlan == null
                    ? 'No plan selected yet'
                    : 'Total: \$${estimate.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (estimate.approvedByOwner && estimate.isSigned) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Approved by owner — confirmed via ${estimate.ownerApprovalMethod ?? 'phone'}'
                  '${estimate.ownerApprovalNote?.trim().isNotEmpty == true ? '\n"${estimate.ownerApprovalNote!.trim()}"' : ''}',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
            ],
            if (estimate.isChangesRequested && estimate.changeRequestMessage?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Requested changes: ${estimate.changeRequestMessage!.trim()}'),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Policy & Terms'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LegalDocumentBody(content: estimate.policyContent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadingPdfId == estimate.id ? null : () => _downloadPdf(estimate),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download PDF'),
                ),
                if (widget.role == 'client' && canActOn)
                  OutlinedButton.icon(
                    onPressed: _requestingChangesEstimateId == estimate.id
                        ? null
                        : () => _requestChanges(estimate),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Request Changes'),
                  ),
                if (widget.role == 'owner' && canActOn) ...[
                  OutlinedButton.icon(
                    onPressed: _editingEstimateId == estimate.id ? null : () => _editEstimate(estimate),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _approvingEstimateId == estimate.id ? null : () => _approveByOwner(estimate),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Approve (Phone/Text)'),
                  ),
                ],
                if (widget.role == 'owner' && estimate.isSigned) ...[
                  if (!estimate.convertedToInvoice)
                    FilledButton.icon(
                      onPressed: _convertingEstimateId == estimate.id
                          ? null
                          : () => _convertToInvoice(estimate),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Convert to Invoice'),
                    ),
                  if (!estimate.isScheduled)
                    OutlinedButton.icon(
                      onPressed:
                          _schedulingEstimateId == estimate.id ? null : () => _scheduleWork(estimate),
                      icon: const Icon(Icons.event_outlined),
                      label: const Text('Schedule Job'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => _viewInAppointments(estimate),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View in Appointments'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _additionalWorkText(FallCleanupEstimate estimate) {
    if (estimate.additionalWorkNeedsQuote) return 'Separate quote upon request.';
    final amount = estimate.additionalWorkAmount;
    if (amount == null || amount == 0) return 'None';
    final description =
        estimate.additionalWorkDescription.trim().isEmpty ? 'Additional work' : estimate.additionalWorkDescription.trim();
    return '$description — \$${amount.toStringAsFixed(2)}';
  }

  Widget _buildPlanRow(FallCleanupEstimate estimate, String plan, bool canActOn) {
    final price = estimate.priceFor(plan);
    final isSelected = estimate.selectedPlan == plan;
    final canApprove = widget.role == 'client' &&
        canActOn &&
        price != null &&
        estimate.selectedPlan == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (isSelected) const Icon(Icons.check_circle, color: Colors.green, size: 18),
          if (isSelected) const SizedBox(width: 6),
          Expanded(
            child: Text(
              FallCleanupPlan.displayLabel(plan),
              style: isSelected ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          Text(
            price == null ? 'Not offered' : '\$${price.toStringAsFixed(2)}',
            style: isSelected ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
          if (canApprove) ...[
            const SizedBox(width: 10),
            SizedBox(
              height: 32,
              child: FilledButton(
                onPressed:
                    _approvingEstimateId == estimate.id ? null : () => _approvePlan(estimate, plan),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Approve'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FallCleanupChangesDialog extends StatefulWidget {
  const _FallCleanupChangesDialog();

  @override
  State<_FallCleanupChangesDialog> createState() => _FallCleanupChangesDialogState();
}

class _FallCleanupChangesDialogState extends State<_FallCleanupChangesDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
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
              hintText: 'Example: Can you price the Both package too?',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Please describe the requested changes.';
              if (text.length < 8) return 'Please add a bit more detail.';
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send Request')),
      ],
    );
  }
}

class _FallCleanupOwnerApprovalResult {
  const _FallCleanupOwnerApprovalResult(
      {required this.plan, required this.method, required this.note});

  final String plan;
  final String method;
  final String note;
}

class _FallCleanupOwnerApprovalDialog extends StatefulWidget {
  const _FallCleanupOwnerApprovalDialog({required this.offeredPlans});

  final List<String> offeredPlans;

  @override
  State<_FallCleanupOwnerApprovalDialog> createState() =>
      _FallCleanupOwnerApprovalDialogState();
}

class _FallCleanupOwnerApprovalDialogState
    extends State<_FallCleanupOwnerApprovalDialog> {
  final _noteController = TextEditingController();
  String _method = 'phone';
  late String _plan = widget.offeredPlans.first;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_FallCleanupOwnerApprovalResult(
        plan: _plan, method: _method, note: _noteController.text.trim()));
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
            const Text('Which plan did the client choose?'),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                for (final plan in widget.offeredPlans)
                  ButtonSegment(value: plan, label: Text(FallCleanupPlan.displayLabel(plan))),
              ],
              selected: {_plan},
              onSelectionChanged: (selection) => setState(() => _plan = selection.first),
            ),
            const SizedBox(height: 16),
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
                hintText: 'Example: Called client 10/3, confirmed verbally.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Approve')),
      ],
    );
  }
}

class _FallCleanupEditResult {
  const _FallCleanupEditResult({
    this.essentialPrice,
    this.premiumPrice,
    this.bothPrice,
    required this.disposalChoice,
    required this.disposalFee,
    required this.whereLeavesCanGo,
    required this.additionalWorkDescription,
    this.additionalWorkAmount,
    required this.additionalWorkNeedsQuote,
    required this.notes,
  });

  final double? essentialPrice;
  final double? premiumPrice;
  final double? bothPrice;
  final String disposalChoice;
  final double disposalFee;
  final String whereLeavesCanGo;
  final String additionalWorkDescription;
  final double? additionalWorkAmount;
  final bool additionalWorkNeedsQuote;
  final String notes;
}

class _EditFallCleanupEstimateDialog extends StatefulWidget {
  const _EditFallCleanupEstimateDialog({required this.estimate});

  final FallCleanupEstimate estimate;

  @override
  State<_EditFallCleanupEstimateDialog> createState() =>
      _EditFallCleanupEstimateDialogState();
}

class _EditFallCleanupEstimateDialogState
    extends State<_EditFallCleanupEstimateDialog> {
  late final _essentialController =
      TextEditingController(text: widget.estimate.essentialPrice?.toStringAsFixed(2) ?? '');
  late final _premiumController =
      TextEditingController(text: widget.estimate.premiumPrice?.toStringAsFixed(2) ?? '');
  late final _bothController =
      TextEditingController(text: widget.estimate.bothPrice?.toStringAsFixed(2) ?? '');
  late final _disposalFeeController =
      TextEditingController(text: widget.estimate.disposalFee > 0 ? widget.estimate.disposalFee.toStringAsFixed(2) : '');
  late final _whereLeavesCanGoController =
      TextEditingController(text: widget.estimate.whereLeavesCanGo);
  late final _additionalWorkDescriptionController =
      TextEditingController(text: widget.estimate.additionalWorkDescription);
  late final _additionalWorkAmountController = TextEditingController(
      text: widget.estimate.additionalWorkAmount?.toStringAsFixed(2) ?? '');
  late final _notesController = TextEditingController(text: widget.estimate.notes);

  late String _disposalChoice = widget.estimate.disposalChoice;
  late bool _additionalWorkNeedsQuote = widget.estimate.additionalWorkNeedsQuote;

  @override
  void dispose() {
    _essentialController.dispose();
    _premiumController.dispose();
    _bothController.dispose();
    _disposalFeeController.dispose();
    _whereLeavesCanGoController.dispose();
    _additionalWorkDescriptionController.dispose();
    _additionalWorkAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_FallCleanupEditResult(
      essentialPrice: double.tryParse(_essentialController.text.trim()),
      premiumPrice: double.tryParse(_premiumController.text.trim()),
      bothPrice: double.tryParse(_bothController.text.trim()),
      disposalChoice: _disposalChoice,
      disposalFee: _disposalChoice == FallCleanupDisposalChoice.woodsOrCurb
          ? 0
          : double.tryParse(_disposalFeeController.text.trim()) ?? 0,
      whereLeavesCanGo: _whereLeavesCanGoController.text,
      additionalWorkDescription: _additionalWorkDescriptionController.text,
      additionalWorkAmount: _additionalWorkNeedsQuote
          ? null
          : double.tryParse(_additionalWorkAmountController.text.trim()),
      additionalWorkNeedsQuote: _additionalWorkNeedsQuote,
      notes: _notesController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Fall Cleanup Estimate'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _essentialController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Essential price', border: OutlineInputBorder(), prefixText: r'$'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _premiumController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Premium price', border: OutlineInputBorder(), prefixText: r'$'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bothController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Both (two visits) price',
                    border: OutlineInputBorder(),
                    prefixText: r'$'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  for (final choice in FallCleanupDisposalChoice.all)
                    ButtonSegment(
                        value: choice,
                        label: Text(FallCleanupDisposalChoice.displayLabel(choice))),
                ],
                selected: {_disposalChoice},
                onSelectionChanged: (selection) =>
                    setState(() => _disposalChoice = selection.first),
              ),
              if (_disposalChoice != FallCleanupDisposalChoice.woodsOrCurb) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _disposalFeeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Disposal fee', border: OutlineInputBorder(), prefixText: r'$'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _whereLeavesCanGoController,
                decoration: const InputDecoration(
                    labelText: 'Where leaves can go (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _additionalWorkDescriptionController,
                decoration: const InputDecoration(
                    labelText: 'Additional work description (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              if (!_additionalWorkNeedsQuote)
                TextField(
                  controller: _additionalWorkAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Additional work price',
                      border: OutlineInputBorder(),
                      prefixText: r'$'),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _additionalWorkNeedsQuote,
                onChanged: (value) =>
                    setState(() => _additionalWorkNeedsQuote = value ?? false),
                title: const Text('Separate quote upon request'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
