import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../models/meeting.dart';

/// Bangun teks notulen terformat (gaya: Judul · Ikhtisar · Tugas Penting ·
/// Garis Besar · Wawasan Cerdas), opsional dengan transkrip penuh di bawah.
String buildNotulenText(Meeting m, {bool includeTranscript = true}) {
  final df = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID');
  final s = m.summary;
  const sep = '\n----------\n';
  final b = StringBuffer();

  String fmt(int sec) => sec < 60
      ? '$sec detik'
      : (sec % 60 == 0
          ? '${sec ~/ 60} menit'
          : '${sec ~/ 60} menit ${sec % 60} detik');

  b.writeln((s?.judul.isNotEmpty ?? false) ? s!.judul : m.title);
  b.writeln(df.format(m.createdAt));
  if (m.durationSeconds > 0) {
    b.writeln('Durasi rekaman: ${fmt(m.durationSeconds)}');
  }
  if (m.processingSeconds != null) {
    b.writeln('Lama konversi: ${fmt(m.processingSeconds!)}');
  }

  if (s != null) {
    if (s.ikhtisar.isNotEmpty) {
      b..writeln(sep)..writeln('IKHTISAR\n')..writeln(s.ikhtisar);
    }
    if (s.tugasPenting.isNotEmpty) {
      b..writeln(sep)..writeln('TUGAS PENTING\n');
      for (final t in s.tugasPenting) {
        b.writeln(' • $t');
      }
    }
    if (s.garisBesar.isNotEmpty) {
      b..writeln(sep)..writeln('GARIS BESAR\n');
      for (final g in s.garisBesar) {
        if (g.topik.isNotEmpty) b.writeln(g.topik);
        for (final p in g.poin) {
          b.writeln(' • $p');
        }
        b.writeln();
      }
    }
    if (s.wawasanCerdas.isNotEmpty) {
      b..writeln(sep)..writeln('WAWASAN CERDAS\n');
      for (final w in s.wawasanCerdas) {
        b.writeln('${w.ikon} ${w.judul}');
        for (final p in w.poin) {
          b.writeln(' • $p');
        }
        b.writeln();
      }
    }
  }

  if (includeTranscript && (m.transcript?.isNotEmpty ?? false)) {
    b..writeln(sep)..writeln('TRANSKRIP\n')..writeln(m.transcript);
  }

  b..writeln(sep)..writeln('— dibuat dengan Notula —');
  return b.toString();
}

/// Nama file aman dari judul (buang karakter yang tidak valid).
String _safeName(Meeting m) {
  final base = (m.summary?.judul.isNotEmpty ?? false) ? m.summary!.judul : m.title;
  final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), ' ').trim();
  final short = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return short.isEmpty ? 'notula' : short;
}

/// Ekspor satu notulen ke file .txt (dialog Simpan). Return path bila berhasil,
/// null bila dibatalkan.
Future<String?> exportSingleTxt(Meeting m) async {
  final location = await getSaveLocation(
    suggestedName: '${_safeName(m)}.txt',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Teks', extensions: ['txt']),
    ],
  );
  if (location == null) return null;
  final path = location.path.toLowerCase().endsWith('.txt')
      ? location.path
      : '${location.path}.txt';
  // Hanya notulen (tanpa transkrip) — sesuai format ringkas Suara 114.txt.
  await File(path).writeAsString(buildNotulenText(m, includeTranscript: false));
  return path;
}

/// Ekspor banyak notulen ke satu folder (dialog Pilih folder).
/// Return jumlah file yang berhasil ditulis (-1 bila dibatalkan).
Future<int> exportManyTxt(List<Meeting> items) async {
  final dir = await getDirectoryPath();
  if (dir == null) return -1;
  var count = 0;
  final used = <String>{};
  for (final m in items) {
    var name = _safeName(m);
    // hindari tabrakan nama dalam satu folder
    var candidate = name;
    var n = 1;
    while (used.contains('$candidate.txt')) {
      candidate = '$name ($n)';
      n++;
    }
    used.add('$candidate.txt');
    try {
      await File('$dir/$candidate.txt')
          .writeAsString(buildNotulenText(m, includeTranscript: false));
      count++;
    } catch (_) {
      // lewati file yang gagal ditulis
    }
  }
  return count;
}
