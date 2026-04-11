import 'package:flutter/material.dart';

import '../../../core/services/invoice_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/invoice.dart';
import '../../../shared/widgets/app_scaffold.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({required this.role, super.key});

  final String role;

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _invoiceNumberController = TextEditingController();
  final _clientIdController = TextEditingController();
  final List<_ServiceRow> _serviceRows = [
    _ServiceRow(nameController: TextEditingController(), priceController: TextEditingController()),
  ];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _clientIdController.dispose();
    for (final row in _serviceRows) {
      row.nameController.dispose();
      row.priceController.dispose();
    }
    super.dispose();
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

  Future<void> _submitInvoice() async {
    final invoiceNumber = _invoiceNumberController.text.trim().isEmpty
        ? _defaultInvoiceNumber()
        : _invoiceNumberController.text.trim();
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
      await InvoiceService.createInvoice(
        invoiceNumber: invoiceNumber,
        clientId: clientId,
        services: services,
      );
      if (!mounted) {
        return;
      }

      _invoiceNumberController.clear();
      _clientIdController.clear();
      for (final row in _serviceRows) {
        row.nameController.clear();
        row.priceController.clear();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice uploaded to Firebase.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create invoice: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _setStatus(String invoiceId, String status) async {
    try {
      await InvoiceService.updateStatus(invoiceId: invoiceId, status: status);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice status set to $status.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update invoice status: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: 'Invoices',
      role: widget.role,
      selectedRoute: '/invoices',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (widget.role == 'owner') ...[
            _OwnerInvoiceForm(
              invoiceNumberController: _invoiceNumberController,
              clientIdController: _clientIdController,
              serviceRows: _serviceRows,
              isSubmitting: _isSubmitting,
              onAddService: _addServiceRow,
              onRemoveService: _removeServiceRow,
              onSubmit: _submitInvoice,
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
            StreamBuilder<List<Invoice>>(
              stream: InvoiceService.watchInvoices(role: widget.role, clientId: clientId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load invoices: ${snapshot.error}'),
                    ),
                  );
                }

                final invoices = snapshot.data ?? const <Invoice>[];
                if (invoices.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.role == 'owner'
                          ? 'No invoices yet. Create one above.'
                          : 'No invoices available for your client ID yet.'),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final invoice in invoices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InvoiceCard(
                          invoice: invoice,
                          isClient: widget.role == 'client',
                          onApprove: () => _setStatus(invoice.id, InvoiceStatus.approved),
                          onDeny: () => _setStatus(invoice.id, InvoiceStatus.denied),
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

class _OwnerInvoiceForm extends StatelessWidget {
  const _OwnerInvoiceForm({
    required this.invoiceNumberController,
    required this.clientIdController,
    required this.serviceRows,
    required this.isSubmitting,
    required this.onAddService,
    required this.onRemoveService,
    required this.onSubmit,
  });

  final TextEditingController invoiceNumberController;
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
            Text('Create Invoice / Estimate', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: invoiceNumberController,
              decoration: const InputDecoration(
                labelText: 'Invoice number (optional)',
                border: OutlineInputBorder(),
                hintText: 'INV-123456',
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
                      : const Text('Submit Invoice'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.isClient,
    required this.onApprove,
    required this.onDeny,
  });

  final Invoice invoice;
  final bool isClient;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
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
                    invoice.invoiceNumber,
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
                    invoice.status,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Client ID: ${invoice.clientId}'),
            const SizedBox(height: 10),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in invoice.services)
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
                Text('\$${invoice.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if (isClient && invoice.isPending) ...[
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
