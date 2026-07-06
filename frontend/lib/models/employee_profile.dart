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
  });

  final String employeeId;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? teamId;
  final bool active;
  final double? hourlyRate;

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
    return EmployeeProfile(
      employeeId: (map['id'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      firstName: (map['first_name'] as String? ?? '').trim(),
      lastName: (map['last_name'] as String? ?? '').trim(),
      phoneNumber: (map['phone_number'] as String? ?? '').trim(),
      teamId: rawTeamId.isEmpty ? null : rawTeamId,
      active: map['active'] as bool? ?? true,
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble(),
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
    );
  }
}
