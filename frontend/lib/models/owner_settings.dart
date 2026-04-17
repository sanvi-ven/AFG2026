class OwnerSettings {
  const OwnerSettings({
    required this.companyName,
    required this.address,
    this.logoUrl,
  });

  final String companyName;
  final String address;
  final String? logoUrl;

  factory OwnerSettings.empty() {
    return const OwnerSettings(companyName: '', address: '', logoUrl: null);
  }

  factory OwnerSettings.fromMap(Map<String, dynamic> map) {
    final logo = (map['logo_url'] as String?)?.trim();
    return OwnerSettings(
      companyName: (map['company_name'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? '').trim(),
      logoUrl: (logo == null || logo.isEmpty) ? null : logo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'company_name': companyName.trim(),
      'address': address.trim(),
      'logo_url': logoUrl?.trim(),
    };
  }

  OwnerSettings copyWith({
    String? companyName,
    String? address,
    String? logoUrl,
    bool clearLogo = false,
  }) {
    return OwnerSettings(
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
    );
  }
}
