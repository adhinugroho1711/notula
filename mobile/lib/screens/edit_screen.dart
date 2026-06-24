import 'package:flutter/material.dart';

import '../models/meeting.dart';
import '../services/meeting_repository.dart';
import '../theme.dart';
import '../widgets/responsive.dart';

/// Layar edit notulen: judul, ikhtisar, tugas penting, garis besar,
/// wawasan cerdas, dan transkrip.
class EditScreen extends StatefulWidget {
  final Meeting meeting;
  const EditScreen({super.key, required this.meeting});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _judul;
  late final TextEditingController _ikhtisar;
  late final TextEditingController _tugas;
  late final TextEditingController _garisBesar;
  late final TextEditingController _wawasan;
  late final TextEditingController _transcript;

  @override
  void initState() {
    super.initState();
    final m = widget.meeting;
    final s = m.summary;
    _title = TextEditingController(text: m.title);
    _judul = TextEditingController(text: s?.judul ?? '');
    _ikhtisar = TextEditingController(text: s?.ikhtisar ?? '');
    _tugas = TextEditingController(text: (s?.tugasPenting ?? []).join('\n'));
    _garisBesar =
        TextEditingController(text: _outlineToText(s?.garisBesar ?? []));
    _wawasan =
        TextEditingController(text: _insightToText(s?.wawasanCerdas ?? []));
    _transcript = TextEditingController(text: m.transcript ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _title, _judul, _ikhtisar, _tugas, _garisBesar, _wawasan, _transcript
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // --- Serialisasi blok (topik di baris sendiri, poin diawali "- ") ---
  static String _outlineToText(List<OutlineSection> secs) => secs
      .map((s) => [s.topik, ...s.poin.map((p) => '- $p')].join('\n'))
      .join('\n\n');

  static String _insightToText(List<Insight> ins) => ins
      .map((w) => ['${w.ikon} ${w.judul}'.trim(), ...w.poin.map((p) => '- $p')]
          .join('\n'))
      .join('\n\n');

  List<String> _lines(TextEditingController c) => c.text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool _isBullet(String l) => l.startsWith('-') || l.startsWith('•');
  String _stripBullet(String l) =>
      l.replaceFirst(RegExp(r'^[-•]\s*'), '').trim();

  List<OutlineSection> _parseOutline(String text) {
    final out = <OutlineSection>[];
    String? topik;
    final poin = <String>[];
    void flush() {
      if (topik != null || poin.isNotEmpty) {
        out.add(OutlineSection(topik: topik ?? '', poin: List.of(poin)));
      }
      topik = null;
      poin.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_isBullet(line)) {
        poin.add(_stripBullet(line));
      } else {
        flush();
        topik = line;
      }
    }
    flush();
    return out;
  }

  List<Insight> _parseInsights(String text) {
    final out = <Insight>[];
    String ikon = '💡';
    String judul = '';
    final poin = <String>[];
    bool started = false;
    void flush() {
      if (started) out.add(Insight(ikon: ikon, judul: judul, poin: List.of(poin)));
      ikon = '💡';
      judul = '';
      poin.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_isBullet(line)) {
        poin.add(_stripBullet(line));
      } else {
        flush();
        started = true;
        final sp = line.indexOf(' ');
        // token pertama dianggap emoji bila pendek (<=3 unit kode)
        if (sp > 0 && sp <= 3) {
          ikon = line.substring(0, sp);
          judul = line.substring(sp + 1).trim();
        } else {
          ikon = '💡';
          judul = line;
        }
      }
    }
    flush();
    return out;
  }

  Future<void> _save() async {
    final m = widget.meeting;
    Summary? summary;
    if (m.summary != null) {
      summary = Summary(
        judul: _judul.text.trim(),
        ikhtisar: _ikhtisar.text.trim(),
        tugasPenting: _lines(_tugas),
        garisBesar: _parseOutline(_garisBesar.text),
        wawasanCerdas: _parseInsights(_wawasan.text),
      );
    }
    await MeetingRepository.instance.updateContent(
      m,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      transcript: m.transcript != null ? _transcript.text : null,
      summary: summary,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasSummary = widget.meeting.summary != null;
    final hasTranscript = widget.meeting.transcript != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Notulen'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Simpan'),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('Judul catatan', _title),
            if (hasSummary) ...[
              _field('Judul notulen', _judul, maxLines: 2),
              _field('Ikhtisar', _ikhtisar, maxLines: 6),
              _field('Tugas penting (satu per baris)', _tugas, maxLines: 5),
              _field('Garis besar', _garisBesar, maxLines: 14),
              _field('Wawasan cerdas', _wawasan, maxLines: 12),
            ],
            if (hasTranscript) _field('Transkrip', _transcript, maxLines: 14),
            const SizedBox(height: 12),
            Text(
              'Tip: pada "Garis besar" & "Wawasan cerdas", tulis judul topik di '
              'baris sendiri, lalu poin-poinnya diawali "- ". Pisahkan antar-topik '
              'dengan baris kosong. Untuk wawasan, boleh awali judul dengan emoji.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            maxLines: maxLines,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
