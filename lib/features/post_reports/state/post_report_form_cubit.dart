import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/repositories/post_reports_repository.dart';

sealed class PostReportFormState {
  const PostReportFormState();
}

class PostReportFormIdle extends PostReportFormState {
  const PostReportFormIdle();
}

class PostReportFormSubmitting extends PostReportFormState {
  const PostReportFormSubmitting();
}

class PostReportFormSuccess extends PostReportFormState {
  const PostReportFormSuccess();
}

class PostReportFormFailure extends PostReportFormState {
  const PostReportFormFailure(this.message);
  final String message;
}

class PostReportFormCubit extends Cubit<PostReportFormState> {
  PostReportFormCubit(this._repository) : super(const PostReportFormIdle());

  final PostReportsRepository _repository;

  Future<void> submit({
    required String postId,
    required String reporterId,
    required String reason,
    required String comment,
  }) async {
    if (state is PostReportFormSubmitting) return;
    emit(const PostReportFormSubmitting());
    try {
      await _repository.createReport(
        postId: postId,
        reporterId: reporterId,
        reason: reason,
        comment: comment.trim().isEmpty ? null : comment.trim(),
      );
      emit(const PostReportFormSuccess());
    } catch (e) {
      emit(PostReportFormFailure(e.toString()));
    }
  }

  void reset() {
    emit(const PostReportFormIdle());
  }
}

