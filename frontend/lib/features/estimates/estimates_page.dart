//made with help of chatgpt: create flutter page that shows list of estimates from firestore stream, how to add aprove/deny buttons for client, and convert to invoice button for owner


import 'package:flutter/material.dart';

import '../../core/services/estimate_service.dart';
import '../../core/services/invoice_service.dart';
import '../../core/state/client_session.dart';
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

  @override
  void dispose() {
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

  Future<void> _setEstimateStatus(String estimateId, String status) async {
    try {
      await EstimateService.updateStatus(estimateId: estimateId, status: status);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estimate status set to $status.')),
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
        SnackBar(content: Text('${estimate.estimateNumber} converted to invoice.')),
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
                          onApprove: () => _setEstimateStatus(estimate.id, InvoiceStatus.approved),
                          onDeny: () => _setEstimateStatus(estimate.id, InvoiceStatus.denied),
                          onConvert: () => _convertToInvoice(estimate),
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
    required this.serviceRows,
    required this.isSubmitting,
    required this.onAddService,
    required this.onRemoveService,
    required this.onSubmit,
  });

  final TextEditingController estimateNumberController;
  final TextEditingController clientIdController;
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
              decoration: const InputDecoration(
                labelText: 'Client ID',
                border: OutlineInputBorder(),
              ),
            ),
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
    required this.onApprove,
    required this.onDeny,
    required this.onConvert,
  });

  final Estimate estimate;
  final String role;
  final bool isConverting;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (estimate.status) {
      InvoiceStatus.approved => Colors.green,
      InvoiceStatus.denied => Colors.red,
      _ => Colors.orange,
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
                    estimate.status,
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
                Text(
                  'Converted to invoice${estimate.convertedInvoiceId == null ? '' : ': ${estimate.convertedInvoiceId}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                FilledButton.icon(
                  onPressed: estimate.isConvertible && !isConverting ? onConvert : null,
                  icon: isConverting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: Text(
                    estimate.isApproved
                        ? 'Convert To Invoice'
                        : 'Approve Required Before Convert',
                  ),
                ),
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
