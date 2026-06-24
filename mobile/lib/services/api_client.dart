import 'package:dio/dio.dart';

import '../models/meeting.dart';

/// Job tidak ditemukan di server (mis. sudah kedaluwarsa/dihapus) — perlu unggah ulang.
class JobNotFoundException implements Exception {
  const JobNotFoundException();
  @override
  String toString() => 'Job tidak ditemukan di server';
}

/// Hasil polling status job dari server.
class JobResult {
  final MeetingStatus status;
  final String? transcript;
  final Summary? summary;
  final String? error;

  /// Kemajuan pemrosesan di server: 0..1, teks tahap, dan estimasi sisa waktu.
  final double progress;
  final String? stageLabel;
  final int? etaSeconds;

  /// Lama proses konversi di server (detik), tersedia saat selesai.
  final int? processingSeconds;

  /// Durasi audio (detik), dari Whisper — tersedia saat selesai.
  final int? audioSeconds;

  const JobResult({
    required this.status,
    this.transcript,
    this.summary,
    this.error,
    this.progress = 0,
    this.stageLabel,
    this.etaSeconds,
    this.processingSeconds,
    this.audioSeconds,
  });
}

/// Klien HTTP ke backend Notula (upload audio + polling hasil).
class ApiClient {
  final String baseUrl;
  final Dio _dio;

  ApiClient(this.baseUrl, {String apiKey = ''})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
            // lewati halaman peringatan ngrok free agar respons JSON langsung
            'ngrok-skip-browser-warning': 'true',
          },
        ));

  /// Cek koneksi & info server.
  Future<Map<String, dynamic>> health() async {
    final resp = await _dio.get('/api/health');
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Upload file audio, kembalikan job_id.
  Future<String> uploadAudio(
    String audioPath, {
    String language = 'id',
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'language': language,
      'audio': await MultipartFile.fromFile(audioPath),
    });
    final resp = await _dio.post(
      '/api/jobs',
      data: form,
      onSendProgress: onProgress,
      options: Options(sendTimeout: const Duration(minutes: 10)),
    );
    return (resp.data as Map)['job_id'] as String;
  }

  /// Ambil status satu job. Melempar [JobNotFoundException] bila job hilang (404).
  Future<JobResult> getJob(String jobId) async {
    final Response resp;
    try {
      resp = await _dio.get('/api/jobs/$jobId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const JobNotFoundException();
      rethrow;
    }
    final data = Map<String, dynamic>.from(resp.data as Map);
    final statusStr = data['status'] as String;
    final status = switch (statusStr) {
      'queued' || 'transcribing' => MeetingStatus.transcribing,
      'summarizing' => MeetingStatus.summarizing,
      'done' => MeetingStatus.done,
      _ => MeetingStatus.failed,
    };
    final progressRaw = (data['progress'] as num?)?.toDouble() ?? 0;
    return JobResult(
      status: status,
      transcript: data['transcript'] as String?,
      summary: data['summary'] == null
          ? null
          : Summary.fromJson(
              Map<String, dynamic>.from(data['summary'] as Map)),
      error: data['error'] as String?,
      progress: (progressRaw / 100).clamp(0, 1),
      stageLabel: data['stage_label'] as String?,
      etaSeconds: (data['eta_seconds'] as num?)?.toInt(),
      processingSeconds: (data['processing_seconds'] as num?)?.toInt(),
      audioSeconds: (data['audio_seconds'] as num?)?.toInt(),
    );
  }

  /// Polling sampai job selesai (done/failed).
  ///
  /// Tahan terhadap koneksi putus sementara: error jaringan/timeout TIDAK
  /// langsung menggagalkan — server tetap memproses job, jadi polling diulang
  /// (server adalah sumber kebenaran). [onUpdate] dipanggil tiap ada status job
  /// baru; [onReconnecting] dipanggil saat sedang mencoba menyambung ulang
  /// (dengan jumlah percobaan beruntun). Menyerah hanya setelah
  /// [maxConsecutiveErrors] kegagalan beruntun, atau bila job hilang (404).
  Future<JobResult> pollUntilDone(
    String jobId, {
    Duration interval = const Duration(seconds: 2),
    int maxConsecutiveErrors = 40,
    void Function(JobResult result)? onUpdate,
    void Function(int attempt)? onReconnecting,
  }) async {
    int errors = 0;
    while (true) {
      try {
        final result = await getJob(jobId);
        errors = 0; // berhasil tersambung kembali
        onUpdate?.call(result);
        if (result.status == MeetingStatus.done ||
            result.status == MeetingStatus.failed) {
          return result;
        }
      } on JobNotFoundException {
        rethrow; // job sudah tidak ada di server — pemanggil yang memutuskan
      } catch (_) {
        errors++;
        if (errors >= maxConsecutiveErrors) rethrow;
        onReconnecting?.call(errors);
      }
      await Future.delayed(interval);
    }
  }
}
