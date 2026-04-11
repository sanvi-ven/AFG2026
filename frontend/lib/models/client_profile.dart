class ClientProfile {
  const ClientProfile({
    required this.signupId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.street,
    required this.country,
    required this.zipCode,
  });

  final String signupId;
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

  factory ClientProfile.emptyForSignup({
    required String signupId,
    required String email,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final fallbackFirstName = normalizedEmail.split('@').first;
    return ClientProfile(
      signupId: signupId.trim(),
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
    final rawName = (map['name'] as String? ?? '').trim();
    final nameParts = rawName.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final address = (map['address'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    return ClientProfile(
      signupId: (map['signupId'] as String? ?? map['id'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      firstName: (map['firstName'] as String? ?? (nameParts.isNotEmpty ? nameParts.first : '')).trim(),
      lastName: (map['lastName'] as String? ?? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')).trim(),
      phone: (map['phone'] as String? ?? '').trim(),
      street: (map['street'] as String? ?? address['street'] as String? ?? '').trim(),
      country: (map['country'] as String? ?? address['country'] as String? ?? '').trim(),
      zipCode: (map['zipCode'] as String? ?? address['zip_code'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'signupId': signupId.trim(),
      'email': email.trim().toLowerCase(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'name': fullName,
      'phone': phone.trim(),
      'street': street.trim(),
      'country': country.trim(),
      'zipCode': zipCode.trim(),
      'address': {
        'street': street.trim(),
        'country': country.trim(),
        'zip_code': zipCode.trim(),
      },
    };
  }

  ClientProfile copyWith({
    String? signupId,
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? street,
    String? country,
    String? zipCode,
  }) {
    return ClientProfile(
      signupId: signupId ?? this.signupId,
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
