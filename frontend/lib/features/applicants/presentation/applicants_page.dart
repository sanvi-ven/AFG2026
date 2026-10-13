import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/applicant_service.dart';
import '../../../models/applicant.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only inbox of job applications from the business website's
/// careers page — same layout idea as RequestsPage: open applications on
/// top, everything already hired/declined folded underneath
class ApplicantsPage extends StatelessWidget {
  const ApplicantsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Applicants',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.applicants,
      body: StreamBuilder<List<Applicant>>(
        stream: ApplicantService.watchAllApplicants(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load applications.'));
          }
          final applicants = snapshot.data ?? const <Applicant>[];
          if (applicants.isEmpty) {
            return const Center(child: Text('No job applications yet.'));
          }
          final open = applicants.where((a) => a.isOpen).toList();
          final closed = applicants.where((a) => !a.isOpen).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final applicant in open) _ApplicantCard(applicant: applicant),
              if (closed.isNotEmpty) ...[
                const SizedBox(height: 4),
                ExpansionTile(
                  title: Text('Hired / declined (${closed.length})'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  children: [for (final applicant in closed) _ApplicantCard(applicant: applicant)],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.applicant});

  final Applicant applicant;

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
    }
  }

  Future<void> _editNotes(BuildContext context) async {
    final controller = TextEditingController(text: applicant.ownerNotes);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Interview notes, follow-ups...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await ApplicantService.updateNotes(applicantId: applicant.id, notes: controller.text);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete application?'),
        content: Text("This permanently removes ${applicant.name}'s application from Anchor."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await ApplicantService.deleteApplicant(applicant.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <(String, String)>[
      ("Driver's license", applicant.driversLicense),
      ('Vehicle', applicant.vehicleInfo),
      ('Landscaping experience', applicant.experience),
      ('Experience details', applicant.experienceDetails),
      ('Availability', applicant.availability),
      ('OK outdoors & lifting 50 lbs', applicant.physicalCapability),
    ].where((row) => row.$2.isNotEmpty).toList();
    final phone = applicant.phone.replaceAll(RegExp(r'[^\d+]'), '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(applicant.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(DateFormat('MMM d, yyyy').format(applicant.createdAt)),
              ],
            ),
            const SizedBox(height: 4),
            Text([applicant.email, applicant.phone].where((v) => v.isNotEmpty).join(' · ')),
            if (applicant.address.isNotEmpty) Text(applicant.address),
            const SizedBox(height: 8),
            for (final (label, value) in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: value),
                  ]),
                ),
              ),
            if (applicant.ownerNotes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Notes: ${applicant.ownerNotes}', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: ApplicantStatus.all.contains(applicant.status) ? applicant.status : ApplicantStatus.newApplicant,
                  items: [
                    for (final status in ApplicantStatus.all)
                      DropdownMenuItem(value: status, child: Text(ApplicantStatus.label(status))),
                  ],
                  onChanged: (status) {
                    if (status != null && status != applicant.status) {
                      ApplicantService.updateStatus(applicantId: applicant.id, status: status);
                    }
                  },
                ),
                if (phone.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () => _open(context, Uri(scheme: 'tel', path: phone)),
                    icon: const Icon(Icons.call_outlined, size: 16),
                    label: const Text('Call'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _open(context, Uri(scheme: 'sms', path: phone)),
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    label: const Text('Text'),
                  ),
                ],
                if (applicant.email.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _open(context, Uri(scheme: 'mailto', path: applicant.email)),
                    icon: const Icon(Icons.email_outlined, size: 16),
                    label: const Text('Email'),
                  ),
                if (applicant.resumeUrl.startsWith('https://'))
                  FilledButton.icon(
                    onPressed: () => _open(context, Uri.parse(applicant.resumeUrl)),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Resume'),
                  ),
                TextButton.icon(
                  onPressed: () => _editNotes(context),
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('Notes'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
