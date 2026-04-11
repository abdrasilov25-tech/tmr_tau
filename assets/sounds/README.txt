Place short UI sound files here (<300 ms, WAV/MP3/OGG).
All files are optional — missing files are silently skipped,
haptics still fire regardless.

  message_sent.wav     — whoosh played when the user sends a message
  message_received.wav — pop/ding played when a new incoming message arrives
  reaction.wav         — sparkle/chime played when the user places an emoji reaction
  success.wav          — positive chime for success actions (purchase, subscribe, read receipt)
  error.wav            — heavy buzz for error actions
  wow_battle.wav       — dramatic boom on Battle section entry
  wow_shop.wav         — magical arpeggio on Shop section entry
  wow_wallet.wav       — coin jingle on Wallet section entry

Integration map (FeedbackManager methods):
  messageSent()      → message_sent.wav  + HapticFeedback.mediumImpact
  messageReceived()  → message_received.wav + HapticFeedback.lightImpact
  messageRead()      → success.wav       + HapticFeedback.selectionClick
  messageReaction()  → reaction.wav      + HapticFeedback.selectionClick
  notificationActivity() → message_received.wav + HapticFeedback.lightImpact
  success()          → success.wav       + HapticFeedback.mediumImpact
  error()            → error.wav         + HapticFeedback.heavyImpact
  buttonTap()        → SystemSound.click + HapticFeedback.lightImpact
  battleEntry()      → wow_battle.wav    + HapticFeedback.heavyImpact
  shopEntry()        → wow_shop.wav      + HapticFeedback.mediumImpact
  walletEntry()      → wow_wallet.wav    + HapticFeedback.mediumImpact

Recommended specs for new sound files:
  Duration  : 80–280 ms
  Format    : WAV (PCM 16-bit, 44100 Hz, mono) or MP3 128 kbps
  Peak level: –6 dBFS to –12 dBFS (not too loud)
