import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/meeting.dart';

/// Format ekspor notulen.
enum ExportFormat { txt, markdown, pdf }

extension ExportFormatX on ExportFormat {
  String get ext => switch (this) {
        ExportFormat.txt => 'txt',
        ExportFormat.markdown => 'md',
        ExportFormat.pdf => 'pdf',
      };
  String get label => switch (this) {
        ExportFormat.txt => 'Teks (.txt)',
        ExportFormat.markdown => 'Markdown (.md)',
        ExportFormat.pdf => 'PDF (.pdf)',
      };
}

String _meta(Meeting m) {
  final df = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID');
  String fmt(int sec) => sec < 60
      ? '$sec detik'
      : (sec % 60 == 0 ? '${sec ~/ 60} menit' : '${sec ~/ 60} menit ${sec % 60} detik');
  final parts = [df.format(m.createdAt)];
  if (m.durationSeconds > 0) parts.add('Durasi ${fmt(m.durationSeconds)}');
  if (m.processingSeconds != null) parts.add('Konversi ${fmt(m.processingSeconds!)}');
  return parts.join('  •  ');
}

String _title(Meeting m) =>
    (m.summary?.judul.isNotEmpty ?? false) ? m.summary!.judul : m.title;

/// Teks notulen polos (.txt) — opsional dengan transkrip penuh.
String buildNotulenText(Meeting m, {bool includeTranscript = true}) {
  final s = m.summary;
  const sep = '\n----------\n';
  final b = StringBuffer()
    ..writeln(_title(m))
    ..writeln(_meta(m));
  if (s != null) {
    if (s.ikhtisar.isNotEmpty) b..writeln(sep)..writeln('IKHTISAR\n')..writeln(s.ikhtisar);
    if (s.tugasPenting.isNotEmpty) {
      b..writeln(sep)..writeln('TUGAS PENTING\n');
      for (final t in s.tugasPenting) { b.writeln(' • $t'); }
    }
    if (s.garisBesar.isNotEmpty) {
      b..writeln(sep)..writeln('GARIS BESAR\n');
      for (final g in s.garisBesar) {
        if (g.topik.isNotEmpty) b.writeln(g.topik);
        for (final p in g.poin) { b.writeln(' • $p'); }
        b.writeln();
      }
    }
    if (s.wawasanCerdas.isNotEmpty) {
      b..writeln(sep)..writeln('WAWASAN CERDAS\n');
      for (final w in s.wawasanCerdas) {
        b.writeln('${w.ikon} ${w.judul}');
        for (final p in w.poin) { b.writeln(' • $p'); }
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

/// Notulen dalam format Markdown.
String buildMarkdown(Meeting m) {
  final s = m.summary;
  final b = StringBuffer()
    ..writeln('# ${_title(m)}')
    ..writeln()
    ..writeln('*${_meta(m)}*');
  if (s != null) {
    if (s.ikhtisar.isNotEmpty) b..writeln('\n## Ikhtisar\n')..writeln(s.ikhtisar);
    if (s.tugasPenting.isNotEmpty) {
      b.writeln('\n## Tugas Penting\n');
      for (final t in s.tugasPenting) { b.writeln('- $t'); }
    }
    if (s.garisBesar.isNotEmpty) {
      b.writeln('\n## Garis Besar');
      for (final g in s.garisBesar) {
        if (g.topik.isNotEmpty) b.writeln('\n### ${g.topik}');
        for (final p in g.poin) { b.writeln('- $p'); }
      }
    }
    if (s.wawasanCerdas.isNotEmpty) {
      b.writeln('\n## Wawasan Cerdas');
      for (final w in s.wawasanCerdas) {
        b.writeln('\n### ${w.ikon} ${w.judul}');
        for (final p in w.poin) { b.writeln('- $p'); }
      }
    }
  }
  b..writeln('\n---')..writeln('*dibuat dengan Notula*');
  return b.toString();
}

/// Notulen sebagai PDF (bytes).
Future<Uint8List> buildPdfBytes(Meeting m) async {
  final s = m.summary;
  final doc = pw.Document();
  final widgets = <pw.Widget>[
    pw.Text(_title(m),
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Text(_meta(m),
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
    pw.Divider(),
  ];

  pw.Widget heading(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(t,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
  pw.Widget bullet(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
      child: pw.Text('•  $t', style: const pw.TextStyle(fontSize: 11)));

  if (s != null) {
    if (s.ikhtisar.isNotEmpty) {
      widgets..add(heading('Ikhtisar'))
        ..add(pw.Text(s.ikhtisar, style: const pw.TextStyle(fontSize: 11)));
    }
    if (s.tugasPenting.isNotEmpty) {
      widgets.add(heading('Tugas Penting'));
      widgets.addAll(s.tugasPenting.map(bullet));
    }
    if (s.garisBesar.isNotEmpty) {
      widgets.add(heading('Garis Besar'));
      for (final g in s.garisBesar) {
        if (g.topik.isNotEmpty) {
          widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
              child: pw.Text(g.topik,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold))));
        }
        widgets.addAll(g.poin.map(bullet));
      }
    }
    if (s.wawasanCerdas.isNotEmpty) {
      widgets.add(heading('Wawasan Cerdas'));
      for (final w in s.wawasanCerdas) {
        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
            child: pw.Text(w.judul,
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))));
        widgets.addAll(w.poin.map(bullet));
      }
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => widgets,
    footer: (_) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('dibuat dengan Notula',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
    ),
  ));
  return doc.save();
}

String _safeName(Meeting m) {
  final cleaned = _title(m).replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), ' ').trim();
  final short = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return short.isEmpty ? 'notula' : short;
}

Future<void> _write(String path, ExportFormat fmt, Meeting m) async {
  switch (fmt) {
    case ExportFormat.txt:
      await File(path).writeAsString(buildNotulenText(m, includeTranscript: false));
    case ExportFormat.markdown:
      await File(path).writeAsString(buildMarkdown(m));
    case ExportFormat.pdf:
      await File(path).writeAsBytes(await buildPdfBytes(m));
  }
}

/// Ekspor satu notulen (dialog Simpan). Return path, atau null bila dibatalkan.
Future<String?> exportSingle(Meeting m, ExportFormat fmt) async {
  final location = await getSaveLocation(
    suggestedName: '${_safeName(m)}.${fmt.ext}',
    acceptedTypeGroups: [
      XTypeGroup(label: fmt.label, extensions: [fmt.ext]),
    ],
  );
  if (location == null) return null;
  final path = location.path.toLowerCase().endsWith('.${fmt.ext}')
      ? location.path
      : '${location.path}.${fmt.ext}';
  await _write(path, fmt, m);
  return path;
}

/// Ekspor banyak notulen ke satu folder. Return jumlah berhasil (-1 bila batal).
Future<int> exportMany(List<Meeting> items, ExportFormat fmt) async {
  final dir = await getDirectoryPath();
  if (dir == null) return -1;
  var count = 0;
  final used = <String>{};
  for (final m in items) {
    final name = _safeName(m);
    var candidate = name;
    var n = 1;
    while (used.contains('$candidate.${fmt.ext}')) {
      candidate = '$name ($n)';
      n++;
    }
    used.add('$candidate.${fmt.ext}');
    try {
      await _write('$dir/$candidate.${fmt.ext}', fmt, m);
      count++;
    } catch (_) {}
  }
  return count;
}
