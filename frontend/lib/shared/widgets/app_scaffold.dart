//made with help of chatgpt: create a reusable app scaffold for a flutter business app that accepts title, role, selectedRoute, body, authToken

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/app_router.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/services/owner_settings_service.dart';
import '../../core/state/client_session.dart';
import '../../models/client_profile.dart';
import '../../models/owner_settings.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.role,
    required this.selectedRoute,
    required this.body,
    this.authToken,
    super.key,
  });

  final String title;
  final String role;
  final String selectedRoute;
  final Widget body;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    final items = _navItems(role);
    final selectedIndex = items.indexWhere((item) => item.route == selectedRoute);

    void onDestinationSelected(int index) {
      final destination = items[index].route;
      if (destination != selectedRoute) {
        Navigator.pushReplacementNamed(
          context,
          destination,
          arguments: {'role': role, 'authToken': authToken},
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final showClientSettings = role == 'client';
        final showOwnerSettings = role == 'owner';
        final showSettings = showClientSettings || showOwnerSettings;

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
                      if (showSettings) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Settings'),
                          subtitle: showClientSettings
                              ? ValueListenableBuilder<ClientProfile?>(
                                  valueListenable: ClientSession.profile,
                                  builder: (context, profile, _) {
                                    return Text(profile?.email ?? 'Update your profile');
                                  },
                                )
                              : const Text('Update business details'),
                          onTap: () => _openSettingsDialog(context),
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
            actions: showSettings
                ? [
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => _openSettingsDialog(context),
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

  Future<void> _openSettingsDialog(BuildContext context) async {
    if (role == 'owner') {
      await _openOwnerSettingsDialog(context);
      return;
    }

    await _openClientSettingsDialog(context);
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

  Future<void> _openOwnerSettingsDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final settings = await OwnerSettingsService.fetch();
      if (!context.mounted) {
        return;
      }

      final saved = await showDialog<OwnerSettings>(
        context: context,
        builder: (_) => _OwnerSettingsDialog(initialSettings: settings),
      );

      if (saved != null && context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Business settings updated.')));
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('Failed to load owner settings: $error')));
    }
  }

  List<_NavItem> _navItems(String role) {
    final common = <_NavItem>[
      const _NavItem(label: 'Anchor', route: AppRouter.dashboard, icon: Icons.dashboard),
      const _NavItem(label: 'Appointments', route: AppRouter.appointments, icon: Icons.calendar_month),
      const _NavItem(label: 'Invoices', route: AppRouter.invoices, icon: Icons.receipt_long),
      const _NavItem(label: 'Estimates', route: AppRouter.estimates, icon: Icons.request_quote_outlined),
      const _NavItem(label: 'Announcements', route: AppRouter.messages, icon: Icons.chat_bubble_outline),
    ];

    if (role == 'owner') {
      return common;
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
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _addressController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.initialProfile.firstName);
    _lastNameController = TextEditingController(text: widget.initialProfile.lastName);
    _phoneNumberController = TextEditingController(text: widget.initialProfile.phoneNumber);
    _addressController = TextEditingController(text: widget.initialProfile.address);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
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
          phoneNumber: _phoneNumberController.text,
          address: _addressController.text,
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
                  controller: _phoneNumberController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
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

class _OwnerSettingsDialog extends StatefulWidget {
  const _OwnerSettingsDialog({required this.initialSettings});

  final OwnerSettings initialSettings;

  @override
  State<_OwnerSettingsDialog> createState() => _OwnerSettingsDialogState();
}

class _OwnerSettingsDialogState extends State<_OwnerSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyNameController;
  late final TextEditingController _addressController;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  bool _isPickingLogo = false;
  String? _logoUrl;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoMimeType;

  @override
  void initState() {
    super.initState();
    _companyNameController = TextEditingController(text: widget.initialSettings.companyName);
    _addressController = TextEditingController(text: widget.initialSettings.address);
    _logoUrl = widget.initialSettings.logoUrl;
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      setState(() => _isPickingLogo = true);
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) {
        return;
      }

      final fileName = picked.name;
      if (!_isSupportedImageFile(fileName)) {
        throw Exception('Unsupported logo format. Use PNG, JPG/JPEG, WEBP, or GIF.');
      }

      final bytes = await picked.readAsBytes();
      final mimeType = _inferMimeType(picked.name);

      if (!mounted) {
        return;
      }
      setState(() {
        _pendingLogoBytes = bytes;
        _pendingLogoMimeType = mimeType;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select logo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingLogo = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      var nextLogoUrl = _logoUrl;
      final bytes = _pendingLogoBytes;
      final mimeType = _pendingLogoMimeType;
      String? nonBlockingUploadWarning;
      if (bytes != null && mimeType != null) {
        try {
          nextLogoUrl = await OwnerSettingsService.uploadLogo(bytes: bytes, mimeType: mimeType);
        } catch (error) {
          nonBlockingUploadWarning =
              'Logo was not updated (${error.toString().replaceFirst('Exception: ', '')}). Other settings were saved.';
        }
      }

      final settings = OwnerSettings(
        companyName: _companyNameController.text.trim(),
        address: _addressController.text.trim(),
        logoUrl: nextLogoUrl,
      );
      final saved = await OwnerSettingsService.save(settings);
      if (!mounted) {
        return;
      }
      if (nonBlockingUploadWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(nonBlockingUploadWarning)),
        );
      }
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save owner settings: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _inferMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  bool _isSupportedImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logoUrl;
    final localPreview = _pendingLogoBytes;
    const localFallbackLogo = 'assets/logos/logo.png';

    return AlertDialog(
      title: const Text('Owner Settings'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _companyNameController,
                  decoration: const InputDecoration(labelText: 'Company name'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Company name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Business address'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Business address is required' : null,
                ),
                const SizedBox(height: 16),
                const Text('Logo', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: logo == null || logo.trim().isEmpty
                      ? (localPreview == null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                localFallbackLogo,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Text('No logo uploaded'),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                localPreview,
                                fit: BoxFit.contain,
                              ),
                            ))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            logo,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Text('Unable to preview logo'),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                if (localPreview != null)
                  Text(
                    'Logo selected. It will upload when you tap Save.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (localPreview != null) const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isPickingLogo ? null : _pickLogo,
                      icon: _isPickingLogo
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(_isPickingLogo ? 'Selecting...' : 'Select logo'),
                    ),
                    TextButton(
                      onPressed: _isPickingLogo
                          ? null
                          : () {
                              setState(() {
                                _logoUrl = null;
                                _pendingLogoBytes = null;
                                _pendingLogoMimeType = null;
                              });
                            },
                      child: const Text('Remove logo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving || _isPickingLogo ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _isPickingLogo ? null : _save,
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
