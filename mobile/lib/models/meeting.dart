import 'dart:convert';

/// Status pemrosesan satu meeting.
enum MeetingStatus {
  recorded, // sudah direkam, belum diupload
  uploading, // sedang upload ke server
  transcribing, // server sedang transkrip
  summarizing, // server sedang meringkas
  done, // selesai, ada transkrip + ringkasan
  failed, // gagal di salah satu tahap
}

extension MeetingStatusLabel on MeetingStatus {
  String get label => switch (this) {
        MeetingStatus.recorded => 'Belum diproses',
        MeetingStatus.uploading => 'Mengunggah…',
        MeetingStatus.transcribing => 'Mentranskrip…',
        MeetingStatus.summarizing => 'Meringkas…',
        MeetingStatus.done => 'Selesai',
        MeetingStatus.failed => 'Gagal',
      };

  bool get isProcessing =>
      this == MeetingStatus.uploading ||
      this == MeetingStatus.transcribing ||
      this == MeetingStatus.summarizing;
}

/// Satu topik pada Garis Besar: judul topik + poin-poin detail.
class OutlineSection {
  final String topik;
  final List<String> poin;

  const OutlineSection({required this.topik, this.poin = const []});

  factory OutlineSection.fromJson(Map<String, dynamic> j) => OutlineSection(
        topik: (j['topik'] ?? '').toString(),
        poin: Summary._strList(j['poin']),
      );

  Map<String, dynamic> toJson() => {'topik': topik, 'poin': poin};
}

/// Satu butir Wawasan Cerdas: emoji + tema + poin-poin.
class Insight {
  final String ikon;
  final String judul;
  final List<String> poin;

  const Insight({this.ikon = '💡', required this.judul, this.poin = const []});

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        ikon: (j['ikon'] ?? '💡').toString(),
        judul: (j['judul'] ?? '').toString(),
        poin: Summary._strList(j['poin']),
      );

  Map<String, dynamic> toJson() => {'ikon': ikon, 'judul': judul, 'poin': poin};
}

/// Notulen terstruktur kaya hasil LLM (Judul, Ikhtisar, Tugas Penting,
/// Garis Besar, Wawasan Cerdas).
class Summary {
  final String judul;
  final String ikhtisar;
  final List<String> tugasPenting;
  final List<OutlineSection> garisBesar;
  final List<Insight> wawasanCerdas;

  const Summary({
    this.judul = '',
    required this.ikhtisar,
    this.tugasPenting = const [],
    this.garisBesar = const [],
    this.wawasanCerdas = const [],
  });

  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
        judul: (j['judul'] ?? '').toString(),
        // toleran ke skema lama: 'ringkasan' jadi 'ikhtisar'
        ikhtisar: (j['ikhtisar'] ?? j['ringkasan'] ?? '').toString(),
        tugasPenting: _strList(j['tugas_penting']),
        garisBesar: (j['garis_besar'] as List? ?? [])
            .whereType<Map>()
            .map((e) => OutlineSection.fromJson(e.cast<String, dynamic>()))
            .toList(),
        wawasanCerdas: (j['wawasan_cerdas'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Insight.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'judul': judul,
        'ikhtisar': ikhtisar,
        'tugas_penting': tugasPenting,
        'garis_besar': garisBesar.map((e) => e.toJson()).toList(),
        'wawasan_cerdas': wawasanCerdas.map((e) => e.toJson()).toList(),
      };

  static List<String> _strList(dynamic v) =>
      (v as List? ?? []).map((e) => e.toString()).toList();
}

/// Entri meeting yang tersimpan di SQLite.
class Meeting {
  final int? id;
  String title;
  final DateTime createdAt;
  final String audioPath;
  // Durasi audio (detik). Untuk impor awalnya 0, lalu diisi dari Whisper saat selesai.
  int durationSeconds;
  MeetingStatus status;
  String? transcript;
  Summary? summary;
  String? error;

  /// ID job di server (disimpan agar bisa melanjutkan/poll ulang setelah
  /// koneksi putus atau aplikasi dibuka kembali).
  String? serverJobId;

  /// Lama proses konversi di server (detik) — transkrip + ringkas.
  int? processingSeconds;

  /// Progres unggah 0..1 (transien, tidak disimpan ke DB).
  double uploadProgress = 0;

  /// Progres pemrosesan di server 0..1, teks tahap, dan estimasi sisa (detik).
  /// Semua transien (tidak disimpan ke DB).
  double processProgress = 0;
  String? stageLabel;
  int? etaSeconds;

  /// Sedang menunggu giliran di antrian pemrosesan (transien).
  bool queued = false;

  Meeting({
    this.id,
    required this.title,
    required this.createdAt,
    required this.audioPath,
    required this.durationSeconds,
    this.status = MeetingStatus.recorded,
    this.transcript,
    this.summary,
    this.error,
    this.serverJobId,
    this.processingSeconds,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'audio_path': audioPath,
        'duration_seconds': durationSeconds,
        'status': status.name,
        'transcript': transcript,
        'summary': summary == null ? null : jsonEncode(summary!.toJson()),
        'error': error,
        'server_job_id': serverJobId,
        'processing_seconds': processingSeconds,
      };

  factory Meeting.fromMap(Map<String, dynamic> m) => Meeting(
        id: m['id'] as int?,
        title: m['title'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        audioPath: m['audio_path'] as String,
        durationSeconds: m['duration_seconds'] as int? ?? 0,
        status: MeetingStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => MeetingStatus.recorded,
        ),
        transcript: m['transcript'] as String?,
        summary: m['summary'] == null
            ? null
            : Summary.fromJson(
                jsonDecode(m['summary'] as String) as Map<String, dynamic>),
        error: m['error'] as String?,
        serverJobId: m['server_job_id'] as String?,
        processingSeconds: m['processing_seconds'] as int?,
      );
}
