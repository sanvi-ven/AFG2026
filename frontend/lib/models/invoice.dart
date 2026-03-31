class Invoice {
  const Invoice({
    required this.id,
    required this.clientId,
    required this.businessId,
    required this.total,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String clientId;
  final String businessId;
  final double total;
  final String status;
  final DateTime dueDate;
}
