class ClientProfile {
  const ClientProfile({
    required this.signupId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.address,
  });

  final String signupId;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String address;

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
      phoneNumber: '',
      address: '',
    );
  }

  factory ClientProfile.fromMap(Map<String, dynamic> map) {
    final rawName = (map['name'] as String? ?? '').trim();
    final nameParts = rawName.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final rawAddress = map['address'];
    final legacyAddressMap = rawAddress is Map
        ? rawAddress.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final fallbackAddress = [
      legacyAddressMap['street'] as String? ?? map['street'] as String? ?? '',
      legacyAddressMap['country'] as String? ?? map['country'] as String? ?? '',
      legacyAddressMap['zip_code'] as String? ?? map['zipCode'] as String? ?? '',
    ].where((part) => part.trim().isNotEmpty).join(', ');

    return ClientProfile(
      signupId: (map['signupId'] as String? ?? map['id'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      firstName: (map['first_name'] as String? ?? map['firstName'] as String? ?? (nameParts.isNotEmpty ? nameParts.first : '')).trim(),
      lastName: (map['last_name'] as String? ?? map['lastName'] as String? ?? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')).trim(),
      phoneNumber: (map['phone_number'] as String? ?? map['phone'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? fallbackAddress).trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': signupId.trim(),
      'email': email.trim().toLowerCase(),
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone_number': phoneNumber.trim(),
      'address': address.trim(),
    };
  }

  ClientProfile copyWith({
    String? signupId,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? address,
  }) {
    return ClientProfile(
      signupId: signupId ?? this.signupId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
    );
  }
}
