//made with help of chatgpt 4.0: create a reusable app scaffold for a flutter business app that accepts title, role, selectedRoute, body, authToken

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/app_router.dart';
import '../../core/services/address_autocomplete_service.dart';
import '../../core/services/client_auth_service.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/services/employee_auth_service.dart';
import '../../core/services/employee_profile_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/owner_settings_service.dart';
import '../../core/services/session_persistence_service.dart';
import '../../core/services/sidebar_preference_service.dart';
import '../../core/state/client_session.dart';
import '../../core/state/employee_session.dart';
import '../../core/state/owner_session.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../models/app_notification.dart';
import '../../models/client_profile.dart';
import '../../models/employee_profile.dart';
import '../../models/owner_settings.dart';
import 'app_logo.dart';

/// reusable app scaffold with navigation, sidebar, and header for business app
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
    final selectedIndex =
        items.indexWhere((item) => item.route == selectedRoute);

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
        final showEmployeeSettings = role == 'employee';
        final showSettings =
            showClientSettings || showOwnerSettings || showEmployeeSettings;

        if (isWide) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 24),
                  const SizedBox(width: 10),
                  Text(title),
                ],
              ),
              actions: [_NotificationBell(role: role, authToken: authToken)],
            ),
            body: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Column(
                    children: [
                      Expanded(
                        child: role == 'owner'
                            ? _OwnerGroupedSidebar(
                                items: items,
                                selectedRoute: selectedRoute,
                                onSelectRoute: (route) => onDestinationSelected(
                                    items.indexWhere((i) => i.route == route)),
                              )
                            : NavigationRail(
                                selectedIndex:
                                    selectedIndex < 0 ? 0 : selectedIndex,
                                onDestinationSelected: onDestinationSelected,
                                labelType: NavigationRailLabelType.all,
                                destinations: [
                                  for (final item in items)
                                    NavigationRailDestination(
                                      icon: item.route == AppRouter.dashboard
                                          ? const AppLogo(
                                              size: 20,
                                              fallbackIcon: Icons.dashboard)
                                          : Icon(item.icon),
                                      selectedIcon: item.route ==
                                              AppRouter.dashboard
                                          ? const AppLogo(
                                              size: 22,
                                              fallbackIcon: Icons.dashboard)
                                          : Icon(item.icon),
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

        final textScaleFactor =
            _getResponsiveTextScaleFactor(constraints.maxWidth, items.length);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 22),
                const SizedBox(width: 10),
                Text(title),
              ],
            ),
            actions: [
              _NotificationBell(role: role, authToken: authToken),
              if (showSettings)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _openSettingsDialog(context),
                ),
            ],
          ),
          body: body,
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.apply(
                    fontSizeFactor: textScaleFactor,
                  ),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final item in items)
                  NavigationDestination(
                    icon: item.route == AppRouter.dashboard
                        ? const AppLogo(size: 20, fallbackIcon: Icons.dashboard)
                        : Icon(item.icon),
                    selectedIcon: item.route == AppRouter.dashboard
                        ? const AppLogo(size: 22, fallbackIcon: Icons.dashboard)
                        : Icon(item.icon),
                    label: item.label,
                  ),
              ],
            ),
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
    if (role == 'employee') {
      await _openEmployeeSettingsDialog(context);
      return;
    }

    await _openClientSettingsDialog(context);
  }

  Future<void> _openEmployeeSettingsDialog(BuildContext context) async {
    final currentProfile = EmployeeSession.profile.value;
    if (currentProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in before editing settings.')),
      );
      return;
    }

    final saved = await showDialog<EmployeeProfile>(
      context: context,
      builder: (_) => _EmployeeSettingsDialog(initialProfile: currentProfile),
    );

    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    }
  }

  Future<void> _openClientSettingsDialog(BuildContext context) async {
    final currentProfile = ClientSession.profile.value;
    if (currentProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Log in with your email before editing settings.')),
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
        messenger.showSnackBar(
            const SnackBar(content: Text('Business settings updated.')));
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
          SnackBar(content: Text('Failed to load owner settings: $error')));
    }
  }

  List<_NavItem> _navItems(String role) {
    if (role == 'employee') {
      return const <_NavItem>[
        _NavItem(
            label: 'Anchor', route: AppRouter.dashboard, icon: Icons.dashboard),
        _NavItem(
            label: 'My Jobs',
            route: AppRouter.myJobs,
            icon: Icons.work_outline),
        _NavItem(
            label: 'My Hours',
            route: AppRouter.myHours,
            icon: Icons.access_time),
        _NavItem(
            label: 'Equipment',
            route: AppRouter.equipmentCatalog,
            icon: Icons.build_outlined),
      ];
    }

    final common = <_NavItem>[
      const _NavItem(
          label: 'Anchor', route: AppRouter.dashboard, icon: Icons.dashboard),
      const _NavItem(
          label: 'Estimates',
          route: AppRouter.estimates,
          icon: Icons.request_quote_outlined),
      const _NavItem(
          label: 'Appointments',
          route: AppRouter.appointments,
          icon: Icons.calendar_month),
      const _NavItem(
          label: 'Invoices',
          route: AppRouter.invoices,
          icon: Icons.receipt_long),
      const _NavItem(
          label: 'Messages',
          route: AppRouter.messages,
          icon: Icons.chat_bubble_outline),
    ];

    if (role == 'owner') {
      return const [
        _NavItem(
            label: 'Anchor', route: AppRouter.dashboard, icon: Icons.dashboard),
        _NavItem(
            label: 'Requests',
            route: AppRouter.requests,
            icon: Icons.inbox_outlined),
        _NavItem(
            label: 'Estimates',
            route: AppRouter.estimates,
            icon: Icons.request_quote_outlined),
        _NavItem(
            label: 'Appointments',
            route: AppRouter.appointments,
            icon: Icons.calendar_month),
        _NavItem(
            label: 'Invoices',
            route: AppRouter.invoices,
            icon: Icons.receipt_long),
        _NavItem(
            label: 'Messages',
            route: AppRouter.messages,
            icon: Icons.chat_bubble_outline),
        _NavItem(
            label: 'Clients',
            route: AppRouter.clients,
            icon: Icons.people_outline),
        _NavItem(
            label: 'Team',
            route: AppRouter.teamAdmin,
            icon: Icons.groups_outlined),
        _NavItem(
            label: 'Reports',
            route: AppRouter.reports,
            icon: Icons.bar_chart_outlined),
        _NavItem(
          label: "Today's Route",
          route: AppRouter.todaysRoute,
          icon: Icons.alt_route_outlined,
        ),
        _NavItem(
            label: 'Equipment',
            route: AppRouter.equipmentCatalog,
            icon: Icons.build_outlined),
      ];
    }

    return common;
  }

  /// Calculates responsive text scale factor for navigation bar based on screen width
  /// On narrow screens, reduces text size to prevent overflow and squishing
  double _getResponsiveTextScaleFactor(double screenWidth, int itemCount) {
    // Each item gets roughly equal horizontal space
    final spacePerItem = screenWidth / itemCount;

    // Scale factor (1.0 = 100% = normal size)
    // Aggressive early shrinking to prevent wrapping on mobile
    if (spacePerItem < 50) {
      return 0.55;
    } else if (spacePerItem < 60) {
      return 0.60;
    } else if (spacePerItem < 70) {
      return 0.67;
    } else if (spacePerItem < 80) {
      return 0.72;
    } else if (spacePerItem < 95) {
      return 0.82;
    } else if (spacePerItem < 100) {
      return 0.88;
    } else if (spacePerItem < 110) {
      return 0.94;
    }

    return 1.0; // Full size for wider screens
  }
}

