import 'package:cloud_firestore/cloud_firestore.dart';

/// a job application, forwarded from the business website's careers page
/// (backend routes/integrations.py). Owner-only — see firestore.rules'
/// `applicants` match. The resume file itself stays on the website server;
/// [resumeUrl] links to the website's own password-protected admin page.
class Applicant {
  const Applicant({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.driversLicense,
    required this.vehicleInfo,
    required this.experience,
    required this.experienceDetails,
    required this.availability,
    required this.physicalCapability,
    required this.resumeUrl,
    required this.status,
    required this.ownerNotes,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String driversLicense;
  final String vehicleInfo;
  final String experience;
  final String experienceDetails;
  final String availability;
  final String physicalCapability;
  final String resumeUrl;
  final String status;
  final String ownerNotes;
  final DateTime createdAt;

  bool get isOpen => status == ApplicantStatus.newApplicant || status == ApplicantStatus.contacted;

  factory Applicant.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    String read(String key) => (map[key] as String? ?? '').trim();

    return Applicant(
      id: read('id'),
      name: read('name'),
      email: read('email'),
      phone: read('phone'),
      address: read('address'),
      driversLicense: read('driversLicense'),
      vehicleInfo: read('vehicleInfo'),
      experience: read('experience'),
      experienceDetails: read('experienceDetails'),
      availability: read('availability'),
      physicalCapability: read('physicalCapability'),
      resumeUrl: read('resumeUrl'),
      status: read('status').isEmpty ? ApplicantStatus.newApplicant : read('status'),
      ownerNotes: read('ownerNotes'),
      createdAt: readDate(map['createdAt']),
    );
  }
}

/// plain string constants for an application's triage status, matching
/// this codebase's RequestStatus convention
class ApplicantStatus {
  static const newApplicant = 'new';
  static const contacted = 'contacted';
  static const hired = 'hired';
  static const declined = 'declined';

  static const all = [newApplicant, contacted, hired, declined];

  static String label(String value) => switch (value) {
        contacted => 'Contacted',
        hired => 'Hired',
        declined => 'Declined',
        _ => 'New',
      };
}
