/// stores owner company branding and contact information
class OwnerSettings {
  const OwnerSettings({
    required this.companyName,
    required this.address,
    this.logoUrl,
    this.logoBase64,
    this.nextEstimateNumber = 1,
    this.phone = '',
    this.email = '',
    this.estimateFileNameTemplate = 'estimate_{EstimateNumber}',
    this.invoiceFileNameTemplate = 'invoice_{InvoiceNumber}',
  });

  final String companyName;
  final String address;
  // Legacy: Firebase Storage URL (kept for possible future use)
  final String? logoUrl;
  // Primary: base64-encoded logo stored directly in Firestore
  final String? logoBase64;
  // Counter used to generate the next sequential estimate number (EST-0001, ...)
  final int nextEstimateNumber;
  final String phone;
  final String email;

  /// filename template for downloaded estimate PDFs; supports {CompanyName},
  /// {EstimateNumber}, {ClientName}, {Date} placeholders
  final String estimateFileNameTemplate;

  /// filename template for downloaded invoice PDFs; supports {CompanyName},
  /// {InvoiceNumber}, {ClientName}, {Date} placeholders
  final String invoiceFileNameTemplate;

  bool get hasLogo =>
      (logoBase64 != null && logoBase64!.isNotEmpty) ||
      (logoUrl != null && logoUrl!.isNotEmpty);

  /// create empty owner settings instance
  factory OwnerSettings.empty() =>
      const OwnerSettings(companyName: '', address: '');

  /// create settings from firestore map
  factory OwnerSettings.fromMap(Map<String, dynamic> map) {
    final logo = (map['logo_url'] as String?)?.trim();
    final base64 = (map['logo_base64'] as String?)?.trim();
    return OwnerSettings(
      companyName: (map['company_name'] as String? ?? '').trim(),
      address: (map['address'] as String? ?? '').trim(),
      logoUrl: (logo == null || logo.isEmpty) ? null : logo,
      logoBase64: (base64 == null || base64.isEmpty) ? null : base64,
      nextEstimateNumber: (map['next_estimate_number'] as num?)?.toInt() ?? 1,
      phone: (map['phone'] as String? ?? '').trim(),
      email: (map['email'] as String? ?? '').trim(),
      estimateFileNameTemplate:
          (map['estimate_file_name_template'] as String?)?.trim().isEmpty ??
                  true
              ? 'estimate_{EstimateNumber}'
              : (map['estimate_file_name_template'] as String).trim(),
      invoiceFileNameTemplate:
          (map['invoice_file_name_template'] as String?)?.trim().isEmpty ?? true
              ? 'invoice_{InvoiceNumber}'
              : (map['invoice_file_name_template'] as String).trim(),
    );
  }

  /// convert settings to firestore map
  Map<String, dynamic> toMap() {
    return {
      'company_name': companyName.trim(),
      'address': address.trim(),
      'logo_url': logoUrl?.trim(),
      'logo_base64': logoBase64,
      'next_estimate_number': nextEstimateNumber,
      'phone': phone.trim(),
      'email': email.trim(),
      'estimate_file_name_template': estimateFileNameTemplate.trim(),
      'invoice_file_name_template': invoiceFileNameTemplate.trim(),
    };
  }

  /// create copy with updated fields
  OwnerSettings copyWith({
    String? companyName,
    String? address,
    String? logoUrl,
    String? logoBase64,
    bool clearLogo = false,
    int? nextEstimateNumber,
    String? phone,
    String? email,
    String? estimateFileNameTemplate,
    String? invoiceFileNameTemplate,
  }) {
    return OwnerSettings(
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
      nextEstimateNumber: nextEstimateNumber ?? this.nextEstimateNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      estimateFileNameTemplate:
          estimateFileNameTemplate ?? this.estimateFileNameTemplate,
      invoiceFileNameTemplate:
          invoiceFileNameTemplate ?? this.invoiceFileNameTemplate,
    );
  }
}
