import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Perekam audio sistem + mikrofon native (macOS ScreenCaptureKit).
/// Untuk merekam rapat online (Zoom/Teams/Meet) tanpa perangkat loopback.
class SystemAudioCapture {
  static const _ch = MethodChannel('id.co.bankjateng.notula/system_audio');

  /// True bila platform mendukung (macOS 13+).
  static Future<bool> available() async {
    if (!Platform.isMacOS) return false;
    try {
      return (await _ch.invokeMethod<bool>('available')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mulai merekam audio sistem (+ mic) ke [path]. Melempar PlatformException
  /// bila gagal (mis. izin Screen Recording belum diberikan).
  static Future<void> start(String path, {bool includeMic = true}) =>
      _ch.invokeMethod('start', {'path': path, 'includeMic': includeMic});

  /// Hentikan; kembalikan path file final.
  static Future<String?> stop() => _ch.invokeMethod<String>('stop');
}