/// a collapsible category in the owner sidebar
class _SidebarGroup {
  const _SidebarGroup({
    required this.key,
    required this.label,
    required this.icon,
    required this.routes,
  });

  final String key;
  final String label;
  final IconData icon;
  final Set<String> routes;
}

/// owner sidebar's collapsible categories, in the order their header should
/// appear (each rendered at the position of its first member route)
const _ownerSidebarGroups = <_SidebarGroup>[
  _SidebarGroup(
    key: 'workflow',
    label: 'Workflow',
    icon: Icons.work_outline,
    routes: {
      AppRouter.requests,
      AppRouter.estimates,
      AppRouter.appointments,
      AppRouter.invoices,
    },
  ),
  _SidebarGroup(
    key: 'contacts',
    label: 'Contacts',
    icon: Icons.people_alt_outlined,
    routes: {AppRouter.messages, AppRouter.clients},
  ),
];

/// owner-only wide-layout sidebar: same nav items as [NavigationRail] used
/// elsewhere, but related routes are folded under collapsible group headers
/// (see [_ownerSidebarGroups]) to cut down the owner's flat item count.
class _OwnerGroupedSidebar extends StatefulWidget {
  const _OwnerGroupedSidebar({
    required this.items,
    required this.selectedRoute,
    required this.onSelectRoute,
  });

