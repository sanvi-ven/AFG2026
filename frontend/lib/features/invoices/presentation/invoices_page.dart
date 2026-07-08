/// made with the help of chatgpt 4.0, prompt: how to build a Flutter invoices page for a business app that shows invoices from Firestore in real time
library;

import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/invoice_pdf_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/invoice.dart';
import '../../../shared/utils/list_highlight_controller.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/sort_control.dart';

/// page for viewing and managing invoices with pdf download and payment tracking
class InvoicesPage extends StatefulWidget {
  const InvoicesPage(
      {required this.role, this.authToken, this.highlightId, super.key});

  final String role;
  final String? authToken;
  final String? highlightId;

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  String? _downloadingInvoiceId;
  String? _markingPaidInvoiceId;
  String? _archivingInvoiceId;
  String? _deletingInvoiceId;
  ListSortMode _sortMode = ListSortMode.newestFirst;
  late final ListHighlightController _highlight =
      ListHighlightController(widget.highlightId);

  void _viewEstimate(Invoice invoice) {
    final estimateId = invoice.sourceEstimateId;
    if (estimateId == null || estimateId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppRouter.estimates,
      arguments: {
        'role': widget.role,
        'authToken': widget.authToken,
        'highlightId': estimateId
      },
    );
  }

  Future<void> _markAsPaid(Invoice invoice) async {
    setState(() => _markingPaidInvoiceId = invoice.id);
    try {
      await InvoiceService.updateStatus(
          invoiceId: invoice.id, status: InvoiceStatus.paid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice marked as paid.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark as paid: $error')),
      );
    } finally {
      if (mounted) setState(() => _markingPaidInvoiceId = null);
    }
  }

