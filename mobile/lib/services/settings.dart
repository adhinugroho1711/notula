import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan konfigurasi sederhana (URL server + API key).
class Settings {
  Settings._();
  static final Settings instance = Settings._();

  static const _kServerUrl = 'server_url';
  static const _kApiKey = 'api_key';

  // API key default — KOSONG. Isi di layar Pengaturan sesuai API_KEY server Anda.
  static const defaultApiKey = '';

  /// Default URL server. Ubah di layar Pengaturan sesuai alamat backend Anda
  /// (mis. http://IP-SERVER:8000, atau http://localhost:8000 bila pakai tunnel).
  static String get defaultServerUrl => 'http://localhost:8000';

  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrl) ?? defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, url.trim());
  }

  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? defaultApiKey;
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key.trim());
  }
}
