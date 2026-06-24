"""Transkripsi audio ke teks menggunakan faster-whisper."""
import logging
import threading

from faster_whisper import WhisperModel

from . import config

logger = logging.getLogger(__name__)

# Bias pengenalan istilah agar transkrip rapat perbankan lebih akurat
# (mengurangi salah dengar seperti "dana pihak ketiga", "QRIS", dll).
INITIAL_PROMPT = (
    "Transkrip rapat resmi berbahasa Indonesia di lingkungan perbankan. "
    "Istilah yang sering muncul: dana pihak ketiga, kredit usaha kecil, nasabah, "
    "QRIS, mobile banking, anggaran, rekening, tabungan, deposito, suku bunga, "
    "rasio kredit bermasalah, rapat koordinasi, evaluasi kinerja cabang, action item."
)

_model: WhisperModel | None = None
_model_lock = threading.Lock()


def _get_model() -> WhisperModel:
    """Lazy-load model Whisper (sekali saja, thread-safe)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                logger.info(
                    "Memuat model Whisper %s (device=%s, compute=%s)...",
                    config.WHISPER_MODEL, config.WHISPER_DEVICE, config.WHISPER_COMPUTE,
                )
                _model = WhisperModel(
                    config.WHISPER_MODEL,
                    device=config.WHISPER_DEVICE,
                    compute_type=config.WHISPER_COMPUTE,
                )
                logger.info("Model Whisper siap.")
    return _model


def transcribe_audio(
    audio_path: str,
    language: str = "id",
    progress_cb=None,
) -> list[dict]:
    """Transkripsi file audio menjadi daftar segmen {start, end, text}.

    Blocking — jalankan di thread terpisah. `progress_cb(done_sec, total_sec)`
    dipanggil per segmen agar pemanggil bisa menghitung persentase/ETA
    (faster-whisper men-stream segmen seiring proses berjalan).
    """
    model = _get_model()
    segments, info = model.transcribe(
        audio_path,
        language=language,
        vad_filter=True,  # lewati bagian hening — penting untuk rekaman meeting panjang
        initial_prompt=INITIAL_PROMPT,
        temperature=0.0,  # deterministik
        # --- Anti-halusinasi (penting untuk audio rapat: banyak hening/noise) ---
        # Jangan mengondisikan ke teks sebelumnya → cegah loop & frasa "mengarang"
        # yang merembet antar-segmen (penyebab halusinasi #1 di Whisper).
        condition_on_previous_text=False,
        # Buang segmen yang teksnya terlalu berulang (ciri khas halusinasi).
        compression_ratio_threshold=2.4,
        # Buang segmen dengan keyakinan sangat rendah.
        log_prob_threshold=-1.0,
        # Anggap sebagai hening (tanpa teks) bila probabilitas no-speech tinggi.
        no_speech_threshold=0.6,
        # Lewati hening panjang (>2 dtk) yang sering memicu teks mengarang.
        word_timestamps=True,
        hallucination_silence_threshold=2.0,
    )
    total = info.duration or 0.0
    logger.info("Transkripsi dimulai (durasi audio: %.1f detik)", total)
    result = []
    for seg in segments:
        text = seg.text.strip()
        if text:
            result.append({"start": seg.start, "end": seg.end, "text": text})
        if progress_cb is not None and total > 0:
            try:
                progress_cb(min(seg.end, total), total)
            except Exception:  # noqa: BLE001 — progress tidak boleh menggagalkan transkripsi
                pass
    logger.info("Transkripsi selesai (%d segmen)", len(result))
    return result


def transcript_text(segments: list[dict]) -> str:
    """Gabungkan segmen menjadi transkrip teks polos."""
    return "\n".join(s["text"] for s in segments if s["text"])
