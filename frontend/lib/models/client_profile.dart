class ClientProfile {
  const ClientProfile({
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.street,
    required this.country,
    required this.zipCode,
  });

  final String email;
  final String firstName;
  final String lastName;
  final String phone;
  final String street;
  final String country;
  final String zipCode;

  String get greetingName {
    if (firstName.trim().isNotEmpty) {
      return firstName.trim();
    }
    return email.split('@').first;
  }

  String get fullName {
    final combined = '${firstName.trim()} ${lastName.trim()}'.trim();
    return combined.isEmpty ? greetingName : combined;
  }

  factory ClientProfile.emptyForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    final fallbackFirstName = normalizedEmail.split('@').first;
    return ClientProfile(
      email: normalizedEmail,
      firstName: fallbackFirstName,
      lastName: '',
      phone: '',
      street: '',
      country: '',
      zipCode: '',
    );
  }

  factory ClientProfile.fromMap(Map<String, dynamic> map) {
    return ClientProfile(
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      firstName: (map['firstName'] as String? ?? '').trim(),
      lastName: (map['lastName'] as String? ?? '').trim(),
      phone: (map['phone'] as String? ?? '').trim(),
      street: (map['street'] as String? ?? '').trim(),
      country: (map['country'] as String? ?? '').trim(),
      zipCode: (map['zipCode'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email.trim().toLowerCase(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'phone': phone.trim(),
      'street': street.trim(),
      'country': country.trim(),
      'zipCode': zipCode.trim(),
    };
  }

  ClientProfile copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? street,
    String? country,
    String? zipCode,
  }) {
    return ClientProfile(
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      street: street ?? this.street,
      country: country ?? this.country,
      zipCode: zipCode ?? this.zipCode,
    );
  }
}
