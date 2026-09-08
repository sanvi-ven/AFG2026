import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

/// a draw-your-signature pad with Clear/Done actions, used by
/// ContractSignatureForm's "drawn" method. Wraps the `signature` package so
/// callers never touch SignatureController directly.
class SignaturePad extends StatefulWidget {
  const SignaturePad({required this.onDone, super.key});

  /// called with a PNG byte array once the signer taps Done with a
  /// non-empty drawing; never called for an empty pad.
  final ValueChanged<Uint8List> onDone;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  late final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_controller.isEmpty) return;
    final bytes = await _controller.toPngBytes();
    if (bytes != null) widget.onDone(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Signature(controller: _controller, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _controller.clear, child: const Text('Clear')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _done, child: const Text('Done')),
          ],
        ),
      ],
    );
  }
}
