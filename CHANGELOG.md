# Changelog

Semua perubahan penting pada proyek **Notula** didokumentasikan di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/), penomoran [SemVer](https://semver.org/).

## [1.12.1] — 2026-06-30
### Ditambahkan
- Tombol **"Pilih semua"** / "Batal semua" di mode pilih — hapus atau ekspor **semua** rekaman sekaligus (tidak hanya satu per satu atau pilih manual).

## [1.12.0] — 2026-06-30
### Ditambahkan
- **Rekam audio sistem + mikrofon native (macOS 13+)** — opsi sumber audio "🔊 Audio sistem + mikrofon" merekam suara semua peserta Zoom/Teams/Meet **digabung** dengan suara Anda, **tanpa perlu BlackHole/VB-Cable**. Memakai ScreenCaptureKit + AVAudioEngine via platform channel. Saat pertama dipakai, macOS meminta izin **Perekaman Layar**.

## [1.11.2] — 2026-06-29
### Diubah
- **Panduan Sumber Audio lebih jelas**: dropdown menandai tiap perangkat (`· mikrofon` / `· audio sistem`), dan ada panduan per-skenario — **rapat tatap muka/tanpa Zoom → "Default sistem (mikrofon)"**, **rapat online → perangkat loopback** (disebut langsung namanya bila terdeteksi, mis. "BlackHole 2ch").

## [1.11.1] — 2026-06-29
### Diperbaiki
- Layar **Rekam**: tombol rekam & label "Siap merekam" tidak lagi terpotong setelah penambahan pemilih sumber audio — kontrol kini disematkan di bawah dan bagian tengah bisa di-scroll.

## [1.11.0] — 2026-06-25
### Ditambahkan
- **Pemilih perangkat input** di layar Rekam — pilih mikrofon **atau perangkat loopback** (BlackHole di macOS / VB-Cable di Windows) untuk **menangkap audio sistem** saat merekam rapat online (Zoom/Teams/Meet) tanpa harus jadi host.
### Catatan
- Indikator "suara terdeteksi/tidak" yang berkedip saat merekam Zoom **bukan bug**: perekaman default hanya menangkap mikrofon; suara peserta lain lewat speaker/headphone. Gunakan perangkat loopback (lihat di atas) atau impor rekaman.

## [1.10.0] — 2026-06-24
### Ditambahkan
- **Rekam "simpan-dulu"**: setelah berhenti merekam, file langsung tersimpan di perangkat dan muncul pilihan **"Proses sekarang"** atau **"Nanti"** — tidak lagi auto-upload, sehingga rekaman aman bila jaringan bermasalah.
- Tampilan **"Proses sekarang"** untuk rekaman yang belum dikonversi (proses kapan saja saat jaringan stabil).

## [1.9.0] — 2026-06-24
### Ditambahkan
- **Durasi audio** ditampilkan berdampingan dengan **lama konversi** (di header detail & ekspor `.txt`).
- Durasi file impor kini akurat (diisi otomatis dari Whisper, sebelumnya 0).

## [1.8.0 – 1.8.2] — 2026-06-23
### Ditambahkan
- **Splash screen** saat aplikasi dibuka (memakai poster aplikasi).
- **Logo asli** dipakai pada header.
- **Konfirmasi saat menutup** aplikasi (peringatan khusus bila masih ada proses berjalan/antri); tombol default **Batal** agar tidak tertutup karena Enter.

## [1.7.0] — 2026-06-23
### Ditambahkan
- **Lama proses konversi** (waktu transkrip + ringkas di server) dicatat & ditampilkan.

## [1.6.0 – 1.6.1] — 2026-06-23
### Ditambahkan
- **Hapus massal** (mode pilih: hapus banyak rekaman sekaligus).
- **Ekspor notulen ke `.txt`** (per item & banyak item ke satu folder). Sejak 1.6.1, ekspor berisi **notulen saja** (tanpa transkrip).

## [1.5.0] — 2026-06-23
### Ditambahkan
- **Antrian multi-file**: impor banyak file sekaligus, diproses berurutan (FIFO sesuai urutan upload) dengan nomor antrian terlihat.

## [1.4.0] — 2026-06-22
### Diubah
- **Format notulen baru** yang lebih kaya & rapi: **Judul · Ikhtisar · Tugas Penting · Garis Besar · Wawasan Cerdas** (dengan emoji), menggantikan format lama.

## [1.3.0] — 2026-06-22
### Ditambahkan
- Bagian **Pembahasan** — uraian mendetail per topik (konteks, angka, alasan, kesepakatan).

## [1.2.0] — 2026-06-22
### Ditambahkan
- **Progress transkrip real-time** (persen + estimasi sisa waktu) untuk semua tahap.
- **Tahan koneksi putus**: `job_id` disimpan, polling otomatis menyambung ulang, auto-resume saat app dibuka, tombol "Coba lagi" pintar.
### Diubah
- STT ke **`large-v3-turbo`** (lebih cepat).
### Diperbaiki
- Diarisasi tidak lagi memblokir API (dijalankan di proses terpisah).

## [1.1.0] — 2026-06-21
### Ditambahkan
- UI modern, **indikator level suara mikrofon** real-time, **impor file** (audio/video), **progress upload**, ikon aplikasi, layout responsif.
- Installer macOS (`.dmg`) & skrip installer Windows (Inno Setup).

## [1.0.0] — 2026-06-19
### Ditambahkan
- Rilis awal: **rekam meeting → transkrip (faster-whisper) → notulen terstruktur (Ollama)**.
- Riwayat lokal (SQLite), edit & bagikan hasil, backend FastAPI stateless via Docker.

---

### Catatan backend (lintas versi)
- Model LLM: `qwen3` → `gemma3:12b` → **`gemma4:12b`** (kualitas notulen terbaik untuk GPU 12 GB).
- **Anti-halusinasi Whisper**: `condition_on_previous_text=false`, ambang `compression_ratio`/`log_prob`/`no_speech`, `hallucination_silence_threshold`.
- **Diarisasi dimatikan** secara default (lambat di CPU & label kurang akurat; format notulen tidak memerlukannya).
- `OLLAMA_NUM_CTX` dinaikkan ke **8192** (ringkasan rapat pendek-menengah sekali jalan).
- Backend **stateless**: audio dihapus setelah proses + folder upload dibersihkan saat startup.
