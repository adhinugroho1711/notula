import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/responsive.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  final _keyController = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      Settings.instance.getServerUrl(),
      Settings.instance.getApiKey(),
    ]).then((v) {
      setState(() {
        _controller.text = v[0];
        _keyController.text = v[1];
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await Settings.instance.setServerUrl(_controller.text);
    await Settings.instance.setApiKey(_keyController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan disimpan')),
      );
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await Settings.instance.setServerUrl(_controller.text);
      await Settings.instance.setApiKey(_keyController.text);
      final api = ApiClient(_controller.text.trim(),
          apiKey: _keyController.text.trim());
      final health = await api.health();
      setState(() {
        _testOk = true;
        _testResult =
            'Terhubung · Whisper: ${health['whisper_model']} · LLM: ${health['ollama_model']}';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Gagal terhubung: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
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
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(Icons.dns_rounded,
                                size: 18, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 10),
                          const Text('URL Server',
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          hintText: 'http://IP-SERVER:8000',
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Alamat backend transkripsi & ringkasan. Bisa IP lokal '
                        '(http://IP-SERVER:8000) atau URL publik (ngrok).',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(Icons.key_rounded,
                                size: 18, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 10),
                          const Text('API Key',
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _keyController,
                        autocorrect: false,
                        obscureText: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          hintText: 'Kunci akses server',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Wajib diisi bila server mengaktifkan autentikasi '
                        '(diperlukan saat diakses lewat internet publik).',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _save,
                        child: const Text('Simpan'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                        ),
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: const Text('Tes koneksi'),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_testOk
                              ? AppTheme.statusDone
                              : AppTheme.statusFailed)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testOk
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: _testOk
                              ? AppTheme.statusDone
                              : AppTheme.statusFailed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_testResult!,
                              style: TextStyle(
                                  color: _testOk
                                      ? AppTheme.statusDone
                                      : AppTheme.statusFailed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            ),
    );
  }
}
