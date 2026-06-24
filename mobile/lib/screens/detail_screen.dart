import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/meeting.dart';
import '../services/export_service.dart';
import '../services/meeting_repository.dart';
import '../theme.dart';
import '../widgets/responsive.dart';
import 'edit_screen.dart';

class DetailScreen extends StatefulWidget {
  final Meeting meeting;
  const DetailScreen({super.key, required this.meeting});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _repo = MeetingRepository.instance;
  Meeting get m => widget.meeting;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChange);
  }

  @override
  void dispose() {
    _repo.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditScreen(meeting: m)),
    );
  }

  void _share() => SharePlus.instance
      .share(ShareParams(text: buildNotulenText(m), subject: m.title));

  Future<void> _exportTxt() async {
    try {
      final path = await exportSingleTxt(m);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tersimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus meeting?'),
        content: const Text('Rekaman dan hasilnya akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusFailed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.remove(m);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID');
    final canShare = m.status == MeetingStatus.done;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(m.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit notulen'),
            if (canShare)
              IconButton(
                  onPressed: _exportTxt,
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'Ekspor .txt'),
            if (canShare)
              IconButton(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Bagikan'),
            IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Hapus'),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(df.format(m.createdAt),
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13)),
                      if (m.durationSeconds > 0) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.graphic_eq_rounded,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text('Durasi ${_fmtDur(m.durationSeconds)}',
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 13)),
                      ],
                      if (m.processingSeconds != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.timer_outlined,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text('Konversi ${_fmtDur(m.processingSeconds!)}',
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: AppTheme.brandGradient,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.primary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    splashBorderRadius: BorderRadius.circular(11),
                    padding: const EdgeInsets.all(4),
                    tabs: const [
                      Tab(text: 'Ringkasan'),
                      Tab(text: 'Transkrip'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(children: [_summaryTab(), _transcriptTab()]),
      ),
    );
  }

  Widget _summaryTab() {
    if (m.status == MeetingStatus.failed) return _failedView();
    if (m.status == MeetingStatus.recorded && !m.queued) {
      return _notProcessedView();
    }
    final s = m.summary;
    if (s == null) return _processingView();

    return ResponsiveCenter(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (s.judul.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Text(s.judul,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, height: 1.3)),
          ),
        if (s.ikhtisar.isNotEmpty)
          _card(
            icon: Icons.subject_rounded,
            color: AppTheme.primary,
            title: 'Ikhtisar',
            child: Text(s.ikhtisar,
                style: const TextStyle(height: 1.55, fontSize: 14.5)),
          ),
        if (s.tugasPenting.isNotEmpty)
          _card(
            icon: Icons.task_alt_rounded,
            color: AppTheme.accent,
            title: 'Tugas Penting',
            child: _bullets(s.tugasPenting),
          ),
        if (s.garisBesar.isNotEmpty)
          _card(
            icon: Icons.account_tree_rounded,
            color: const Color(0xFF6366F1),
            title: 'Garis Besar',
            child: _outline(s.garisBesar),
          ),
        if (s.wawasanCerdas.isNotEmpty)
          _card(
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Wawasan Cerdas',
            child: _insights(s.wawasanCerdas),
          ),
      ],
    ),
    );
  }

  Widget _transcriptTab() {
    if (m.status == MeetingStatus.failed) return _failedView();
    if (m.status == MeetingStatus.recorded && !m.queued) {
      return _notProcessedView();
    }
    if (m.transcript == null) return _processingView();
    return ResponsiveCenter(
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: SelectableText(m.transcript!,
            style: const TextStyle(height: 1.6, fontSize: 14.5)),
      ),
      ),
    );
  }

  /// Tampilan untuk rekaman yang sudah tersimpan tapi BELUM diproses.
  Widget _notProcessedView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_upload_outlined,
                    size: 38, color: AppTheme.primary),
              ),
              const SizedBox(height: 18),
              const Text('Rekaman tersimpan, belum diproses',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'File aman di perangkat. Proses (transkrip + ringkasan) saat '
                'jaringan ke server stabil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => _repo.enqueue(m),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Proses sekarang'),
              ),
            ],
          ),
        ),
      );

  Widget _processingView() {
    final uploading = m.status == MeetingStatus.uploading;
    // Saat upload: pakai progres unggah. Saat diproses server: pakai progres server.
    final value = uploading ? m.uploadProgress : m.processProgress;
    final hasBar = value > 0;
    final pct = (value * 100).clamp(0, 100).toStringAsFixed(0);
    final heading = m.queued
        ? 'Menunggu antrian…'
        : uploading
            ? 'Mengunggah… $pct%'
            : (m.stageLabel?.isNotEmpty == true
                ? m.stageLabel!
                : m.status.label);
    final eta = uploading ? null : _formatEta(m.etaSeconds);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasBar) ...[
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 18),
            ],
            Text(heading,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              eta != null
                  ? 'Estimasi sisa $eta'
                  : (uploading
                      ? 'Untuk rekaman panjang, proses ini bisa beberapa saat'
                      : 'Mohon tunggu sebentar'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// Ubah detik → teks ramah ("± 2 mnt 5 dtk"). Null jika tidak ada estimasi.
  String? _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    if (seconds < 60) return '± $seconds dtk';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '± $m mnt' : '± $m mnt $s dtk';
  }

  Widget _failedView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.statusFailed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    size: 40, color: AppTheme.statusFailed),
              ),
              const SizedBox(height: 18),
              Text(m.error ?? 'Pemrosesan gagal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.4)),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                onPressed: () => _repo.retry(m),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _bullets(List<String> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 7),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: AppTheme.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(e,
                              style: const TextStyle(
                                  height: 1.45, fontSize: 14.5))),
                    ],
                  ),
                ))
            .toList(),
      );

  // Garis Besar: judul topik (bold) + poin-poin di bawahnya.
  Widget _outline(List<OutlineSection> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items[i].topik.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(items[i].topik,
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              fontWeight: FontWeight.w700)),
                    ),
                  _bullets(items[i].poin),
                ],
              ),
            ),
        ],
      );

  // Wawasan Cerdas: emoji + tema (bold) + poin-poin.
  Widget _insights(List<Insight> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${items[i].ikon}  ${items[i].judul}',
                        style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w700)),
                  ),
                  _bullets(items[i].poin),
                ],
              ),
            ),
        ],
      );
}

/// Format durasi detik → "X mnt Y dtk" (atau "Y dtk").
String _fmtDur(int seconds) {
  if (seconds < 60) return '$seconds dtk';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m mnt' : '$m mnt $s dtk';
}