  final List<_NavItem> items;
  final String selectedRoute;
  final void Function(String route) onSelectRoute;

  @override
  State<_OwnerGroupedSidebar> createState() => _OwnerGroupedSidebarState();
}

class _OwnerGroupedSidebarState extends State<_OwnerGroupedSidebar> {
  late final Map<String, bool> _expanded = {
    for (final group in _ownerSidebarGroups)
      group.key: group.routes.contains(widget.selectedRoute),
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    for (final group in _ownerSidebarGroups) {
      final stored = await SidebarPreferenceService.getGroupExpanded(group.key);
      if (stored == null || !mounted) continue;
      setState(() => _expanded[group.key] =
          stored || group.routes.contains(widget.selectedRoute));
    }
  }

  void _toggleGroup(String key) {
    final next = !(_expanded[key] ?? false);
    setState(() => _expanded[key] = next);
    SidebarPreferenceService.setGroupExpanded(key, next);
  }

  _SidebarGroup? _groupForRoute(String route) {
    for (final group in _ownerSidebarGroups) {
      if (group.routes.contains(route)) return group;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final insertedGroupKeys = <String>{};

    for (final item in widget.items) {
      final group = _groupForRoute(item.route);
      if (group != null) {
        if (insertedGroupKeys.contains(group.key)) continue;
        insertedGroupKeys.add(group.key);
        final expanded = _expanded[group.key] ?? false;
        rows.add(_GroupHeaderTile(
          label: group.label,
          icon: group.icon,
          expanded: expanded,
          onTap: () => _toggleGroup(group.key),
        ));
        if (expanded) {
          for (final groupedItem
              in widget.items.where((i) => group.routes.contains(i.route))) {
            rows.add(_SidebarRow(
              item: groupedItem,
              selected: groupedItem.route == widget.selectedRoute,
              indent: true,
              onTap: () => widget.onSelectRoute(groupedItem.route),
            ));
          }
        }
        continue;
      }
      rows.add(_SidebarRow(
        item: item,
        selected: item.route == widget.selectedRoute,
        onTap: () => widget.onSelectRoute(item.route),
      ));
    }

    return ListView(children: rows);
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.item,
    required this.selected,
    required this.onTap,
    this.indent = false,
  });

  final _NavItem item;
  final bool selected;
  final bool indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16 : 0),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        leading: item.route == AppRouter.dashboard
            ? const AppLogo(size: 20, fallbackIcon: Icons.dashboard)
            : Icon(item.icon),
        title: Text(item.label, style: const TextStyle(fontSize: 13)),
        onTap: onTap,
      ),
    );
  }
}

class _GroupHeaderTile extends StatelessWidget {
  const _GroupHeaderTile({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Icon(Icons.expand_more),
      ),
      onTap: onTap,
    );
  }
}

class _NavItem {
  const _NavItem(
      {required this.label, required this.route, required this.icon});

  final String label;
  final String route;
  final IconData icon;
}

/// bell icon with an unread-count badge, opening the notifications inbox
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.role, this.authToken});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    final recipientId = recipientIdFor(role);
    if (recipientId == null) return const SizedBox.shrink();

    return StreamBuilder<List<AppNotification>>(
      stream: NotificationService.watchForRecipient(role, recipientId),
      builder: (context, snapshot) {
        final unreadCount = (snapshot.data ?? const <AppNotification>[])
            .where((n) => !n.isRead)
            .length;

        return IconButton(
          tooltip: 'Notifications',
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () => Navigator.pushNamed(
            context,
            AppRouter.notifications,
            arguments: {'role': role, 'authToken': authToken},
          ),
        );
      },
    );
  }
}

