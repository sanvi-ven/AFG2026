import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';

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

        if (isWide) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Row(
              children: [
                NavigationRail(
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
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(title)),
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

  List<_NavItem> _navItems(String role) {
    final common = <_NavItem>[
      const _NavItem(label: 'Dashboard', route: AppRouter.dashboard, icon: Icons.dashboard),
      const _NavItem(label: 'Appointments', route: AppRouter.appointments, icon: Icons.calendar_month),
      const _NavItem(label: 'Invoices', route: AppRouter.invoices, icon: Icons.receipt_long),
      const _NavItem(label: 'Messages', route: AppRouter.messages, icon: Icons.chat_bubble_outline),
      const _NavItem(label: 'Notify', route: AppRouter.notifications, icon: Icons.notifications_none),
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
