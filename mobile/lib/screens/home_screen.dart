import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/meeting.dart';
import '../services/export_service.dart';
import '../services/meeting_repository.dart';
import '../theme.dart';
import '../widgets/export_format.dart';
import '../widgets/responsive.dart';
import 'detail_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = MeetingRepository.instance;

  bool _selectMode = false;
  final Set<int> _selected = {};

  String _query = '';
  _SortMode _sort = _SortMode.newest;

  /// Daftar meeting setelah difilter (pencarian) & diurutkan.
  List<Meeting> _visible(List<Meeting> all) {
    final q = _query.trim().toLowerCase();
    var list = all;
    if (q.isNotEmpty) {
      list = all.where((m) {
        final judul = m.summary?.judul ?? '';
        final ikh = m.summary?.ikhtisar ?? '';
        return m.title.toLowerCase().contains(q) ||
            judul.toLowerCase().contains(q) ||
            ikh.toLowerCase().contains(q);
      }).toList();
    } else {
      list = List.of(all);
    }
    switch (_sort) {
      case _SortMode.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortMode.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _SortMode.title:
        list.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  void _enterSelect(Meeting m) {
    setState(() {
      _selectMode = true;
      if (m.id != null) _selected.add(m.id!);
    });
  }

  void _toggleSelect(Meeting m) {
    if (m.id == null) return;
    setState(() {
      if (_selected.contains(m.id)) {
        _selected.remove(m.id);
      } else {
        _selected.add(m.id!);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  List<Meeting> get _selectedMeetings =>
      _repo.meetings.where((m) => _selected.contains(m.id)).toList();

  Future<void> _deleteSelected() async {
    final items = _selectedMeetings;
    if (items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${items.length} item?'),
        content: const Text('Rekaman dan hasilnya akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusFailed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.removeMany(items);
    _exitSelect();
  }

  Future<void> _exportSelected() async {
    final items = _selectedMeetings.where((m) => m.summary != null).toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada hasil selesai untuk diekspor.')));
      return;
    }
    final fmt = await showExportFormatPicker(context);
    if (fmt == null || !mounted) return;
    try {
      final n = await exportMany(items, fmt);
      if (!mounted || n < 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n file .${fmt.ext} tersimpan.')));
      _exitSelect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal ekspor: $e')));
    }
  }

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

  void _onChange() => setState(() {});

  Future<void> _startRecording() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    );
  }

  Future<void> _importFile() async {
    const group = XTypeGroup(
      label: 'Rekaman meeting',
      extensions: [
        'm4a', 'aac', 'wav', 'mp3', 'ogg', 'flac', 'webm', 'opus',
        'mp4', 'mov', 'mkv', 'm4v', 'avi', 'wmv',
      ],
    );
    // Bisa pilih BANYAK file sekaligus → semuanya masuk antrian (berurutan).
    final List<XFile> files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;

    Meeting? first;
    for (final file in files) {
      final name = p.basenameWithoutExtension(file.path);
      final meeting = await _repo.addImported(title: name, filePath: file.path);
      first ??= meeting;
      // ignore: unawaited_futures
      _repo.enqueue(meeting);
    }
    if (!mounted) return;

    if (files.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailScreen(meeting: first!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${files.length} file ditambahkan ke antrian — diproses satu per satu.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meetings = _repo.meetings;
    final shown = _visible(meetings);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ResponsiveCenter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _selectMode ? _selectionHeader() : _header(meetings.length),
              if (!_selectMode && meetings.isNotEmpty) _searchSortBar(),
              Expanded(
                child: meetings.isEmpty
                    ? _empty()
                    : (shown.isEmpty
                        ? _noResults()
                        : _list(shown)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _selectMode ? null : _recordFab(),
    );
  }

  Widget _searchSortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Cari judul / isi notulen…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
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
            ),
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Urutkan',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.newest, child: Text('Terbaru')),
              PopupMenuItem(value: _SortMode.oldest, child: Text('Terlama')),
              PopupMenuItem(value: _SortMode.title, child: Text('Judul (A-Z)')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noResults() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Tidak ada hasil untuk "$_query".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
        ),
      );

  Future<void> _renameMeeting(Meeting m) async {
    final ctrl = TextEditingController(text: m.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ubah judul'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Judul rapat'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _repo.updateTitle(m, newTitle.trim());
    }
  }

  void _toggleSelectAll() {
    final all = _repo.meetings
        .where((m) => m.id != null)
        .map((m) => m.id!)
        .toSet();
    setState(() {
      if (all.isNotEmpty && _selected.length >= all.length) {
        _selected.clear(); // semua sudah terpilih → batalkan semua
      } else {
        _selected
          ..clear()
          ..addAll(all); // pilih semua
      }
    });
  }

  Widget _selectionHeader() {
    final total = _repo.meetings.length;
    final allSelected = total > 0 && _selected.length >= total;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Batal pilih',
            onPressed: _exitSelect,
          ),
          Expanded(
            child: Text('${_selected.length} dipilih',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            icon: Icon(
                allSelected
                    ? Icons.remove_done_rounded
                    : Icons.select_all_rounded,
                size: 20),
            label: Text(allSelected ? 'Batal semua' : 'Pilih semua'),
            onPressed: total == 0 ? null : _toggleSelectAll,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Ekspor .txt ke folder',
            onPressed: _selected.isEmpty ? null : _exportSelected,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Hapus',
            color: AppTheme.statusFailed,
            onPressed: _selected.isEmpty ? null : _deleteSelected,
          ),
        ],
      ),
    );
  }

  Widget _header(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.softShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/icon/notula.png',
                  width: 44, height: 44, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notula',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E1B2E),
                        letterSpacing: -0.5)),
                Text(
                  count == 0 ? 'Notulen rapat otomatis' : '$count rekaman',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (count > 0)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Pilih (hapus / ekspor banyak)',
              onPressed: () => setState(() => _selectMode = true),
            ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Impor rekaman',
            onPressed: _importFile,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.12),
                    AppTheme.accent.withValues(alpha: 0.12),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_none_rounded,
                  size: 56, color: AppTheme.primary),
            ),
            const SizedBox(height: 24),
            const Text('Belum ada rekaman',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Ketuk tombol di bawah untuk\nmerekam meeting pertama Anda',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
          ],
        ),
      );

  Widget _list(List<Meeting> meetings) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: meetings.length,
      itemBuilder: (context, i) {
        final m = meetings[i];
        return _MeetingCard(
          meeting: m,
          selectMode: _selectMode,
          selected: _selected.contains(m.id),
          onTap: () {
            if (_selectMode) {
              _toggleSelect(m);
            } else {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DetailScreen(meeting: m)));
            }
          },
          onLongPress: () => _selectMode ? _toggleSelect(m) : _enterSelect(m),
          onRename: () => _renameMeeting(m),
          onDelete: () => _repo.remove(m),
        );
      },
    );
  }

  Widget _recordFab() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.recordGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.statusFailed.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _startRecording,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('Rekam',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool selectMode;
  final bool selected;
  const _MeetingCard({
    required this.meeting,
    required this.onTap,
    this.onLongPress,
    this.onRename,
    this.onDelete,
    this.selectMode = false,
    this.selected = false,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus rekaman?'),
        content: Text('"${meeting.title}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusFailed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy • HH:mm', 'id_ID');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
        border: selected
            ? Border.all(color: AppTheme.primary, width: 2)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (selectMode) ...[
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppTheme.primary : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 12),
                ],
                _statusAvatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meeting.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15.5)),
                      const SizedBox(height: 4),
                      Text(
                        '${df.format(meeting.createdAt)}  ·  ${_fmtDuration(meeting.durationSeconds)}',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      _statusPill(),
                    ],
                  ),
                ),
                if (selectMode)
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400)
                else
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: Colors.grey.shade500),
                    tooltip: 'Opsi',
                    onSelected: (v) {
                      if (v == 'rename') onRename?.call();
                      if (v == 'delete') _confirmDelete(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Ubah judul'))),
                      PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline_rounded),
                              title: Text('Hapus'))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({Color color, IconData icon}) get _style {
    if (meeting.queued) {
      return (color: AppTheme.statusProcessing, icon: Icons.hourglass_empty_rounded);
    }
    return switch (meeting.status) {
      MeetingStatus.done =>
        (color: AppTheme.statusDone, icon: Icons.check_rounded),
      MeetingStatus.failed =>
        (color: AppTheme.statusFailed, icon: Icons.priority_high_rounded),
      _ when meeting.status.isProcessing =>
        (color: AppTheme.statusProcessing, icon: Icons.sync_rounded),
      _ => (color: AppTheme.statusRecorded, icon: Icons.mic_rounded),
    };
  }

  Widget _statusAvatar() {
    final s = _style;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: (meeting.status.isProcessing && !meeting.queued)
          ? Padding(
              padding: const EdgeInsets.all(13),
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: s.color),
            )
          : Icon(s.icon, color: s.color, size: 24),
    );
  }

  Widget _statusPill() {
    final s = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_pillLabel,
          style: TextStyle(
              color: s.color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  /// Label chip: tambahkan persen saat sedang diproses.
  String get _pillLabel {
    if (meeting.queued) {
      final pos = MeetingRepository.instance.queuePosition(meeting);
      return pos > 0 ? 'Antrian ke-$pos' : 'Menunggu antrian';
    }
    if (meeting.status == MeetingStatus.uploading && meeting.uploadProgress > 0) {
      return 'Mengunggah ${(meeting.uploadProgress * 100).toStringAsFixed(0)}%';
    }
    if (meeting.status.isProcessing && meeting.processProgress > 0) {
      return '${meeting.status.label} ${(meeting.processProgress * 100).toStringAsFixed(0)}%';
    }
    return meeting.status.label;
  }
}

String _fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Mode pengurutan daftar rekaman.
enum _SortMode { newest, oldest, title }
