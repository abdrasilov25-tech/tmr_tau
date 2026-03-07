import 'package:flutter/foundation.dart';

void appLog(String message, [Object? error, StackTrace? stackTrace]) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[tmr_tau] $message');
    if (error != null) {
      // ignore: avoid_print
      print('[tmr_tau] error: $error');
      if (stackTrace != null) {
        // ignore: avoid_print
        print(stackTrace);
      }
    }
  }
}
