import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc(this._repository) : super(ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
    on<ProfileToggleFollow>(_onToggleFollow);
  }

  final ProfileRepository _repository;

  Future<void> _onLoadRequested(
      ProfileLoadRequested event, Emitter<ProfileState> emit) async {
    emit(ProfileLoading());
    try {
      final sessionUid = Supabase.instance.client.auth.currentUser?.id;
      final viewerId = event.currentUserId ?? sessionUid;
      final profile = await _repository.getSellerProfile(
        event.sellerId,
        currentUserId: viewerId,
      );
      if (!isClosed) {
        emit(profile != null
            ? ProfileSuccess(profile)
            : ProfileFailure('Профиль не найден'));
      }
    } catch (e) {
      if (!isClosed) emit(ProfileFailure(e.toString()));
    }
  }

  Future<void> _onToggleFollow(
      ProfileToggleFollow event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileSuccess) return;
    // Оптимистично обновляем профиль в UI.
    final updated = SellerProfileEntity(
      id: current.profile.id,
      name: current.profile.name,
      avatarUrl: current.profile.avatarUrl,
      bio: current.profile.bio,
      followersCount: current.profile.isFollowingByMe
          ? current.profile.followersCount - 1
          : current.profile.followersCount + 1,
      followingCount: current.profile.followingCount,
      totalReceivedPostLikes: current.profile.totalReceivedPostLikes,
      isFollowingByMe: !current.profile.isFollowingByMe,
      products: current.profile.products,
      isVerified: current.profile.isVerified,
      instagramUrl: current.profile.instagramUrl,
      telegramUsername: current.profile.telegramUsername,
      websiteUrl: current.profile.websiteUrl,
      officialPageActive: current.profile.officialPageActive,
    );
    if (!isClosed) emit(ProfileSuccess(updated));

    // Запрос в БД выполняем в фоне, чтобы не блокировать интерфейс.
    unawaited(_repository.toggleFollow(event.followerId, event.followingId));
  }
}
