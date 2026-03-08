/// Выбрасывается, когда ответ на комментарий сохранён без parent_id
/// (колонка в БД отсутствует), чтобы UI мог показать подсказку по миграции.
class PostCommentReplyFallbackException implements Exception {
  const PostCommentReplyFallbackException();
}
