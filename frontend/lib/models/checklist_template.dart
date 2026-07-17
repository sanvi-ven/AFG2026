import 'package:cloud_firestore/cloud_firestore.dart';

/// a saved, reusable checklist the owner can attach to a job (e.g. "Lawn
/// Mowing: mow / edge / blow / bag clippings") instead of relying on one
/// fixed completion form for every job type
class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<String> items;
  final DateTime createdAt;

  /// create template from firestore map data
  factory ChecklistTemplate.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return ChecklistTemplate(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      items: (map['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      createdAt: readDate(map['createdAt']),
    );
  }

  /// convert template to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'items': items,
      'createdAt': createdAt,
    };
  }
}

/// one checked-off item on a ScheduledWork's checklist — a snapshot of a
/// ChecklistTemplate's item label at the time the job was scheduled, so
/// editing the template later doesn't retroactively change jobs already
/// scheduled (same reasoning as InvoiceServiceItem snapshots on estimates)
class ChecklistItem {
  const ChecklistItem({required this.label, this.done = false});

  final String label;
  final bool done;

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      label: (map['label'] as String? ?? '').trim(),
      done: map['done'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {'label': label, 'done': done};
  }

  ChecklistItem copyWith({bool? done}) {
    return ChecklistItem(label: label, done: done ?? this.done);
  }
}
