import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/contract_amendment_service.dart';
import '../../../core/services/contract_api_service.dart';
import '../../../core/services/contract_pdf_service.dart';
import '../../../core/services/contract_service.dart';
import '../../../models/contract_amendment.dart';
import '../../../models/employment_contract.dart';
import '../../../shared/widgets/contract_signature_form.dart';
import '../../legal/presentation/legal_document_page.dart';

const _consentText =
    'I have read this employment contract in full and agree to its terms. This constitutes my '
    'electronic signature.';

const _initialConsentText =
    'I have read the changes described above and agree to them. This constitutes my electronic '
    'initial on this amendment.';

/// view/sign one employee's employment contract — reachable both by the
/// employee themselves (to sign, or view/download once signed) and by the
/// owner (read-only, plus the resend-guardian-link action). Also surfaces
/// any pending amendment needing a fresh initial.
class ContractPage extends StatefulWidget {
  const ContractPage({
    required this.role,
    this.authToken,
    required this.employeeId,
    super.key,
  });

  final String role;
  final String? authToken;
  final String employeeId;

  @override
  State<ContractPage> createState() => _ContractPageState();
}

class _ContractPageState extends State<ContractPage> {
  bool _isSubmitting = false;
  bool _isResendingLink = false;
  bool _isDownloading = false;

  bool get _isOwnerViewing => widget.role == 'owner';

  Future<void> _submitSignature(ContractSignature signature) async {
    setState(() => _isSubmitting = true);
    try {
      await ContractService.submitEmployeeSignature(
        employeeId: widget.employeeId,
        signature: signature,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to sign: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitAmendmentInitial(ContractAmendment amendment, ContractSignature initials) async {
    setState(() => _isSubmitting = true);
    try {
      await ContractAmendmentService.submitEmployeeInitial(
        amendmentId: amendment.id,
        initials: initials,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to initial: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resendGuardianLink(String recordId) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return;
    setState(() => _isResendingLink = true);
    try {
      await ContractApiService.sendGuardianLink(recordId: recordId, authToken: token);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link sent to the guardian.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to send link: $error')));
      }
    } finally {
      if (mounted) setState(() => _isResendingLink = false);
    }
  }

  Future<void> _download(EmploymentContract contract) async {
    // an uploaded paper contract has no real `content` to render into a PDF
    // (recordUploadedContract creates it empty) — open the actual uploaded
    // file directly instead of generating a broken wrapper PDF around
    // nothing.
    final uploadedUrl = contract.uploadedFile?.url;
    if (uploadedUrl != null) {
      final uri = Uri.parse(uploadedUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open the uploaded file.')));
      }
      return;
    }

    setState(() => _isDownloading = true);
    try {
      await ContractPdfService.generateAndDownloadContractPdf(contract: contract);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to download: $error')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employment Contract')),
      body: StreamBuilder<EmploymentContract?>(
        stream: ContractService.watchContractForEmployee(widget.employeeId),
        builder: (context, contractSnapshot) {
          if (contractSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final contract = contractSnapshot.data;
          if (contract == null) {
            return const Center(child: Text('No contract on file yet.'));
          }

          return StreamBuilder<ContractAmendment?>(
            stream: ContractAmendmentService.watchPendingAmendmentForEmployee(widget.employeeId),
            builder: (context, amendmentSnapshot) {
              final pendingAmendment = amendmentSnapshot.data;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statusBanner(contract),
                        const SizedBox(height: 16),
                        if (contract.uploadedFile == null) ...[
                          Text('Version ${contract.contractVersion}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          LegalDocumentBody(content: contract.content),
                        ] else
                          const Text('This contract was signed on paper and uploaded by the owner.'),
                        const SizedBox(height: 24),
                        if (pendingAmendment != null)
                          _amendmentSection(contract, pendingAmendment)
                        else if (!_isOwnerViewing)
                          _signingSection(contract),
                        if (contract.isFullySigned) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isDownloading ? null : () => _download(contract),
                            icon: Icon(contract.uploadedFile != null
                                ? Icons.open_in_new
                                : Icons.download),
                            label: Text(_isDownloading
                                ? 'Preparing…'
                                : (contract.uploadedFile != null
                                    ? 'View uploaded file'
                                    : 'Download PDF')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statusBanner(EmploymentContract contract) {
    final theme = Theme.of(context);
    String text;
    switch (contract.status) {
      case ContractStatus.fullySigned:
        text = 'Fully signed.';
      case ContractStatus.uploadedSigned:
        text =
            'Paper contract on file, uploaded ${DateFormat('MMM d, yyyy').format(contract.uploadedFile!.uploadedAt)}.';
      case ContractStatus.pendingGuardianSignature:
        text = contract.guardianEmail.isEmpty
            ? 'Waiting on a parent/guardian signature — no guardian email on file yet.'
            : 'Waiting on a parent/guardian signature, sent to ${contract.guardianEmail}.';
      default:
        text = 'Awaiting your signature.';
    }

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            if (contract.status == ContractStatus.pendingGuardianSignature &&
                contract.guardianEmail.isNotEmpty &&
                widget.authToken != null)
              TextButton(
                onPressed: _isResendingLink ? null : () => _resendGuardianLink(contract.id),
                child: Text(_isResendingLink ? 'Sending…' : 'Resend link'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _signingSection(EmploymentContract contract) {
    if (contract.employeeSignature != null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ContractSignatureForm(
          consentText: _consentText,
          isSubmitting: _isSubmitting,
          onSubmit: _submitSignature,
        ),
      ),
    );
  }

  Widget _amendmentSection(EmploymentContract contract, ContractAmendment amendment) {
    final needsMyInitial = !_isOwnerViewing && amendment.employeeInitials == null;
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contract amendment', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final section in amendment.changedSections) ...[
              Text(section.sectionHeading, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(section.newText),
              const SizedBox(height: 12),
            ],
            if (needsMyInitial) ...[
              const SizedBox(height: 8),
              ContractSignatureForm(
                consentText: _initialConsentText,
                isSubmitting: _isSubmitting,
                onSubmit: (initials) => _submitAmendmentInitial(amendment, initials),
              ),
            ] else if (!amendment.isFullyInitialed)
              const Text('Waiting on a parent/guardian initial.'),
          ],
        ),
      ),
    );
  }
}
