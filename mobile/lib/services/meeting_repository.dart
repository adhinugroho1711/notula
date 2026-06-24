import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../db/database.dart';
import '../models/meeting.dart';
import 'api_client.dart';
import 'settings.dart';

/// Sumber kebenaran in-memory untuk daftar meeting + orkestrasi pemrosesan.
///
/// Memuat daftar dari SQLite, dan menangani upload→polling ke server sambil
/// memperbarui status agar UI bisa menampilkannya secara reaktif.
class MeetingRepository extends ChangeNotifier {
  MeetingRepository._();
  static final MeetingRepository instance = MeetingRepository._();

  final _db = MeetingDatabase.instance;
  List<Meeting> _meetings = [];
  List<Meeting> get meetings => List.unmodifiable(_meetings);

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Set id meeting yang sedang dipoll, agar tidak ada polling ganda.
  final Set<int> _active = {};

  /// Antrian id meeting yang menunggu giliran diproses (satu per satu).
  final List<int> _pending = [];
  bool _draining = false;

  /// Tambahkan meeting ke antrian pemrosesan. Diproses berurutan satu per satu
  /// (upload + transkrip + ringkas selesai, baru lanjut berikutnya) — ramah
  /// bandwidth tunnel & sesuai worker tunggal di server.
  Future<void> enqueue(Meeting m) async {
    if (m.id == null) return;
    if (m.status.isProcessing) return;
    if (_pending.contains(m.id) || _active.contains(m.id)) return;
    m.queued = true;
    _pending.add(m.id!);
    _touch(m);
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final id = _pending.removeAt(0);
        Meeting? m;
        for (final e in _meetings) {
          if (e.id == id) {
            m = e;
            break;
          }
        }
        if (m == null) continue;
        m.queued = false;
        await process(m); // tunggu sampai selesai sebelum berikutnya
      }
    } finally {
      _draining = false;
    }
  }

  int get pendingCount => _pending.length;

  /// Apakah masih ada pekerjaan berjalan/antri (untuk konfirmasi tutup app).
  bool get isBusy =>
      _draining ||
      _pending.isNotEmpty ||
      _active.isNotEmpty ||
      _meetings.any((m) => m.status.isProcessing || m.queued);

  /// Posisi 1-based meeting dalam antrian (urutan upload, FIFO). 0 = tidak antri.
  int queuePosition(Meeting m) {
    final i = _pending.indexOf(m.id ?? -1);
    return i < 0 ? 0 : i + 1;
  }

  Future<void> load() async {
    _meetings = await _db.getAll();
    _loaded = true;
    notifyListeners();
    _resumeInterrupted();
  }

  /// Lanjutkan meeting yang tertinggal dalam status "diproses" saat app ditutup:
  /// jika punya job_id server -> poll ulang; jika tidak -> tandai bisa dicoba lagi.
  void _resumeInterrupted() {
    for (final m in _meetings) {
      if (!m.status.isProcessing) continue;
      if (m.serverJobId != null) {
        resume(m); // fire-and-forget; aman dari polling ganda lewat _active
      } else {
        m
          ..status = MeetingStatus.failed
          ..error = 'Proses terputus sebelum selesai diunggah. Coba lagi.';
        _touch(m);
      }
    }
  }

  Future<Meeting> addRecording({
    required String title,
    required String audioPath,
    required int durationSeconds,
  }) async {
    final meeting = await _db.insert(Meeting(
      title: title,
      createdAt: DateTime.now(),
      audioPath: audioPath,
      durationSeconds: durationSeconds,
    ));
    _meetings.insert(0, meeting);
    notifyListeners();
    return meeting;
  }

  /// Tambah meeting dari file rekaman yang diimpor (mis. hasil rekaman Zoom/Teams).
  Future<Meeting> addImported({
    required String title,
    required String filePath,
  }) async {
    final meeting = await _db.insert(Meeting(
      title: title,
      createdAt: DateTime.now(),
      audioPath: filePath,
      durationSeconds: 0,
    ));
    _meetings.insert(0, meeting);
    notifyListeners();
    return meeting;
  }

  Future<void> updateTitle(Meeting m, String title) async {
    m.title = title;
    await _db.update(m);
    notifyListeners();
  }

  /// Simpan hasil editan pengguna (judul/transkrip/ringkasan).
  Future<void> updateContent(
    Meeting m, {
    String? title,
    String? transcript,
    Summary? summary,
  }) async {
    if (title != null) m.title = title;
    if (transcript != null) m.transcript = transcript;
    if (summary != null) m.summary = summary;
    await _db.update(m);
    notifyListeners();
  }

  Future<void> remove(Meeting m) async {
    if (m.id != null) await _db.delete(m.id!);
    _meetings.removeWhere((e) => e.id == m.id);
    _pending.remove(m.id);
    notifyListeners();
  }

  /// Hapus beberapa meeting sekaligus.
  Future<void> removeMany(Iterable<Meeting> items) async {
    for (final m in items) {
      if (m.id != null) await _db.delete(m.id!);
      _pending.remove(m.id);
    }
    final ids = items.map((e) => e.id).toSet();
    _meetings.removeWhere((e) => ids.contains(e.id));
    notifyListeners();
  }

  void _touch(Meeting m) {
    _db.update(m);
    notifyListeners();
  }

  Future<ApiClient> _api() async => ApiClient(
        await Settings.instance.getServerUrl(),
        apiKey: await Settings.instance.getApiKey(),
      );

  /// Tombol "Coba lagi": lanjutkan job yang masih ada di server bila punya
  /// job_id, jika tidak unggah ulang dari awal.
  Future<void> retry(Meeting m) async {
    if (m.serverJobId != null) {
      await resume(m);
    } else {
      await process(m);
    }
  }

  /// Upload audio meeting lalu polling sampai selesai. Aman dipanggil ulang.
  Future<void> process(Meeting m) async {
    if (m.id != null && _active.contains(m.id)) return;
    if (m.id != null) _active.add(m.id!);
    m
      ..status = MeetingStatus.uploading
      ..uploadProgress = 0
      ..processProgress = 0
      ..stageLabel = null
      ..etaSeconds = null
      ..error = null;
    _touch(m);

    try {
      final api = await _api();
      final jobId = await api.uploadAudio(
        m.audioPath,
        onProgress: (sent, total) {
          if (total > 0) {
            m.uploadProgress = sent / total;
            notifyListeners();
          }
        },
      );
      // Simpan job_id SEGERA agar bisa di-resume kalau koneksi putus.
      m.serverJobId = jobId;
      _touch(m);

      await _pollAndApply(m, jobId, api);
    } catch (e) {
      m
        ..status = MeetingStatus.failed
        ..error = _friendlyError(e);
      _touch(m);
    } finally {
      if (m.id != null) _active.remove(m.id);
    }
  }

  /// Lanjutkan memantau job yang sudah diunggah sebelumnya (tanpa unggah ulang).
  /// Dipakai saat resume setelah koneksi putus / app dibuka kembali.
  Future<void> resume(Meeting m) async {
    final jobId = m.serverJobId;
    if (jobId == null) return process(m);
    if (m.id != null && _active.contains(m.id)) return;
    if (m.id != null) _active.add(m.id!);
    m.error = null;
    notifyListeners();

    try {
      final api = await _api();
      await _pollAndApply(m, jobId, api);
    } on JobNotFoundException {
      // Hasil di server sudah kedaluwarsa/dihapus -> unggah ulang dari awal.
      m.serverJobId = null;
      if (m.id != null) _active.remove(m.id);
      await process(m);
      return;
    } catch (e) {
      m
        ..status = MeetingStatus.failed
        ..error = _friendlyError(e);
      _touch(m);
    } finally {
      if (m.id != null) _active.remove(m.id);
    }
  }

  /// Poll job sampai selesai sambil memperbarui progres, lalu simpan hasilnya.
  Future<void> _pollAndApply(Meeting m, String jobId, ApiClient api) async {
    final result = await api.pollUntilDone(
      jobId,
      onUpdate: (r) {
        final statusChanged = m.status != r.status;
        m
          ..status = r.status
          ..processProgress = r.progress
          ..stageLabel = r.stageLabel
          ..etaSeconds = r.etaSeconds;
        if (statusChanged) {
          _touch(m); // simpan perubahan status ke DB + notify
        } else {
          notifyListeners(); // progres transien: cukup refresh UI
        }
      },
      onReconnecting: (attempt) {
        m.stageLabel = 'Menyambungkan ulang… (percobaan $attempt)';
        notifyListeners();
      },
    );

    if (result.status == MeetingStatus.done) {
      m
        ..status = MeetingStatus.done
        ..transcript = result.transcript
        ..summary = result.summary
        ..processingSeconds = result.processingSeconds
        ..serverJobId = null // selesai — tak perlu disimpan lagi
        ..stageLabel = null
        ..etaSeconds = null;
      // Isi durasi audio dari Whisper bila belum ada (mis. file impor).
      if (result.audioSeconds != null && result.audioSeconds! > 0) {
        m.durationSeconds = result.audioSeconds!;
      }
    } else {
      m
        ..status = MeetingStatus.failed
        ..error = result.error ?? 'Pemrosesan gagal di server';
    }
    _touch(m);
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('timeout')) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi & URL server di Pengaturan.';
    }
    return s;
  }
}
