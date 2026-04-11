import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmr_tau/app.dart';
import 'package:tmr_tau/core/auth/guest_session_storage.dart';
import 'package:tmr_tau/core/accounts/account_repository.dart';
import 'package:tmr_tau/core/feedback/feedback_preferences_storage.dart';
import 'package:tmr_tau/core/storage/chat_list_storage.dart';
import 'package:tmr_tau/core/storage/chat_story_list_storage.dart';
import 'package:tmr_tau/core/storage/local_reactions_storage.dart';
import 'package:tmr_tau/core/storage/multi_account_storage.dart';
import 'package:tmr_tau/features/chat/data/chat_streak_storage.dart';
import 'package:tmr_tau/features/chat/data/chat_pets_storage.dart';
import 'package:tmr_tau/features/chat/data/chat_sticker_favorites_storage.dart';

void main() {
  late LocalReactionsStorage localReactionsStorage;
  late ChatListStorage chatListStorage;
  late ChatStoryListStorage chatStoryListStorage;
  late ChatStreakStorage chatStreakStorage;
  late ChatPetsStorage chatPetsStorage;
  late ChatStickerFavoritesStorage chatStickerFavoritesStorage;
  late MultiAccountStorage multiAccountStorage;
  late AccountRepository accountRepository;
  late FeedbackPreferencesStorage feedbackPreferencesStorage;
  late GuestSessionStorage guestSessionStorage;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    localReactionsStorage = LocalReactionsStorage(prefs);
    chatListStorage = ChatListStorage(prefs);
    chatStoryListStorage = ChatStoryListStorage(prefs);
    chatStreakStorage = ChatStreakStorage(prefs);
    chatPetsStorage = ChatPetsStorage(prefs);
    chatStickerFavoritesStorage = ChatStickerFavoritesStorage(prefs);
    multiAccountStorage = MultiAccountStorage(prefs, const FlutterSecureStorage());
    accountRepository = AccountRepositoryImpl(prefs);
    feedbackPreferencesStorage = FeedbackPreferencesStorage(prefs);
    guestSessionStorage = GuestSessionStorage(prefs);
  });

  group('TmrTauApp', () {
    testWidgets(
        'показывает экран настройки Supabase, когда Supabase не инициализирован',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        TmrTauApp(
          supabaseUrl: 'https://test.supabase.co',
          supabaseAnonKey: 'test-key',
          supabaseInitialized: false,
          localReactionsStorage: localReactionsStorage,
          chatListStorage: chatListStorage,
          chatStoryListStorage: chatStoryListStorage,
          chatStreakStorage: chatStreakStorage,
          chatPetsStorage: chatPetsStorage,
          chatStickerFavoritesStorage: chatStickerFavoritesStorage,
          multiAccountStorage: multiAccountStorage,
          accountRepository: accountRepository,
          feedbackPreferencesStorage: feedbackPreferencesStorage,
          guestSessionStorage: guestSessionStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Supabase'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
