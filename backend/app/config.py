"""Konfigurasi backend via environment variable."""
import os

# Model Whisper: small/medium untuk CPU, large-v3 untuk server ber-GPU
WHISPER_MODEL = os.getenv("WHISPER_MODEL", "medium")
WHISPER_DEVICE = os.getenv("WHISPER_DEVICE", "cpu")  # "cuda" jika ada GPU
WHISPER_COMPUTE = os.getenv("WHISPER_COMPUTE", "int8")  # "float16" untuk GPU

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen3:8b")
# Jumlah layer model yang dipaksa ke GPU (99 = semua). Perlu untuk gemma4 di
# Ollama 0.21.0 yang under-estimate VRAM. Kecilkan bila bentrok VRAM dgn Whisper.
OLLAMA_NUM_GPU = int(os.getenv("OLLAMA_NUM_GPU", "99"))
# Ukuran context window LLM (token). 4096 cukup untuk chunk ringkasan & hemat VRAM.
OLLAMA_NUM_CTX = int(os.getenv("OLLAMA_NUM_CTX", "4096"))

# Direktori sementara untuk file audio yang diupload
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/tmp/notula-uploads")

# Job selesai dihapus dari memori setelah TTL (detik) — server stateless
JOB_TTL_SECONDS = int(os.getenv("JOB_TTL_SECONDS", "3600"))

# Autentikasi: jika di-set, setiap request wajib mengirim header X-API-Key yang cocok.
# Kosong = auth nonaktif (hanya untuk pengembangan lokal di jaringan tepercaya).
API_KEY = os.getenv("API_KEY", "")

# Diarisasi pembicara (sherpa-onnx, lokal tanpa token). Label "[Pembicara N]".
DIARIZE = os.getenv("DIARIZE", "true").lower() == "true"
DIARIZE_SEG_MODEL = os.getenv("DIARIZE_SEG_MODEL", "/models/seg.onnx")
DIARIZE_EMB_MODEL = os.getenv("DIARIZE_EMB_MODEL", "/models/emb.onnx")
# Jumlah pembicara: 0 = deteksi otomatis (pakai threshold), >0 = paksa jumlah.
DIARIZE_NUM_SPEAKERS = int(os.getenv("DIARIZE_NUM_SPEAKERS", "0"))
# Ambang clustering kemiripan suara (mode otomatis). MAKIN BESAR = lebih sedikit
# pembicara (lebih banyak digabung). 0.5 terlalu kecil → over-segmentasi
# (mis. 1 rapat terdeteksi 100+ pembicara). 0.7 lebih realistis untuk rapat.
DIARIZE_THRESHOLD = float(os.getenv("DIARIZE_THRESHOLD", "0.8"))
# Durasi minimum (detik) sebuah giliran bicara — buang segmen super-pendek
# (interupsi/"oke"/"iya") yang memicu pembicara palsu & over-segmentasi.
DIARIZE_MIN_ON = float(os.getenv("DIARIZE_MIN_ON", "1.0"))
DIARIZE_MIN_OFF = float(os.getenv("DIARIZE_MIN_OFF", "0.5"))
