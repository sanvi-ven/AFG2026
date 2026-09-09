import 'package:cloud_firestore/cloud_firestore.dart';

/// a prospective or existing client's work request, triaged by the owner
/// before it becomes an Estimate
class Request {
  const Request({
    required this.id,
    this.clientId,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.description,
    this.photoUrls = const [],
    required this.status,
    required this.createdAt,
    this.convertedEstimateId,
    this.declineReason = '',
    this.smsOptIn = false,
    this.preferredContact = PreferredContactMethod.email,
  });

  final String id;
  /// set only when submitted by a logged-in client; null for a brand-new
  /// public lead who doesn't have an account yet
  final String? clientId;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String description;
  final List<String> photoUrls;
  final String status;
  final DateTime createdAt;
  final String? convertedEstimateId;
  final String declineReason;

  /// explicit, unchecked-by-default opt-in to SMS about this request
  /// (received/declined), captured pre-auth on the public request form —
  /// unlike client/employee signup, a request submitted before this field
  /// existed simply has no opt-in (defaults false) and is never backfilled,
  /// since there's no prior verbal confirmation to fall back on the way
  /// there was for existing employees.
  final bool smsOptIn;

  /// how this requester would rather be reached back about this request —
  /// defaults to email for requests submitted before this field existed
  /// (email was already always collected/required, so it's the only safe
  /// default that doesn't imply a consent this app never captured).
  final String preferredContact;

  bool get isNew => status == RequestStatus.newRequest;
  bool get isConverted => status == RequestStatus.converted;
  bool get isDeclined => status == RequestStatus.declined;

  /// create request instance from firestore map data
  factory Request.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return Request(
      id: (map['id'] as String? ?? '').trim(),
      clientId: (map['clientId'] as String?)?.trim().isEmpty ?? true ? null : (map['clientId'] as String).trim(),
      name: (map['name'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim(),
      phone: (map['phone'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      photoUrls:
          (map['photoUrls'] as List<dynamic>? ?? const <dynamic>[]).whereType<String>().toList(),
      status: (map['status'] as String? ?? RequestStatus.newRequest).trim(),
      createdAt: readDate(map['createdAt']),
      convertedEstimateId: (map['convertedEstimateId'] as String?)?.trim(),
      declineReason: (map['declineReason'] as String? ?? '').trim(),
      smsOptIn: map['smsOptIn'] as bool? ?? false,
      preferredContact:
          (map['preferredContact'] as String? ?? PreferredContactMethod.email).trim(),
    );
  }

  /// convert request instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientId': clientId,
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'description': description,
      'photoUrls': photoUrls,
      'status': status,
      'createdAt': createdAt,
      'convertedEstimateId': convertedEstimateId,
      'declineReason': declineReason,
      'smsOptIn': smsOptIn,
      'preferredContact': preferredContact,
    };
  }
}

/// plain string constants for a requester's preferred contact method,
/// matching this codebase's RequestStatus/InvoiceStatus convention
class PreferredContactMethod {
  static const call = 'call';
  static const text = 'text';
  static const email = 'email';

  /// display order for the request form's dropdown — text first (the
  /// form's own default selection), then call, then email
  static const all = [text, call, email];

  static String label(String value) => switch (value) {
        call => 'Call',
        text => 'Text',
        _ => 'Email',
      };
}

/// plain string constants for request status, matching this codebase's
/// InvoiceStatus/ScheduledWorkStatus convention
class RequestStatus {
  static const newRequest = 'new';
  static const converted = 'converted';
  static const declined = 'declined';
}
