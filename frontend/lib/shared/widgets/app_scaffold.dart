import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/state/client_session.dart';
import '../../models/client_profile.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.role,
    required this.selectedRoute,
    required this.body,
    super.key,
  });

  final String title;
  final String role;
  final String selectedRoute;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final items = _navItems(role);
    final selectedIndex = items.indexWhere((item) => item.route == selectedRoute);

    void onDestinationSelected(int index) {
      final destination = items[index].route;
      if (destination != selectedRoute) {
        Navigator.pushReplacementNamed(context, destination, arguments: {'role': role});
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final showClientSettings = role == 'client';

        if (isWide) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Column(
                    children: [
                      Expanded(
                        child: NavigationRail(
                          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                          onDestinationSelected: onDestinationSelected,
                          labelType: NavigationRailLabelType.all,
                          destinations: [
                            for (final item in items)
                              NavigationRailDestination(
                                icon: Icon(item.icon),
                                label: Text(item.label),
                              ),
                          ],
                        ),
                      ),
                      if (showClientSettings) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Settings'),
                          subtitle: ValueListenableBuilder<ClientProfile?>(
                            valueListenable: ClientSession.profile,
                            builder: (context, profile, _) {
                              return Text(profile?.email ?? 'Update your profile');
                            },
                          ),
                          onTap: () => _openClientSettingsDialog(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: showClientSettings
                ? [
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => _openClientSettingsDialog(context),
                    ),
                  ]
                : null,
          ),
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final item in items)
                NavigationDestination(icon: Icon(item.icon), label: item.label),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openClientSettingsDialog(BuildContext context) async {
    final currentProfile = ClientSession.profile.value;
    if (currentProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in with your email before editing settings.')),
      );
      return;
    }

    final saved = await showDialog<ClientProfile>(
      context: context,
      builder: (_) => _ClientSettingsDialog(initialProfile: currentProfile),
    );

    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    }
  }

  List<_NavItem> _navItems(String role) {
    final common = <_NavItem>[
      const _NavItem(label: 'Anchor', route: AppRouter.dashboard, icon: Icons.dashboard),
      const _NavItem(label: 'Appointments', route: AppRouter.appointments, icon: Icons.calendar_month),
      const _NavItem(label: 'Invoices', route: AppRouter.invoices, icon: Icons.receipt_long),
      const _NavItem(label: 'Estimates', route: AppRouter.estimates, icon: Icons.request_quote_outlined),
      const _NavItem(label: 'Messages', route: AppRouter.messages, icon: Icons.chat_bubble_outline),
    ];

    if (role == 'owner') {
      return [
        ...common,
        const _NavItem(label: 'Availability', route: AppRouter.availability, icon: Icons.schedule),
      ];
    }

    return common;
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.route, required this.icon});

  final String label;
  final String route;
  final IconData icon;
}

class _ClientSettingsDialog extends StatefulWidget {
  const _ClientSettingsDialog({required this.initialProfile});

  final ClientProfile initialProfile;

  @override
  State<_ClientSettingsDialog> createState() => _ClientSettingsDialogState();
}

class _ClientSettingsDialogState extends State<_ClientSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _streetController;
  late final TextEditingController _countryController;
  late final TextEditingController _zipCodeController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.initialProfile.firstName);
    _lastNameController = TextEditingController(text: widget.initialProfile.lastName);
    _phoneController = TextEditingController(text: widget.initialProfile.phone);
    _streetController = TextEditingController(text: widget.initialProfile.street);
    _countryController = TextEditingController(text: widget.initialProfile.country);
    _zipCodeController = TextEditingController(text: widget.initialProfile.zipCode);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _countryController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await ClientProfileService.save(
        widget.initialProfile.copyWith(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          phone: _phoneController.text,
          street: _streetController.text,
          country: _countryController.text,
          zipCode: _zipCodeController.text,
        ),
      );
      ClientSession.setProfile(updated);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Client Settings'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: widget.initialProfile.email,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _firstNameController,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'First name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _streetController,
                  decoration: const InputDecoration(labelText: 'Street'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countryController,
                  decoration: const InputDecoration(labelText: 'Country'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _zipCodeController,
                  decoration: const InputDecoration(labelText: 'ZIP code'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
