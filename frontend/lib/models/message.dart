class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.read,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String text;
  final bool read;
}
