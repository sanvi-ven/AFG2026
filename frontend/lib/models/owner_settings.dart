class OwnerSettings {
  const OwnerSettings({
    required this.companyName,
    required this.address,
    this.logoUrl,
    this.logoBase64,
  });

  final String companyName;
  final String address;
  // Legacy: Firebase Storage URL (kept for possible future use)
  final String? logoUrl;
  // Primary: base64-encoded logo stored directly in Firestore
  final String? logoBase64;

  bool get hasLogo =>
      (logoBase64 != null && logoBase64!.isNotEmpty) ||
      (logoUrl != null && logoUrl!.isNotEmpty);

  factory OwnerSettings.empty() => const OwnerSettings(companyName: '', address: '');

  factory OwnerSettings.fromMap(Map<String, dynamic> map) {
    final logo = (map['logo_url'] as String?)?.trim();
    final base64 = (map['logo_base64'] as String?)?.trim();
    return OwnerSettings(
      companyName: (map['company_name'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? '').trim(),
      logoUrl: (logo == null || logo.isEmpty) ? null : logo,
      logoBase64: (base64 == null || base64.isEmpty) ? null : base64,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'company_name': companyName.trim(),
      'address': address.trim(),
      'logo_url': logoUrl?.trim(),
      'logo_base64': logoBase64,
    };
  }

  OwnerSettings copyWith({
    String? companyName,
    String? address,
    String? logoUrl,
    String? logoBase64,
    bool clearLogo = false,
  }) {
    return OwnerSettings(
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
    );
  }
}
