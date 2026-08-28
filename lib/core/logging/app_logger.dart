import 'package:flutter/foundation.dart';

/// Keeps diagnostics structured without exposing credentials or token bytes.
abstract final class AppLogger {
  static void info(String scope, String message) {
    if (kDebugMode) debugPrint('[$scope] $message');
  }

  static void error(String scope, Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[$scope] $error');
      if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    }
  }
}
