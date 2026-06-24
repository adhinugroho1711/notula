<p align="center">
  <img src="docs/hero.png" alt="Notula" width="420">
</p>

<h1 align="center">Notula</h1>

<p align="center">
  Aplikasi perekam rapat → transkrip otomatis → notulen terstruktur, <b>sepenuhnya self-hosted</b>.<br>
  Privasi penuh: audio & hasil tidak pernah keluar dari infrastruktur Anda. Tanpa cloud, tanpa token pihak ketiga.
</p>

---

## ✨ Fitur

- 🎙️ **Rekam langsung** atau **impor file** audio/video (mp4, m4a, wav, mov, mkv, dll — termasuk rekaman Zoom/Teams/Meet).
- 📝 **Transkrip otomatis** (Speech-to-Text) berbahasa Indonesia memakai **faster-whisper** (`large-v3-turbo`) di GPU.
- 🧠 **Notulen terstruktur** via LLM lokal (**Ollama + Gemma**): Judul, Ikhtisar, Tugas Penting, Garis Besar, dan Wawasan Cerdas.
- 📊 **Progress real-time** (persen + estimasi) untuk transkrip & ringkasan, plus **durasi audio** & **lama konversi**.
- 🔁 **Tahan koneksi putus**: rekaman disimpan lokal dulu, antrian upload otomatis menyambung ulang & bisa diproses kapan saja.
- 🗂️ **Antrian multi-file** (FIFO), **hapus massal**, dan **ekspor notulen ke `.txt`**.
- 🖥️ **Desktop-first** (macOS & Windows), riwayat tersimpan lokal (SQLite).
- 🔒 **Stateless backend**: audio dihapus setelah diproses; hasil dipurge setelah TTL.

## 🏗️ Arsitektur

```
┌──────────────────┐   upload audio    ┌─────────────────────────────────────┐
│ Notula (Flutter) │ ───────────────▶ │  Backend FastAPI                     │
│  - rekam / impor │                   │   1. faster-whisper  → transkrip     │
│  - riwayat SQLite│ ◀─────────────── │   2. Ollama (Gemma)  → notulen JSON  │
│  - antrian/upload│   poll progress   └─────────────────────────────────────┘
└──────────────────┘                      Docker (GPU) + Ollama host-native
```

- **Klien**: Flutter (Dart) — satu basis kode untuk macOS, Windows, Linux, Android, iOS.
- **Backend**: FastAPI + antrian in-memory (1 worker), stateless.
- **STT**: faster-whisper (CTranslate2) di GPU CUDA.
- **LLM**: Ollama (model Gemma) di host, otomatis pakai GPU.

## 📂 Struktur Repo

```
.
├── backend/                 # FastAPI + STT + ringkasan
│   ├── app/                 # main.py, jobs.py, transcribe.py, summarize.py, diarize.py, config.py
│   ├── Dockerfile
│   ├── docker-compose.prod.yml
│   └── requirements.txt
├── mobile/                  # Aplikasi Flutter "notula"
│   ├── lib/                 # models, services, screens
│   └── installer/windows/   # skrip Inno Setup (.exe)
├── docs/                    # gambar/aset dokumentasi
└── CHANGELOG.md
```

---

## 🚀 Setup Backend

**Prasyarat:** Linux ber-GPU NVIDIA, Docker + NVIDIA Container Toolkit, dan **Ollama** terpasang native di host.

1. **Siapkan model LLM di Ollama** (host):
   ```bash
   ollama pull gemma4:12b      # atau gemma3:12b (lebih ringan/cepat)
   ```
   > `gemma4:12b` butuh Ollama ≥ 0.30. Cek `ollama --version`.

2. **Konfigurasi `.env`** di `backend/`:
   ```env
   API_KEY=ganti-dengan-kunci-rahasia-anda
   WHISPER_MODEL=large-v3-turbo
   WHISPER_DEVICE=cuda
   WHISPER_COMPUTE=float16
   OLLAMA_URL=http://127.0.0.1:11434
   OLLAMA_MODEL=gemma4:12b
   OLLAMA_NUM_GPU=99
   OLLAMA_NUM_CTX=8192
   DIARIZE=false
   ```

3. **Jalankan**:
   ```bash
   cd backend
   docker compose -f docker-compose.prod.yml up -d --build
   ```

4. **Cek**: `GET http://SERVER:8000/api/health` → `{"status":"ok", ...}` (kirim header `X-API-Key`).

**Endpoint:** `POST /api/jobs` (upload), `GET /api/jobs/{id}` (status/hasil), `GET /api/health`. Semua butuh header `X-API-Key`.

### Parameter penting (env)
| Variabel | Default | Keterangan |
|---|---|---|
| `WHISPER_MODEL` | `large-v3-turbo` | model STT (cepat & akurat); `large-v3` lebih akurat tapi besar |
| `OLLAMA_MODEL` | `gemma4:12b` | model notulen; `gemma3:12b` alternatif lebih cepat |
| `OLLAMA_NUM_GPU` | `99` | jumlah layer LLM ke GPU (turunkan bila VRAM bentrok) |
| `OLLAMA_NUM_CTX` | `8192` | ukuran context LLM |
| `DIARIZE` | `false` | pemisahan pembicara (lambat di CPU, opsional) |

---

## 💻 Setup Aplikasi (Flutter)

**Prasyarat:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable). Untuk build desktop: Xcode (macOS) atau Visual Studio + "Desktop development with C++" (Windows).

```bash
cd mobile
flutter pub get
flutter run -d macos        # atau: -d windows / -d linux
```

**Build rilis:**
```bash
flutter build macos --release      # build/macos/Build/Products/Release/notula.app
flutter build windows --release    # build/windows/x64/runner/Release/  (HARUS di Windows)
```

> `.exe` Windows hanya bisa dibangun **di mesin Windows** (Flutter tidak bisa cross-compile dari macOS). Untuk installer Windows, kompilasi `installer/windows/notula_setup.iss` dengan [Inno Setup](https://jrsoftware.org/isdl.php).

### Konfigurasi di aplikasi
Buka **Pengaturan** di app lalu isi:
- **URL Server** — mis. `http://IP-SERVER:8000` (jaringan internal) atau `http://localhost:8000` (bila pakai SSH tunnel).
- **API Key** — sama dengan `API_KEY` di `.env` backend.

> Default sengaja dikosongkan demi keamanan — wajib diisi sekali; tersimpan di perangkat.

---

## 🔒 Privasi & Keamanan

- **Self-hosted penuh** — tidak ada layanan cloud/pihak ketiga; cocok untuk data sensitif.
- Backend **stateless**: file audio dihapus setelah diproses, hasil dipurge setelah TTL, dan folder upload dibersihkan saat startup.
- Akses dilindungi **API key** (`X-API-Key`).
- Jangan commit `.env`, API key, atau IP server internal (sudah diabaikan via `.gitignore`).

## 📜 Riwayat & Lisensi

Lihat [CHANGELOG.md](CHANGELOG.md) untuk riwayat versi (v1.0.0 → terkini).

Dibangun dengan Flutter, FastAPI, faster-whisper, dan Ollama (Gemma).
