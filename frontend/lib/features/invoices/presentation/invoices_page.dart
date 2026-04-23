import 'package:flutter/material.dart';

import '../../../core/services/invoice_pdf_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/invoice.dart';
import '../../../shared/widgets/app_scaffold.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  String? _downloadingInvoiceId;

  Future<void> _downloadInvoicePdf(Invoice invoice) async {
    setState(() => _downloadingInvoiceId = invoice.id);
    try {
      final savedPath = await InvoicePdfService.generateAndDownloadInvoicePdf(invoice: invoice);
      if (!mounted) {
        return;
      }
      final message =
          savedPath == null ? 'Invoice PDF downloaded.' : 'Invoice PDF saved: $savedPath';
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
                          ? 'No invoices yet. Convert approved estimates to invoices from the Estimates page.'
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
                          role: widget.role,
                          isDownloadingPdf: _downloadingInvoiceId == invoice.id,
                          onDownloadPdf: () => _downloadInvoicePdf(invoice),
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

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.role,
    required this.isDownloadingPdf,
    required this.onDownloadPdf,
  });

  final Invoice invoice;
  final String role;
  final bool isDownloadingPdf;
  final VoidCallback onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    final statusKey = InvoiceStatus.displayLabel(invoice.status);
    final statusColor = InvoiceStatus.isSent(statusKey)
      ? Colors.green
        : statusKey == InvoiceStatus.denied
        ? Colors.red
        : Colors.orange;
    final statusText = switch (statusKey) {
      InvoiceStatus.sent => role == 'client' ? 'Received' : 'Sent',
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
                    statusText,
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isDownloadingPdf ? null : onDownloadPdf,
              icon: isDownloadingPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Download PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
