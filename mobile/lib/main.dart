// Dialog tutup dipicu dari navigatorKey global (bukan widget yg bisa ter-dispose).
// ignore_for_file: use_build_context_synchronously
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/splash_screen.dart';
import 'services/meeting_repository.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

bool get _isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await MeetingRepository.instance.load();

  // Desktop: cegah tutup langsung agar bisa konfirmasi (terutama saat ada proses).
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const NotulaApp());
}

class NotulaApp extends StatefulWidget {
  const NotulaApp({super.key});

  @override
  State<NotulaApp> createState() => _NotulaAppState();
}

class _NotulaAppState extends State<NotulaApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  /// Dipicu saat tombol tutup jendela ditekan (desktop).
  @override
  void onWindowClose() async {
    if (!await windowManager.isPreventClose()) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      await windowManager.destroy();
      return;
    }
    final busy = MeetingRepository.instance.isBusy;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Tutup Notula?'),
        content: Text(busy
            ? 'Masih ada proses konversi yang sedang berjalan/antri. '
                'Jika ditutup sekarang, proses tersebut akan dibatalkan. '
                'Yakin ingin keluar?'
            : 'Yakin ingin menutup aplikasi?'),
        actions: [
          // Tombol Tutup (aksi keluar) — sengaja BUKAN default, harus diklik.
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(busy ? 'Tutup & batalkan' : 'Tutup',
                style: TextStyle(color: AppTheme.statusFailed)),
          ),
          // Batal = tombol utama + autofocus → Enter tidak menutup aplikasi.
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notula',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}
