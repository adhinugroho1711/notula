import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Pembungkus paket `record` untuk merekam audio meeting ke file lokal (.m4a).
class MeetingRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Mulai rekaman, kembalikan path file tujuan.
  Future<String> start() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(dir.path, 'recordings'));
    if (!recordingsDir.existsSync()) {
      recordingsDir.createSync(recursive: true);
    }
    final path = p.join(
      recordingsDir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000, // optimal untuk speech-to-text
        numChannels: 1,
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
