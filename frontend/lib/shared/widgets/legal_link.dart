import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';

/// tappable inline link to a legal document (privacy policy, terms of
/// service, employee data notice) — used inline in signup/settings text so
/// callers don't each re-implement navigation + underline styling.
class LegalLink extends StatelessWidget {
  const LegalLink({required this.label, required this.documentId, super.key});

  final String label;
  final String documentId;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRouter.legalDocument,
        arguments: {'documentId': documentId},
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
