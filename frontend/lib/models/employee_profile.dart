import 'package:cloud_firestore/cloud_firestore.dart';

/// represents an employee profile with contact info and team assignment
class EmployeeProfile {
  const EmployeeProfile({
    required this.employeeId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.teamId,
    required this.active,
    this.hourlyRate,
    this.uid,
    this.archived = false,
    this.dateOfBirth,
    this.guardianName = '',
    this.guardianEmail = '',
    this.guardianPhone = '',
    this.address = '',
    this.foodAllergies = '',
    this.medicationAllergies = '',
    this.environmentalAllergies = '',
  });

  final String employeeId;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? teamId;
  final bool active;
  final double? hourlyRate;

  /// linked Firebase Auth uid
  final String? uid;

  /// true once the owner has archived this employee (hidden from the active
  /// roster and from new job/team assignments) — their history (jobs, time
  /// entries, pay) stays intact and still resolves through this profile.
  final bool archived;

  /// self-editable by the employee (see firestore.rules) — note this means an
  /// employee could misstate their own age; the one backstop is the owner
  /// being prompted to confirm adult/minor status when issuing a contract to
  /// someone with no birthdate on file (see ContractsTab._issueContract).
  final DateTime? dateOfBirth;

  /// owner-only-writable — unlike dateOfBirth, guardian contact stays
  /// owner-only since a self-editable guardian email would let a minor
  /// redirect their own contract's guardian consent to an address they
  /// control, which is a materially worse gap than misstating a birthdate.
  final String guardianName;
  final String guardianEmail;
  final String guardianPhone;

  /// self-editable by the employee — home address, for HR/emergency records.
  final String address;

  /// self-editable by the employee — free-text allergy info a crew lead or
  /// the owner might need in an emergency, kept as three separate categories
  /// rather than one blob so each is quick to scan.
  final String foodAllergies;
  final String medicationAllergies;
  final String environmentalAllergies;

  /// derived, never stored — same reasoning as EquipmentBasket.computeStatus,
  /// so it can't drift out of sync with dateOfBirth.
  bool get isMinor {
    final dob = dateOfBirth;
    if (dob == null) return false;
    final today = DateTime.now();
    var age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age < 18;
  }

  String get greetingName {
    if (firstName.trim().isNotEmpty) {
      return firstName.trim();
    }
    return email.split('@').first;
  }

  /// get full name from first and last names
  String get fullName {
    final combined = '${firstName.trim()} ${lastName.trim()}'.trim();
    return combined.isEmpty ? greetingName : combined;
  }

  /// create empty profile for new employee signup
  factory EmployeeProfile.emptyForSignup({
    required String employeeId,
    required String email,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final fallbackFirstName = normalizedEmail.split('@').first;
    return EmployeeProfile(
      employeeId: employeeId.trim(),
      email: normalizedEmail,
      firstName: fallbackFirstName,
      lastName: '',
      phoneNumber: '',
      teamId: null,
      active: true,
    );
  }

  /// create employee profile instance from firestore map data
  factory EmployeeProfile.fromMap(Map<String, dynamic> map) {
    final rawTeamId = (map['teamId'] as String? ?? '').trim();
    final rawDob = map['date_of_birth'];
    DateTime? dob;
    if (rawDob is Timestamp) {
      dob = rawDob.toDate();
    } else if (rawDob is String && rawDob.trim().isNotEmpty) {
      dob = DateTime.tryParse(rawDob.trim());
    }
    return EmployeeProfile(
      employeeId: (map['id'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      firstName: (map['first_name'] as String? ?? '').trim(),
      lastName: (map['last_name'] as String? ?? '').trim(),
      phoneNumber: (map['phone_number'] as String? ?? '').trim(),
      teamId: rawTeamId.isEmpty ? null : rawTeamId,
      active: map['active'] as bool? ?? true,
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble(),
      uid: (map['uid'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['uid'] as String).trim(),
      archived: map['archived'] as bool? ?? false,
      dateOfBirth: dob,
      guardianName: (map['guardian_name'] as String? ?? '').trim(),
      guardianEmail: (map['guardian_email'] as String? ?? '').trim(),
      guardianPhone: (map['guardian_phone'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? '').trim(),
      foodAllergies: (map['food_allergies'] as String? ?? '').trim(),
      medicationAllergies: (map['medication_allergies'] as String? ?? '').trim(),
      environmentalAllergies: (map['environmental_allergies'] as String? ?? '').trim(),
    );
  }

  /// convert profile to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': employeeId.trim(),
      'email': email.trim().toLowerCase(),
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone_number': phoneNumber.trim(),
      'teamId': teamId,
      'active': active,
      'hourly_rate': hourlyRate,
      'archived': archived,
      'date_of_birth': dateOfBirth,
      'guardian_name': guardianName.trim(),
      'guardian_email': guardianEmail.trim(),
      'guardian_phone': guardianPhone.trim(),
      'address': address.trim(),
      'food_allergies': foodAllergies.trim(),
      'medication_allergies': medicationAllergies.trim(),
      'environmental_allergies': environmentalAllergies.trim(),
    };
  }

  /// create copy of profile with updated fields
  EmployeeProfile copyWith({
    String? employeeId,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? teamId,
    bool clearTeamId = false,
    bool? active,
    double? hourlyRate,
    bool clearHourlyRate = false,
    String? uid,
    bool? archived,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? guardianName,
    String? guardianEmail,
    String? guardianPhone,
    String? address,
    String? foodAllergies,
    String? medicationAllergies,
    String? environmentalAllergies,
  }) {
    return EmployeeProfile(
      employeeId: employeeId ?? this.employeeId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      active: active ?? this.active,
      hourlyRate: clearHourlyRate ? null : (hourlyRate ?? this.hourlyRate),
      uid: uid ?? this.uid,
      archived: archived ?? this.archived,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      guardianName: guardianName ?? this.guardianName,
      guardianEmail: guardianEmail ?? this.guardianEmail,
      guardianPhone: guardianPhone ?? this.guardianPhone,
      address: address ?? this.address,
      foodAllergies: foodAllergies ?? this.foodAllergies,
      medicationAllergies: medicationAllergies ?? this.medicationAllergies,
      environmentalAllergies: environmentalAllergies ?? this.environmentalAllergies,
    );
  }
}
