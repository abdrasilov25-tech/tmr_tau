import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/user_settings_entity.dart';
import '../domain/repositories/settings_repository.dart';

sealed class SettingsState {
  const SettingsState();
}

class SettingsInitial extends SettingsState {
  const SettingsInitial();
}

class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

class SettingsFailure extends SettingsState {
  const SettingsFailure(this.message);
  final String message;
}

class SettingsSuccess extends SettingsState {
  const SettingsSuccess({
    required this.settings,
    this.isSaving = false,
  });

  final UserSettingsEntity settings;
  final bool isSaving;

  SettingsSuccess copyWith({
    UserSettingsEntity? settings,
    bool? isSaving,
  }) {
    return SettingsSuccess(
      settings: settings ?? this.settings,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(
    this._repository, {
    required this.userId,
  }) : super(const SettingsInitial());

  final SettingsRepository _repository;
  final String userId;

  Future<void> load() async {
    emit(const SettingsLoading());
    try {
      final settings = await _repository.getMySettings(userId: userId);
      emit(SettingsSuccess(settings: settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  Future<void> update({
    bool? pushNotificationsEnabled,
    bool? emailNotificationsEnabled,
    bool? inAppNotificationsEnabled,
    bool? activityStatusEnabled,
    String? storyVisibility,
    String? postVisibility,
    bool? twoFactorEnabled,
  }) async {
    final current = state;
    if (current is! SettingsSuccess) return;
    if (current.isSaving) return;

    emit(current.copyWith(isSaving: true));
    try {
      final updated = current.settings.copyWith(
        pushNotificationsEnabled: pushNotificationsEnabled,
        emailNotificationsEnabled: emailNotificationsEnabled,
        inAppNotificationsEnabled: inAppNotificationsEnabled,
        activityStatusEnabled: activityStatusEnabled,
        storyVisibility: storyVisibility,
        postVisibility: postVisibility,
        twoFactorEnabled: twoFactorEnabled,
      );
      await _repository.upsertMySettings(settings: updated);
      emit(SettingsSuccess(settings: updated));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }
}

