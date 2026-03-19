import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/repositories/settings_repository.dart';

sealed class SupportTicketFormState {
  const SupportTicketFormState();
}

class SupportTicketFormIdle extends SupportTicketFormState {
  const SupportTicketFormIdle();
}

class SupportTicketFormSubmitting extends SupportTicketFormState {
  const SupportTicketFormSubmitting();
}

class SupportTicketFormSuccess extends SupportTicketFormState {
  const SupportTicketFormSuccess();
}

class SupportTicketFormFailure extends SupportTicketFormState {
  const SupportTicketFormFailure(this.message);
  final String message;
}

class SupportTicketFormCubit extends Cubit<SupportTicketFormState> {
  SupportTicketFormCubit(
    this._repository, {
    required this.userId,
  }) : super(const SupportTicketFormIdle());

  final SettingsRepository _repository;
  final String userId;

  Future<void> submit({
    required String title,
    required String description,
  }) async {
    if (state is SupportTicketFormSubmitting) return;
    emit(const SupportTicketFormSubmitting());
    try {
      final trimmedTitle = title.trim();
      final trimmedDesc = description.trim();
      await _repository.createSupportTicket(
        userId: userId,
        title: trimmedTitle,
        description: trimmedDesc,
      );
      emit(const SupportTicketFormSuccess());
    } catch (e) {
      emit(SupportTicketFormFailure(e.toString()));
    }
  }

  void reset() {
    emit(const SupportTicketFormIdle());
  }
}

