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
}
