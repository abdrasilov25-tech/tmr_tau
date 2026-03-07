import '../../data/models/message_model.dart';

abstract class ChatRepository {
  Stream<List<MessageEntity>> watchMessages(String userId, String peerId);
  Future<void> sendMessage(String receiverId, String text);
}

