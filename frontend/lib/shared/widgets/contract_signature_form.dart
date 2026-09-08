import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/employment_contract.dart';
import 'signature_pad.dart';

/// shared signing widget for both the original contract signature and an
/// amendment's initials, used by the authenticated employee (via
/// ContractPage) and the pre-auth guardian (via GuardianSignPage) alike.
/// Either typed-name+checkbox or a drawn signature — signer's choice, not
/// both required (see the approved plan's "Signature strength" decision).
class ContractSignatureForm extends StatefulWidget {
  const ContractSignatureForm({
    required this.consentText,
    required this.onSubmit,
    this.isSubmitting = false,
    super.key,
  });

  /// the exact consent checkbox wording — frozen onto the resulting
  /// ContractSignature so it stays accurate even if this copy changes later
  final String consentText;
  final ValueChanged<ContractSignature> onSubmit;
  final bool isSubmitting;

  @override
  State<ContractSignatureForm> createState() => _ContractSignatureFormState();
}

enum _Method { typed, drawn }

class _ContractSignatureFormState extends State<ContractSignatureForm> {
  _Method _method = _Method.typed;
  final _typedNameController = TextEditingController();
  bool _agreed = false;
  String? _error;

  @override
  void dispose() {
    _typedNameController.dispose();
    super.dispose();
  }

  void _submitTyped() {
    if (!_agreed) {
      setState(() => _error = 'Please check the box to confirm you agree.');
      return;
    }
    final name = _typedNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Type your full legal name.');
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(ContractSignature(
      method: ContractSignatureMethod.typed,
      typedName: name,
      consentText: widget.consentText,
      signedAt: DateTime.now(),
    ));
  }

  void _submitDrawn(List<int> pngBytes) {
    if (!_agreed) {
      setState(() => _error = 'Please check the box to confirm you agree.');
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(ContractSignature(
      method: ContractSignatureMethod.drawn,
      drawingBase64: base64Encode(pngBytes),
      consentText: widget.consentText,
      signedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Method>(
          segments: const [
            ButtonSegment(value: _Method.typed, label: Text('Type name')),
            ButtonSegment(value: _Method.drawn, label: Text('Draw signature')),
          ],
          selected: {_method},
          onSelectionChanged: widget.isSubmitting
              ? null
              : (selection) => setState(() => _method = selection.first),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreed,
              onChanged: widget.isSubmitting
                  ? null
                  : (value) => setState(() => _agreed = value ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.consentText, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_method == _Method.typed) ...[
          TextField(
            controller: _typedNameController,
            enabled: !widget.isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Full legal name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.isSubmitting ? null : _submitTyped,
            child: widget.isSubmitting
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign'),
          ),
        ] else
          SignaturePad(onDone: (bytes) => _submitDrawn(bytes)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}
