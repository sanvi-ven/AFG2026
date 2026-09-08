import 'package:flutter/material.dart';

import '../../../core/services/contract_api_service.dart';
import '../../../models/employment_contract.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/contract_signature_form.dart';
import '../../legal/presentation/legal_document_page.dart';

const _guardianConsentText =
    'I am the parent or legal guardian of this employee and I have read this contract in full. '
    'I agree to its terms on their behalf. This constitutes my electronic signature.';

/// pre-auth page a parent/guardian reaches by clicking the link emailed to
/// them — no login, gated entirely by the token in the URL. Reached only
/// via app.dart's _resolveInitialHome() cold-link carve-out, never via
/// in-app navigation, since a guardian never has an app session to push
/// from.
class GuardianSignPage extends StatefulWidget {
  const GuardianSignPage({required this.token, super.key});

  final String token;

  @override
  State<GuardianSignPage> createState() => _GuardianSignPageState();
}

class _GuardianSignPageState extends State<GuardianSignPage> {
  late Future<Map<String, dynamic>> _viewFuture;
  bool _isSubmitting = false;
  bool _justSigned = false;

  @override
  void initState() {
    super.initState();
    _viewFuture = ContractApiService.guardianView(token: widget.token);
  }

  Future<void> _submit(ContractSignature signature) async {
    setState(() => _isSubmitting = true);
    try {
      await ContractApiService.guardianSign(
        token: widget.token,
        method: signature.method,
        typedName: signature.typedName,
        drawingBase64: signature.drawingBase64,
        consentChecked: true,
        consentText: signature.consentText,
      );
      if (mounted) setState(() => _justSigned = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to sign: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [AppLogo(size: 22), SizedBox(width: 10), Text('Anchor')],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _viewFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.error.toString().replaceFirst('Exception: ', ''),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }

              final data = snapshot.data!;
              final employeeName = data['employee_name'] as String? ?? 'this employee';
              final companyName = data['company_name'] as String? ?? 'the company';
              final content = data['content'] as String? ?? '';
              final alreadySigned = _justSigned || (data['already_signed'] as bool? ?? false);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$employeeName's employment contract with $companyName",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    LegalDocumentBody(content: content),
                    const SizedBox(height: 24),
                    if (alreadySigned)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Thank you — this has already been signed.'),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ContractSignatureForm(
                            consentText: _guardianConsentText,
                            isSubmitting: _isSubmitting,
                            onSubmit: _submit,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
