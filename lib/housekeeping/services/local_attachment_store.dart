abstract interface class LocalAttachmentStore {
  Future<String> readAttachment(String id);
}
