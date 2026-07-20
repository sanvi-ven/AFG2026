import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/services/job_photo_upload_service.dart';
import '../../../models/equipment.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only create/edit form for a catalog item. In create mode the type
/// toggle picks Equipment vs Supply and reveals the type-specific fields; in
/// edit mode quantity is read-only (unit-count adjustment is Phase 2).
class EquipmentFormPage extends StatefulWidget {
  const EquipmentFormPage({
    required this.role,
    this.authToken,
    this.existingId,
    super.key,
  });

  final String role;
  final String? authToken;
  final String? existingId;

  @override
  State<EquipmentFormPage> createState() => _EquipmentFormPageState();
}

class _EquipmentFormPageState extends State<EquipmentFormPage> {
  final _formKey = GlobalKey<FormState>();

  /// minted up front so photos have a stable upload path before the doc is
  /// saved. In edit mode we overwrite it once the existing item loads.
  late String _equipmentId = EquipmentService.newEquipmentId();

  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitOfMeasureController = TextEditingController();
  final _lowStockThresholdController = TextEditingController();
  final _serviceIntervalController = TextEditingController();

  String _type = EquipmentType.equipment;
  List<String> _photoUrls = const [];
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  bool _isLoading = false;

  bool get _isEdit => widget.existingId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _equipmentId = widget.existingId!;
      _loadExisting();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitOfMeasureController.dispose();
    _lowStockThresholdController.dispose();
    _serviceIntervalController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoading = true);
    try {
      final item =
          await EquipmentService.watchOne(widget.existingId!).first;
      if (item == null || !mounted) return;
      setState(() {
        _type = item.type;
        _nameController.text = item.name;
        _quantityController.text = item.quantity.toString();
        _unitOfMeasureController.text = item.unitOfMeasure;
        _lowStockThresholdController.text =
            item.lowStockThreshold?.toString() ?? '';
        _serviceIntervalController.text =
            item.defaultServiceIntervalDays?.toString() ?? '';
        _photoUrls = List<String>.from(item.photoUrls);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load item: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPhoto() async {
    setState(() => _isUploadingPhoto = true);
    try {
      final url = await JobPhotoUploadService.pickAndUploadEquipmentPhoto(
          equipmentId: _equipmentId);
      if (url != null && mounted) {
        setState(() => _photoUrls = [..._photoUrls, url]);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _removePhoto(String url) {
    setState(() => _photoUrls = _photoUrls.where((u) => u != url).toList());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final threshold = int.tryParse(_lowStockThresholdController.text.trim());
      final serviceInterval =
          int.tryParse(_serviceIntervalController.text.trim());

      if (_isEdit) {
        await EquipmentService.updateCatalogFields(
          id: _equipmentId,
          name: name,
          photoUrls: _photoUrls,
          unitOfMeasure: _type == EquipmentType.supply
              ? _unitOfMeasureController.text.trim()
              : null,
          lowStockThreshold:
              _type == EquipmentType.supply ? threshold : null,
          defaultServiceIntervalDays:
              _type == EquipmentType.equipment ? serviceInterval : null,
        );
      } else {
        final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
        await EquipmentService.createEquipment(
          id: _equipmentId,
          name: name,
          type: _type,
          photoUrls: _photoUrls,
          quantity: quantity,
          unitOfMeasure: _type == EquipmentType.supply
              ? _unitOfMeasureController.text.trim()
              : '',
          lowStockThreshold: _type == EquipmentType.supply ? threshold : null,
          defaultServiceIntervalDays:
              _type == EquipmentType.equipment ? serviceInterval : null,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save equipment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEdit ? 'Edit Equipment' : 'Add Equipment',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: AppRouter.equipmentCatalog,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildFormFields(context),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildFormFields(BuildContext context) {
    final isSupply = _type == EquipmentType.supply;
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
            labelText: 'Name', border: OutlineInputBorder()),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Name is required' : null,
      ),
      const SizedBox(height: 12),
      // type is fixed once created — switching type would invalidate units
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
              value: EquipmentType.equipment, label: Text('Equipment')),
          ButtonSegment(value: EquipmentType.supply, label: Text('Supply')),
        ],
        selected: {_type},
        onSelectionChanged: _isEdit
            ? null
            : (selection) => setState(() => _type = selection.first),
      ),
      const SizedBox(height: 12),
      if (_isEdit)
        // quantity/unit-count changes are Phase 2 — show read-only here
        InputDecorator(
          decoration: const InputDecoration(
              labelText: 'Quantity', border: OutlineInputBorder()),
          child: Text(_quantityController.text),
        )
      else
        TextFormField(
          controller: _quantityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: isSupply ? 'On-hand quantity' : 'Number of units',
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            final parsed = int.tryParse((value ?? '').trim());
            if (parsed == null || parsed < 1) {
              return 'Enter a whole number of 1 or more';
            }
            return null;
          },
        ),
      const SizedBox(height: 12),
      if (isSupply) ...[
        TextFormField(
          controller: _unitOfMeasureController,
          decoration: const InputDecoration(
            labelText: 'Unit of measure (e.g. boxes, L)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _lowStockThresholdController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Low-stock threshold (optional)',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return null;
            final parsed = int.tryParse(text);
            if (parsed == null || parsed < 0) {
              return 'Enter a whole number of 0 or more';
            }
            return null;
          },
        ),
      ] else ...[
        TextFormField(
          controller: _serviceIntervalController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default service interval (days, optional)',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return null;
            final parsed = int.tryParse(text);
            if (parsed == null || parsed < 1) {
              return 'Enter a whole number of 1 or more';
            }
            return null;
          },
        ),
      ],
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Photos', style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: 8),
      if (_photoUrls.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in _photoUrls)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      url,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey.shade200,
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, size: 20),
                      color: Colors.black54,
                      onPressed: () => _removePhoto(url),
                    ),
                  ),
                ],
              ),
          ],
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _isUploadingPhoto ? null : _addPhoto,
          icon: _isUploadingPhoto
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add Photo'),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _isSaving ? null : _save,
        child: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_isEdit ? 'Save Changes' : 'Create'),
      ),
    ];
  }
}
