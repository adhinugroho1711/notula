import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/meeting_repository.dart';
import '../services/recorder.dart';
import '../theme.dart';
import 'detail_screen.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _recorder = MeetingRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  int _elapsed = 0;
  bool _recording = false;
  bool _paused = false;
  bool _starting = false;
  String? _error;

  // Level suara real-time (0..1, sudah dihaluskan) untuk visual.
  double _level = 0;
  // Berapa detik beruntun tidak ada suara terdeteksi (deteksi mic bermasalah).
  int _silentSeconds = 0;
  bool _everHeard = false;

  static const double _detectThreshold = 0.08; // ambang "ada suara"

  // Perangkat input (mic / loopback seperti BlackHole/VB-Cable).
  List<InputDevice> _devices = [];
  InputDevice? _selectedDevice; // null = default sistem

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final ok = await _recorder.hasPermission();
    if (!ok) return; // daftar device perlu izin mic
    final devs = await _recorder.inputDevices();
    if (!mounted) return;
    setState(() => _devices = devs);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    WakelockPlus.disable();
    _recorder.dispose();
    super.dispose();
  }

  /// Ubah dBFS (amplitudo) menjadi level 0..1.
  double _normalize(double dbfs) {
    const floor = -45.0; // anggap < -45 dB sebagai hening
    final v = ((dbfs - floor) / (0 - floor)).clamp(0.0, 1.0);
    return v;
  }

  void _onAmplitude(Amplitude amp) {
    final target = _paused ? 0.0 : _normalize(amp.current);
    setState(() {
      // smoothing: naik cepat, turun halus
      _level = target > _level
          ? _level + (target - _level) * 0.6
          : _level + (target - _level) * 0.25;
      if (_level > _detectThreshold) _everHeard = true;
    });
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final ok = await _recorder.hasPermission();
    if (!ok) {
      setState(() {
        _starting = false;
        _error = 'Izin mikrofon ditolak. Aktifkan di pengaturan perangkat.';
      });
      return;
    }
    await _recorder.start(device: _selectedDevice);
    await WakelockPlus.enable();
    _ampSub = _recorder.amplitudeStream().listen(_onAmplitude);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      setState(() {
        _elapsed++;
        if (_level < _detectThreshold) {
          _silentSeconds++;
        } else {
          _silentSeconds = 0;
        }
      });
    });
    setState(() {
      _recording = true;
      _starting = false;
    });
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    setState(() {
      _paused = !_paused;
      if (_paused) _level = 0;
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    await WakelockPlus.disable();
    final path = await _recorder.stop();
    if (path == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final defaultTitle =
        'Meeting ${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(DateTime.now())}';
    final meeting = await MeetingRepository.instance.addRecording(
      title: defaultTitle,
      audioPath: path,
      durationSeconds: _elapsed,
    );
    if (!mounted) return;
    // Rekaman sudah TERSIMPAN di perangkat. Tanya: proses sekarang atau nanti
    // (agar tidak hilang bila jaringan bermasalah saat upload).
    final processNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Rekaman tersimpan'),
        content: const Text(
            'Rekaman sudah disimpan di perangkat dan tidak akan hilang.\n\n'
            'Proses sekarang (transkrip + ringkasan), atau nanti saat jaringan '
            'stabil? Anda bisa memprosesnya kapan saja lewat tombol "Proses".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Nanti')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Proses sekarang')),
        ],
      ),
    );
    if (processNow == true) {
      unawaited(MeetingRepository.instance.enqueue(meeting));
    }
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => DetailScreen(meeting: meeting)));
  }

  Widget _devicePicker() {
    final value = _selectedDevice?.id ?? '';
    final loopback =
        _selectedDevice != null && _isLoopback(_selectedDevice!.label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.headset_mic_outlined,
                  size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              const Text('Sumber audio',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Muat ulang daftar perangkat',
                onPressed: _loadDevices,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                items: [
                  const DropdownMenuItem(
                      value: '',
                      child: Text('Default sistem (mikrofon)',
                          overflow: TextOverflow.ellipsis)),
                  ..._devices.map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                          _isLoopback(d.label)
                              ? '${d.label}  ·  audio sistem'
                              : '${d.label}  ·  mikrofon',
                          overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (id) => setState(() {
                  _selectedDevice = (id == null || id.isEmpty)
                      ? null
                      : _devices.firstWhere((d) => d.id == id);
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sourceGuide(loopback),
        ],
      ),
    );
  }

  /// Tebak apakah sebuah perangkat adalah loopback (penangkap audio sistem).
  bool _isLoopback(String label) {
    final l = label.toLowerCase();
    const keys = [
      'blackhole', 'vb-cable', 'vb-audio', 'cable output', 'stereo mix',
      'loopback', 'soundflower', 'voicemeeter', 'aggregate', 'multi-output',
    ];
    return keys.any(l.contains);
  }

  /// Panduan konkret: skenario online vs tatap muka, menyebut nama device asli.
  Widget _sourceGuide(bool loopbackSelected) {
    // cari perangkat loopback yang terdeteksi (untuk disebut namanya)
    final loop = _devices.where((d) => _isLoopback(d.label)).toList();
    final loopName = loop.isNotEmpty ? '"${loop.first.label}"' : null;

    Widget row(IconData ic, Color c, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ic, size: 15, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                    children: [
                      TextSpan(
                          text: '$title: ',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: body),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(Icons.groups_rounded, const Color(0xFF0EA5E9),
            'Rapat tatap muka / tanpa Zoom',
            'pilih "Default sistem (mikrofon)" — menangkap suara di sekitar laptop.'),
        row(Icons.videocam_rounded, AppTheme.primary, 'Rapat online (Zoom/Teams/Meet)',
            loopName != null
                ? 'pilih $loopName (audio sistem) agar suara semua peserta ikut terekam.'
                : 'pasang perangkat loopback (BlackHole di Mac / VB-Cable di Windows), lalu muat ulang (⟳) & pilih di sini. Tanpa itu, hanya mikrofon yang terekam.'),
        if (loopbackSelected)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Pastikan output suara sistem diarahkan ke perangkat ini (mis. Multi-Output Device) agar Anda tetap mendengar rapat.',
              style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                  height: 1.35),
            ),
          ),
      ],
    );
  }

  bool get _soundDetected => _recording && !_paused && _level > _detectThreshold;
  bool get _micProblem =>
      _recording && !_paused && _silentSeconds >= 4; // 4 dtk hening

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rekam Meeting')),
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!_recording) _devicePicker(),
              // Bagian tengah: bisa scroll & terpusat agar tak pernah terpotong.
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 16),
                        _micVisual(),
                        const SizedBox(height: 24),
                        _levelBars(),
                        const SizedBox(height: 28),
                        Text(
                          _fmtElapsed(_elapsed),
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w200,
                            letterSpacing: 1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _statusLabel(),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: AppTheme.statusFailed)),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              // Kontrol rekam — selalu terlihat di bawah.
              _controls(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// Ikon mic dengan halo yang membesar/menyala mengikuti level suara.
  Widget _micVisual() {
    final active = _recording && !_paused;
    final glow = active ? _level : 0.0;
    final haloScale = 1.0 + glow * 0.9; // halo bereaksi terhadap suara
    final baseColor = !_recording
        ? AppTheme.primary
        : (_micProblem ? AppTheme.statusFailed : AppTheme.statusDone);

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // halo terluar (reaktif)
          AnimatedScale(
            scale: haloScale,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: baseColor.withValues(alpha: 0.10 + glow * 0.18),
              ),
            ),
          ),
          // cincin tengah
          AnimatedScale(
            scale: 1.0 + glow * 0.35,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: baseColor.withValues(alpha: 0.16 + glow * 0.2),
              ),
            ),
          ),
          // tombol mic inti
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _recording
                  ? (_micProblem
                      ? AppTheme.recordGradient
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF34D399), Color(0xFF10B981)]))
                  : AppTheme.brandGradient,
              boxShadow: [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.35 + glow * 0.3),
                  blurRadius: 20 + glow * 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              !_recording
                  ? Icons.mic_rounded
                  : (_micProblem ? Icons.mic_off_rounded : Icons.mic_rounded),
              color: Colors.white,
              size: 42,
            ),
          ),
        ],
      ),
    );
  }

  /// Equalizer bars yang bereaksi terhadap level suara.
  Widget _levelBars() {
    const n = 9;
    final active = _recording && !_paused;
    final color = _micProblem ? AppTheme.statusFailed : AppTheme.statusDone;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(n, (i) {
        // pola tinggi: tengah lebih tinggi, plus dipengaruhi level
        final shape = math.sin((i + 1) / (n + 1) * math.pi); // 0..1..0
        final h = active
            ? (6 + _level * 46 * (0.4 + 0.6 * shape))
            : 6.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 6,
          height: h.clamp(6.0, 56.0),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.55 + _level * 0.45)
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _statusLabel() {
    if (!_recording) {
      return Text('Siap merekam',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16));
    }
    if (_paused) {
      return Text('Dijeda',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16));
    }
    if (_micProblem) {
      return Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.warning_amber_rounded,
                  color: AppTheme.statusFailed, size: 18),
              SizedBox(width: 6),
              Text('Tidak ada suara terdeteksi',
                  style: TextStyle(
                      color: AppTheme.statusFailed,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Text('Periksa mikrofon atau dekatkan ke pembicara',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
        ],
      );
    }
    if (_soundDetected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.graphic_eq_rounded,
              color: AppTheme.statusDone, size: 18),
          SizedBox(width: 6),
          Text('Suara terdeteksi',
              style: TextStyle(
                  color: AppTheme.statusDone,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ],
      );
    }
    return Text(_everHeard ? 'Merekam…' : 'Mendengarkan…',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 16));
  }

  Widget _controls() {
    if (!_recording) {
      return _circleButton(
        icon: Icons.fiber_manual_record,
        gradient: AppTheme.recordGradient,
        label: 'Mulai',
        onTap: _starting ? null : _start,
        busy: _starting,
        size: 76,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleButton(
          icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          gradient: AppTheme.brandGradient,
          label: _paused ? 'Lanjut' : 'Jeda',
          onTap: _togglePause,
          size: 64,
        ),
        const SizedBox(width: 40),
        _circleButton(
          icon: Icons.stop_rounded,
          gradient: AppTheme.recordGradient,
          label: 'Selesai',
          onTap: _stop,
          size: 76,
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Gradient gradient,
    required String label,
    required VoidCallback? onTap,
    double size = 72,
    bool busy = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: onTap == null ? null : gradient,
              color: onTap == null ? Colors.grey.shade300 : null,
              boxShadow: onTap == null
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Colors.white))
                : Icon(icon, color: Colors.white, size: size * 0.42),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

String _fmtElapsed(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
