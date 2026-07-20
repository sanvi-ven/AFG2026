import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/equipment_service.dart';
import '../../../models/equipment.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'equipment_schedule_tab.dart';
import 'my_equipment_tab.dart';

/// Equipment area shell: a [DefaultTabController] with a "Catalog" tab (search /
/// filter / sort / list, plus owner-only "+ Add") and a role-conditional second
/// tab — "Schedule" for owners, "My Equipment" for employees.
class EquipmentCatalogPage extends StatelessWidget {
  const EquipmentCatalogPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  bool get _isOwner => role == 'owner';

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Equipment',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.equipmentCatalog,
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              tabs: [
                const Tab(
                    text: 'Catalog',
                    icon: Icon(Icons.inventory_2_outlined)),
                _isOwner
                    ? const Tab(
                        text: 'Schedule',
                        icon: Icon(Icons.event_note_outlined))
                    : const Tab(
                        text: 'My Equipment',
                        icon: Icon(Icons.handyman_outlined)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CatalogTab(role: role, authToken: authToken),
                  _isOwner
                      ? const EquipmentScheduleTab()
                      : const MyEquipmentTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// the browsable catalog list with search, type filter, show-archived, sort,
/// and (owner-only) add. Client-side filter/sort; tap a card to open detail.
class _CatalogTab extends StatefulWidget {
  const _CatalogTab({required this.role, this.authToken});

  final String role;
  final String? authToken;

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _typeFilter; // null = All
  String _sortBy = 'nameAsc';
  bool _showArchived = false;

  bool get _isOwner => widget.role == 'owner';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(String equipmentId) {
    Navigator.pushNamed(
      context,
      AppRouter.equipmentDetail,
      arguments: {
        'role': widget.role,
        'authToken': widget.authToken,
        'equipmentId': equipmentId,
      },
    );
  }

  void _openCreateForm() {
    Navigator.pushNamed(
      context,
      AppRouter.equipmentForm,
      arguments: {'role': widget.role, 'authToken': widget.authToken},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildControls(context),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<EquipmentItem>>(
            stream: EquipmentService.watchAll(includeArchived: _showArchived),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Failed to load equipment: ${snapshot.error}'));
              }

              final all = snapshot.data ?? const <EquipmentItem>[];
              final items = EquipmentService.filterAndSort(
                items: all,
                query: _query,
                typeFilter: _typeFilter,
                sortBy: _sortBy,
              );

              if (all.isEmpty) {
                return const Center(child: Text('No equipment yet.'));
              }
              if (items.isEmpty) {
                return const Center(
                    child: Text('No items match your filters.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _EquipmentCard(
                    item: item,
                    onTap: () => _openDetail(item.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search equipment',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (_isOwner) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openCreateForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _typeFilter == null,
                      onSelected: (_) => setState(() => _typeFilter = null),
                    ),
                    ChoiceChip(
                      label: const Text('Equipment'),
                      selected: _typeFilter == EquipmentType.equipment,
                      onSelected: (_) => setState(
                          () => _typeFilter = EquipmentType.equipment),
                    ),
                    ChoiceChip(
                      label: const Text('Supply'),
                      selected: _typeFilter == EquipmentType.supply,
                      onSelected: (_) =>
                          setState(() => _typeFilter = EquipmentType.supply),
                    ),
                    if (_isOwner)
                      FilterChip(
                        label: const Text('Show archived'),
                        selected: _showArchived,
                        onSelected: (value) =>
                            setState(() => _showArchived = value),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _sortBy,
                onChanged: (value) {
                  if (value != null) setState(() => _sortBy = value);
                },
                items: const [
                  DropdownMenuItem(value: 'nameAsc', child: Text('Name (A–Z)')),
                  DropdownMenuItem(
                      value: 'nameDesc', child: Text('Name (Z–A)')),
                  DropdownMenuItem(value: 'quantity', child: Text('Quantity')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.item, required this.onTap});

  final EquipmentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = item.photoUrls.isNotEmpty ? item.photoUrls.first : null;
    final quantityLabel = item.isSupply && item.unitOfMeasure.isNotEmpty
        ? '${item.quantity} ${item.unitOfMeasure}'
        : '${item.quantity}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumbnail(url: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _TypeBadge(type: item.type),
                        const SizedBox(width: 8),
                        Text('Qty: $quantityLabel'),
                        if (item.isLowStock) ...[
                          const SizedBox(width: 8),
                          const _LowStockBadge(),
                        ],
                        if (item.isArchived) ...[
                          const SizedBox(width: 8),
                          const _ArchivedBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    final placeholder = Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.build_outlined, color: Colors.grey.shade500),
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final isEquipment = type == EquipmentType.equipment;
    final label = isEquipment ? 'Equipment' : 'Supply';
    final color = isEquipment ? Colors.blue : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ArchivedBadge extends StatelessWidget {
  const _ArchivedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Archived',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _LowStockBadge extends StatelessWidget {
  const _LowStockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('Low stock',
          style: TextStyle(
              fontSize: 12,
              color: Colors.orange,
              fontWeight: FontWeight.w600)),
    );
  }
}