Future<void> _confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Log out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  ClientSession.clear();
  OwnerSession.clear();
  await SessionPersistenceService.clearSession();
  if (!context.mounted) return;

  Navigator.of(context)
      .pushNamedAndRemoveUntil(AppRouter.login, (route) => false);
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
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmNewPasswordController =
      TextEditingController();
  bool _isSaving = false;
  bool _isLoadingAddressSuggestions = false;
  List<String> _addressSuggestions = const [];
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _firstNameController =
        TextEditingController(text: widget.initialProfile.firstName);
    _lastNameController =
        TextEditingController(text: widget.initialProfile.lastName);
    _phoneNumberController =
        TextEditingController(text: widget.initialProfile.phoneNumber);
    _addressController =
        TextEditingController(text: widget.initialProfile.address);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    _addressDebounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    _addressDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _addressSuggestions = const [];
        _isLoadingAddressSuggestions = false;
      });
      return;
    }
    setState(() => _isLoadingAddressSuggestions = true);
    _addressDebounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await AddressAutocompleteService.search(query);
      if (!mounted) return;
      setState(() {
        _addressSuggestions = suggestions;
        _isLoadingAddressSuggestions = false;
      });
    });
  }

  void _pickAddressSuggestion(String value) {
    _addressController.text = value;
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final shouldChangePassword = _oldPasswordController.text.isNotEmpty ||
          _newPasswordController.text.isNotEmpty ||
          _confirmNewPasswordController.text.isNotEmpty;

      if (shouldChangePassword) {
        await ClientAuthService.changePassword(
          email: widget.initialProfile.email,
          oldPassword: _oldPasswordController.text,
          newPassword: _newPasswordController.text,
        );
      }

      final nextProfile = widget.initialProfile.copyWith(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phoneNumber: _phoneNumberController.text,
        address: _addressController.text,
      );
      final updated = await ClientProfileService.save(nextProfile);
      ClientSession.setProfile(updated);
      await SessionPersistenceService.saveClientSession(updated);
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'First name is required'
                      : null,
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
                  decoration: InputDecoration(
                    labelText: 'Address',
                    suffixIcon: _isLoadingAddressSuggestions
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _onAddressChanged,
                ),
                if (_addressSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _addressSuggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _addressSuggestions[index];
                          return ListTile(
                            dense: true,
                            title: Text(suggestion),
                            onTap: () => _pickAddressSuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Change password',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password'),
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    if ((value ?? '').isEmpty) {
                      return 'Current password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    final input = value ?? '';
                    if (input.isEmpty) {
                      return 'New password is required';
                    }
                    if (input.length < 8) {
                      return 'New password must be at least 8 characters';
                    }
                    if (input == _oldPasswordController.text) {
                      return 'New password must be different';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmNewPasswordController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    if ((value ?? '').isEmpty) {
                      return 'Confirm your new password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'New passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : () => _confirmLogout(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
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

class _EmployeeSettingsDialog extends StatefulWidget {
  const _EmployeeSettingsDialog({required this.initialProfile});

  final EmployeeProfile initialProfile;

  @override
  State<_EmployeeSettingsDialog> createState() =>
      _EmployeeSettingsDialogState();
}

class _EmployeeSettingsDialogState extends State<_EmployeeSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneNumberController;
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmNewPasswordController =
      TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController =
        TextEditingController(text: widget.initialProfile.firstName);
    _lastNameController =
        TextEditingController(text: widget.initialProfile.lastName);
    _phoneNumberController =
        TextEditingController(text: widget.initialProfile.phoneNumber);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneNumberController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final shouldChangePassword = _oldPasswordController.text.isNotEmpty ||
          _newPasswordController.text.isNotEmpty ||
          _confirmNewPasswordController.text.isNotEmpty;

      if (shouldChangePassword) {
        await EmployeeAuthService.changePassword(
          email: widget.initialProfile.email,
          oldPassword: _oldPasswordController.text,
          newPassword: _newPasswordController.text,
        );
      }

      final nextProfile = widget.initialProfile.copyWith(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phoneNumber: _phoneNumberController.text,
      );
      final updated = await EmployeeProfileService.save(nextProfile);
      EmployeeSession.setProfile(updated);
      await SessionPersistenceService.saveEmployeeSession(updated);
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
      title: const Text('Employee Settings'),
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'First name is required'
                      : null,
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
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Change password',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password'),
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    if ((value ?? '').isEmpty) {
                      return 'Current password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    final input = value ?? '';
                    if (input.isEmpty) {
                      return 'New password is required';
                    }
                    if (input.length < 8) {
                      return 'New password must be at least 8 characters';
                    }
                    if (input == _oldPasswordController.text) {
                      return 'New password must be different';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmNewPasswordController,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                  obscureText: true,
                  validator: (value) {
                    final hasAnyPasswordInput =
                        _oldPasswordController.text.isNotEmpty ||
                            _newPasswordController.text.isNotEmpty ||
                            _confirmNewPasswordController.text.isNotEmpty;
                    if (!hasAnyPasswordInput) {
                      return null;
                    }
                    if ((value ?? '').isEmpty) {
                      return 'Confirm your new password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'New passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : () => _confirmLogout(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
  late final TextEditingController _nextEstimateNumberController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _estimateFileNameTemplateController;
  late final TextEditingController _invoiceFileNameTemplateController;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  bool _isPickingLogo = false;
  // base64-encoded logo to save into Firestore
  String? _logoBase64;
  // raw bytes of a newly picked image — used only for the preview widget
  Uint8List? _pendingLogoBytes;

  @override
  void initState() {
    super.initState();
    _companyNameController =
        TextEditingController(text: widget.initialSettings.companyName);
    _addressController =
        TextEditingController(text: widget.initialSettings.address);
    _nextEstimateNumberController = TextEditingController(
        text: widget.initialSettings.nextEstimateNumber.toString());
    _phoneController =
        TextEditingController(text: widget.initialSettings.phone);
    _emailController =
        TextEditingController(text: widget.initialSettings.email);
    _estimateFileNameTemplateController = TextEditingController(
        text: widget.initialSettings.estimateFileNameTemplate);
    _invoiceFileNameTemplateController = TextEditingController(
        text: widget.initialSettings.invoiceFileNameTemplate);
    _logoBase64 = widget.initialSettings.logoBase64;
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _addressController.dispose();
    _nextEstimateNumberController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _estimateFileNameTemplateController.dispose();
    _invoiceFileNameTemplateController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      setState(() => _isPickingLogo = true);
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final encoded = base64Encode(bytes);

      if (!mounted) return;
      setState(() {
        _pendingLogoBytes = bytes;
        _logoBase64 = encoded;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select logo: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPickingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final settings = OwnerSettings(
        companyName: _companyNameController.text.trim(),
        address: _addressController.text.trim(),
        logoBase64: _logoBase64,
        nextEstimateNumber:
            int.tryParse(_nextEstimateNumberController.text.trim()) ??
                widget.initialSettings.nextEstimateNumber,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        estimateFileNameTemplate:
            _estimateFileNameTemplateController.text.trim().isEmpty
                ? 'estimate_{EstimateNumber}'
                : _estimateFileNameTemplateController.text.trim(),
        invoiceFileNameTemplate:
            _invoiceFileNameTemplateController.text.trim().isEmpty
                ? 'invoice_{InvoiceNumber}'
                : _invoiceFileNameTemplateController.text.trim(),
      );
      final saved = await OwnerSettingsService.save(settings);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save owner settings: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBase64 = _logoBase64 != null && _logoBase64!.isNotEmpty;
    final hasPending = _pendingLogoBytes != null;

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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Company name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration:
                      const InputDecoration(labelText: 'Business address'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Business address is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Business phone (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Business email (optional)'),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _estimateFileNameTemplateController,
                  decoration: const InputDecoration(
                    labelText: 'Estimate file name',
                    helperText:
                        'Placeholders: {CompanyName}, {EstimateNumber}, {ClientName}, {Date}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _invoiceFileNameTemplateController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice file name',
                    helperText:
                        'Placeholders: {CompanyName}, {InvoiceNumber}, {ClientName}, {Date}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nextEstimateNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Next quote number',
                    helperText:
                        'The next estimate created will use EST-#### starting from this number.',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed < 1) {
                      return 'Enter a whole number of 1 or more';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text('Logo',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasPending
                        ? Image.memory(_pendingLogoBytes!, fit: BoxFit.contain)
                        : hasBase64
                            ? Image.memory(base64Decode(_logoBase64!),
                                fit: BoxFit.contain)
                            : Image.asset(
                                AppLogo.assetPath,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Text('No logo uploaded'),
                              ),
                  ),
                ),
                const SizedBox(height: 8),
                if (hasPending) ...[
                  Text(
                    'Logo ready — will be saved when you tap Save.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
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
                      label:
                          Text(_isPickingLogo ? 'Selecting...' : 'Select logo'),
                    ),
                    TextButton(
                      onPressed: _isPickingLogo
                          ? null
                          : () {
                              setState(() {
                                _logoBase64 = null;
                                _pendingLogoBytes = null;
                              });
                            },
                      child: const Text('Remove logo'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving || _isPickingLogo
                        ? null
                        : () => _confirmLogout(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving || _isPickingLogo
              ? null
              : () => Navigator.of(context).pop(),
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
