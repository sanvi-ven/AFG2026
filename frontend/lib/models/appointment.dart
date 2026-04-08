class Appointment {
  const Appointment({
    required this.id,
    required this.businessId,
    required this.clientId,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  final String id;
  final String businessId;
  final String clientId;
  final DateTime startTime;
  final DateTime endTime;
  final String status;

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      clientId: json['client_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      status: json['status'] as String,
    );
  }
}
