import 'package:flutter/material.dart';

import '../../core/services/contract_service.dart';
import '../../models/employment_contract.dart';

/// small inline tag showing one employee's employment-contract status,
/// visual sibling to ArchivedBadge — grey "Not started," amber "Awaiting
/// your/guardian signature," green "Signed," blue "Paper contract on file."
class ContractStatusBadge extends StatelessWidget {
  const ContractStatusBadge({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EmploymentContract?>(
      stream: ContractService.watchContractForEmployee(employeeId),
      builder: (context, snapshot) {
        return _badge(context, snapshot.data);
      },
    );
  }

  Widget _badge(BuildContext context, EmploymentContract? contract) {
    final scheme = Theme.of(context).colorScheme;

    late final Color color;
    late final String label;
    late final IconData icon;

    if (contract == null) {
      color = scheme.outline;
      label = 'Not started';
      icon = Icons.description_outlined;
    } else {
      switch (contract.status) {
        case ContractStatus.uploadedSigned:
          color = Colors.blue;
          label = 'Paper contract on file';
          icon = Icons.file_present_outlined;
        case ContractStatus.fullySigned:
          color = Colors.green;
          label = 'Signed';
          icon = Icons.check_circle_outline;
        case ContractStatus.pendingGuardianSignature:
          color = Colors.amber.shade800;
          label = 'Awaiting guardian signature';
          icon = Icons.hourglass_bottom;
        default:
          color = Colors.amber.shade800;
          label = 'Awaiting their signature';
          icon = Icons.hourglass_empty;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