  Future<void> _archiveInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Invoice'),
        content: Text(
          'Archive ${invoice.invoiceNumber}? It will be moved to your archived section.',
        ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _archivingInvoiceId = invoice.id);
    try {
      await InvoiceService.archiveInvoice(invoice.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive invoice: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _archivingInvoiceId = null);
    }
  }

  Future<void> _deleteInvoicePermanently(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Invoice Permanently'),
        content: Text(
            "Permanently delete ${invoice.invoiceNumber}? This can't be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingInvoiceId = invoice.id);
    try {
      await InvoiceService.deleteInvoicePermanently(invoice.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingInvoiceId = null);
    }
  }

  Future<void> _downloadInvoicePdf(Invoice invoice) async {
    setState(() => _downloadingInvoiceId = invoice.id);
    try {
      final savedPath = await InvoicePdfService.generateAndDownloadInvoicePdf(
          invoice: invoice);
      if (!mounted) {
        return;
      }
      final message = savedPath == null
          ? 'Invoice PDF downloaded.'
          : 'Invoice PDF saved: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download invoice PDF: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingInvoiceId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: 'Invoices',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/invoices',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
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
            StreamBuilder<List<ClientProfile>>(
              stream: ClientProfileService.watchAllProfiles(),
              builder: (context, clientsSnapshot) {
                final clients = clientsSnapshot.data ?? const <ClientProfile>[];

                return StreamBuilder<List<Invoice>>(
                  stream: InvoiceService.watchInvoices(
                      role: widget.role, clientId: clientId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              'Failed to load invoices: ${snapshot.error}'),
                        ),
                      );
                    }

                    final invoices = snapshot.data ?? const <Invoice>[];
                    if (invoices.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(widget.role == 'owner'
                              ? 'No invoices yet. Convert approved estimates to invoices from the Estimates page.'
                              : 'No invoices available for your client ID yet.'),
                        ),
                      );
                    }

                    void applySort(List<Invoice> list) {
                      switch (_sortMode) {
                        case ListSortMode.newestFirst:
                          list.sort(
                              (a, b) => b.createdAt.compareTo(a.createdAt));
                          break;
                        case ListSortMode.oldestFirst:
                          list.sort(
                              (a, b) => a.createdAt.compareTo(b.createdAt));
                          break;
                        case ListSortMode.client:
                          list.sort((a, b) =>
                              ClientProfileService.displayNameFor(
                                      clients, a.clientId)
                                  .toLowerCase()
                                  .compareTo(
                                      ClientProfileService.displayNameFor(
                                              clients, b.clientId)
                                          .toLowerCase()));
                          break;
                      }
                    }

                    final active =
                        invoices.where((i) => !i.isArchived).toList();
                    final archived =
                        invoices.where((i) => i.isArchived).toList();
                    applySort(active);
                    applySort(archived);

                    _highlight.maybeScrollTo(
                      [...active, ...archived].map((i) => i.id).toList(),
                      () {
                        if (mounted) setState(() {});
                      },
                    );

                    Widget invoiceCard(Invoice invoice) => KeyedSubtree(
                          key: _highlight.keyFor(invoice.id),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InvoiceCard(
                              invoice: invoice,
                              role: widget.role,
                              isDownloadingPdf:
                                  _downloadingInvoiceId == invoice.id,
                              isMarkingPaid:
                                  _markingPaidInvoiceId == invoice.id,
                              isArchiving: _archivingInvoiceId == invoice.id,
                              isDeleting: _deletingInvoiceId == invoice.id,
                              isHighlighted:
                                  _highlight.isHighlighted(invoice.id),
                              onDownloadPdf: () => _downloadInvoicePdf(invoice),
                              onMarkPaid: () => _markAsPaid(invoice),
                              onArchive: widget.role == 'owner'
                                  ? () => _archiveInvoice(invoice)
                                  : null,
                              onDeletePermanently: widget.role == 'owner'
                                  ? () => _deleteInvoicePermanently(invoice)
                                  : null,
                              onViewEstimate:
                                  (invoice.sourceEstimateId == null ||
                                          invoice.sourceEstimateId!.isEmpty)
                                      ? null
                                      : () => _viewEstimate(invoice),
                            ),
                          ),
                        );

                    return Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: SortControl(
                            value: _sortMode,
                            onChanged: (mode) =>
                                setState(() => _sortMode = mode),
                          ),
                        ),
                        for (final invoice in active) invoiceCard(invoice),
                        if (widget.role == 'owner' && archived.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ExpansionTile(
                            title: Text(
                              'Archived (${archived.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                            ),
                            tilePadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            childrenPadding: EdgeInsets.zero,
                            children: [
                              for (final invoice in archived)
                                invoiceCard(invoice),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.role,
    required this.isDownloadingPdf,
    required this.isMarkingPaid,
    required this.isArchiving,
    required this.isDeleting,
    required this.onDownloadPdf,
    required this.onMarkPaid,
    this.isHighlighted = false,
    this.onViewEstimate,
    this.onArchive,
    this.onDeletePermanently,
  });

  final Invoice invoice;
  final String role;
  final bool isDownloadingPdf;
  final bool isMarkingPaid;
  final bool isArchiving;
  final bool isDeleting;
  final bool isHighlighted;
  final VoidCallback onDownloadPdf;
  final VoidCallback onMarkPaid;
  final VoidCallback? onViewEstimate;
  final VoidCallback? onArchive;
  final VoidCallback? onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = invoice.status.trim().toLowerCase();
    final isPaid = normalizedStatus == InvoiceStatus.paid;
    final statusKey = InvoiceStatus.displayLabel(invoice.status);
    final statusColor = isPaid
        ? Colors.green
        : InvoiceStatus.isSent(statusKey)
            ? Colors.blue
            : statusKey == InvoiceStatus.denied
                ? Colors.red
                : Colors.orange;
    final statusText = isPaid
        ? 'Paid'
        : switch (statusKey) {
            InvoiceStatus.sent => role == 'client' ? 'Received' : 'Sent',
            InvoiceStatus.denied => 'Denied',
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
                      invoice.invoiceNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                          color: statusColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!invoice.isArchived && onArchive != null) ...[
                    const SizedBox(width: 4),
                    isArchiving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: onArchive,
                            icon: const Icon(Icons.archive_outlined),
                            tooltip: 'Archive invoice',
                            color: Theme.of(context).colorScheme.outline,
                            iconSize: 20,
                          ),
                  ] else if (invoice.isArchived &&
                      onDeletePermanently != null) ...[
                    const SizedBox(width: 4),
                    isDeleting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
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
              Text('Client ID: ${invoice.clientId}'),
              const SizedBox(height: 10),
              Text('Services', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final item in invoice.services)
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
                        Text(item.description,
                            style: Theme.of(context).textTheme.bodySmall),
                      if (item.isPerUnit)
                        Text(
                          '${item.quantity} ${item.unit?.isEmpty ?? true ? 'unit(s)' : item.unit} × \$${item.unitPrice!.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              if (invoice.notes.isNotEmpty) ...[
                Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(invoice.notes),
                const SizedBox(height: 10),
              ],
              if (invoice.terms.isNotEmpty) ...[
                Text('Terms', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(invoice.terms),
                const SizedBox(height: 10),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  const Expanded(
                      child: Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text('\$${invoice.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isDownloadingPdf ? null : onDownloadPdf,
                    icon: isDownloadingPdf
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined),
                    label: const Text('Download PDF'),
                  ),
                  if (onViewEstimate != null)
                    OutlinedButton.icon(
                      onPressed: onViewEstimate,
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('View Source Estimate'),
                    ),
                  if (role == 'owner' &&
                      !isPaid &&
                      InvoiceStatus.isSent(invoice.status))
                    OutlinedButton.icon(
                      onPressed: isMarkingPaid ? null : onMarkPaid,
                      icon: isMarkingPaid
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.payments_outlined),
                      label: const Text('Mark as Paid'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
