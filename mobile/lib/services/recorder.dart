import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Pembungkus paket `record` untuk merekam audio meeting ke file lokal (.m4a).
class MeetingRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Daftar perangkat input yang tersedia (mic, atau loopback seperti
  /// BlackHole/VB-Cable untuk menangkap audio sistem/Zoom).
  Future<List<InputDevice>> inputDevices() async {
    try {
      return await _recorder.listInputDevices();
    } catch (_) {
      return [];
    }
  }

  /// Buat path file rekaman baru di folder lokal (dipakai juga oleh jalur
  /// perekam native audio-sistem).
  Future<String> newRecordingPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(dir.path, 'recordings'));
    if (!recordingsDir.existsSync()) {
      recordingsDir.createSync(recursive: true);
    }
    return p.join(
      recordingsDir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }

  /// Mulai rekaman, kembalikan path file tujuan. [device] opsional — bila null
  /// pakai perangkat input default sistem.
  Future<String> start({InputDevice? device}) async {
    final path = await newRecordingPath();
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000, // optimal untuk speech-to-text
        numChannels: 1,
        device: device, // null = default sistem
      ),
      path: path,
    );
    return path;
  }

  Future<void> pause() => _recorder.pause();
  Future<void> resume() => _recorder.resume();

  /// Hentikan rekaman, kembalikan path file final.
  Future<String?> stop() => _recorder.stop();

  Future<bool> isRecording() => _recorder.isRecording();
  Future<bool> isPaused() => _recorder.isPaused();

  /// Stream amplitudo untuk indikator level suara (update cepat utk visual).
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 120));

  void dispose() => _recorder.dispose();
}
