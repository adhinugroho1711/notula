"""Job store in-memory + worker yang memproses antrian secara berurutan.

Transkripsi memakan CPU berat, jadi job diproses satu per satu lewat
asyncio.Queue dengan satu worker. Server stateless: file audio dihapus
setelah diproses dan job dipurge setelah TTL.
"""
import asyncio
import logging
import multiprocessing
import os
import time
import uuid
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field

from . import config
from .diarize import diarized_transcript
from .summarize import correct_transcript, summarize_transcript
from .transcribe import transcribe_audio, transcript_text

# Batas panjang transkrip yang dirapikan LLM (hindari output terpotong & latensi tinggi
# pada meeting sangat panjang). ~12000 karakter ≈ rapat 45-60 menit.
MAX_CORRECTION_CHARS = 12000

logger = logging.getLogger(__name__)


# Diarisasi (sherpa-onnx) menahan GIL selama beberapa menit → kalau dijalankan
# di thread, event loop API ikut macet dan SEMUA request (status/health) timeout.
# Jalankan di proses terpisah (spawn, agar tidak mewarisi konteks CUDA Whisper)
# dengan satu worker persisten supaya model diarisasi tetap hangat antar-job.
_diarize_pool: ProcessPoolExecutor | None = None


def _get_diarize_pool() -> ProcessPoolExecutor:
    global _diarize_pool
    if _diarize_pool is None:
        _diarize_pool = ProcessPoolExecutor(
            max_workers=1, mp_context=multiprocessing.get_context("spawn")
        )
    return _diarize_pool


# Bobot tiap tahap terhadap progress keseluruhan (0-100). Dijumlah ~100.
# Transkripsi & diarisasi adalah bagian terlama untuk rapat panjang.
STAGE_WEIGHTS = {
    "transcribe": 50.0,   # 0  -> 50
    "diarize": 20.0,      # 50 -> 70
    "correct": 8.0,       # 70 -> 78
    "summarize": 21.0,    # 78 -> 99
}
_STAGE_BASE = {
    "transcribe": 0.0,
    "diarize": 50.0,
    "correct": 70.0,
    "summarize": 78.0,
}


@dataclass
class Job:
    id: str
    audio_path: str
    language: str = "id"
    status: str = "queued"  # queued | transcribing | summarizing | done | failed
    transcript: str | None = None
    summary: dict | None = None
    error: str | None = None
    # Kemajuan pemrosesan (untuk ditampilkan di UI: persen + estimasi).
    progress: float = 0.0          # 0-100 keseluruhan
    stage_label: str = ""          # teks tahap, mis. "Mentranskrip 45%"
    eta_seconds: int | None = None  # estimasi sisa waktu (detik)
    audio_seconds: float | None = None  # durasi audio (dari Whisper)
    processing_started_at: float | None = None
    finished_at: float | None = None
    created_at: float = field(default_factory=time.time)

    def set_stage(self, stage: str, fraction: float, label: str) -> None:
        """Perbarui progress keseluruhan dari kemajuan satu tahap (fraction 0-1)."""
        fraction = max(0.0, min(1.0, fraction))
        base = _STAGE_BASE[stage]
        self.progress = round(base + STAGE_WEIGHTS[stage] * fraction, 1)
        self.stage_label = label
        # ETA linear sederhana dari progress & waktu berjalan.
        if self.processing_started_at and 1.0 < self.progress < 99.0:
            elapsed = time.time() - self.processing_started_at
            self.eta_seconds = int(elapsed * (100.0 - self.progress) / self.progress)
        else:
            self.eta_seconds = None


_jobs: dict[str, Job] = {}
_queue: asyncio.Queue[str] = asyncio.Queue()


def create_job(audio_path: str, language: str = "id") -> Job:
    job = Job(id=uuid.uuid4().hex, audio_path=audio_path, language=language)
    _jobs[job.id] = job
    _queue.put_nowait(job.id)
    logger.info("Job %s dibuat (antrian: %d)", job.id, _queue.qsize())
    return job


def get_job(job_id: str) -> Job | None:
    return _jobs.get(job_id)


def _cleanup_audio(job: Job) -> None:
    try:
        if os.path.exists(job.audio_path):
            os.remove(job.audio_path)
    except OSError:
        logger.warning("Gagal menghapus file audio %s", job.audio_path)


def _purge_expired() -> None:
    """Hapus job selesai/gagal yang melewati TTL — server tidak menyimpan data."""
    now = time.time()
    expired = [
        jid for jid, job in _jobs.items()
        if job.finished_at and now - job.finished_at > config.JOB_TTL_SECONDS
    ]
    for jid in expired:
        del _jobs[jid]
    if expired:
        logger.info("Purge %d job kedaluwarsa", len(expired))


async def _process(job: Job) -> None:
    try:
        job.processing_started_at = time.time()
        job.status = "transcribing"
        job.set_stage("transcribe", 0.0, "Mempersiapkan transkripsi…")

        def _on_transcribe(done_sec: float, total_sec: float) -> None:
            if total_sec:
                job.audio_seconds = total_sec  # durasi audio diketahui dari Whisper
            frac = done_sec / total_sec if total_sec else 0.0
            job.set_stage("transcribe", frac, f"Mentranskrip {int(frac * 100)}%")

        # faster-whisper blocking — jalankan di thread agar event loop tetap responsif
        segments = await asyncio.to_thread(
            transcribe_audio, job.audio_path, job.language, _on_transcribe
        )
        if not segments:
            raise ValueError("Audio tidak mengandung ucapan yang bisa ditranskrip")

        # Diarisasi pembicara (lokal, opsional) — beri label [Pembicara N].
        # Dijalankan di proses terpisah agar tidak memblokir API selama berjalan.
        if config.DIARIZE:
            job.set_stage("diarize", 0.0, "Memisahkan pembicara…")
            try:
                loop = asyncio.get_running_loop()
                job.transcript = await loop.run_in_executor(
                    _get_diarize_pool(), diarized_transcript, job.audio_path, segments
                )
            except Exception as exc:  # noqa: BLE001 — fallback ke transkrip polos
                logger.warning("Diarisasi gagal, pakai transkrip polos: %s", exc)
                job.transcript = transcript_text(segments)
        else:
            job.transcript = transcript_text(segments)
        job.set_stage("diarize", 1.0, "Memisahkan pembicara…")

        # Rapikan typo/istilah hasil STT sebelum diringkas (transkrip pendek-menengah).
        if len(job.transcript) <= MAX_CORRECTION_CHARS:
            job.set_stage("correct", 0.0, "Merapikan transkrip…")
            job.transcript = await correct_transcript(job.transcript)
        job.set_stage("correct", 1.0, "Merapikan transkrip…")

        job.status = "summarizing"
        job.set_stage("summarize", 0.0, "Meringkas…")

        def _on_summarize(done: int, total: int) -> None:
            frac = done / total if total else 0.0
            label = f"Meringkas bagian {done}/{total}" if total > 1 else "Meringkas…"
            job.set_stage("summarize", frac, label)

        job.summary = await summarize_transcript(job.transcript, _on_summarize)

        job.status = "done"
        job.progress = 100.0
        job.stage_label = "Selesai"
        job.eta_seconds = 0
    except Exception as exc:  # noqa: BLE001 — semua kegagalan dilaporkan ke client
        logger.exception("Job %s gagal", job.id)
        job.status = "failed"
        job.error = str(exc)
    finally:
        job.finished_at = time.time()
        _cleanup_audio(job)


async def worker_loop() -> None:
    """Worker tunggal: proses job satu per satu dari antrian."""
    logger.info("Worker job dimulai")
    while True:
        job_id = await _queue.get()
        _purge_expired()
        job = _jobs.get(job_id)
        if job is not None:
            await _process(job)
        _queue.task_done()


def shutdown() -> None:
    """Tutup process pool diarisasi saat aplikasi berhenti."""
    global _diarize_pool
    if _diarize_pool is not None:
        _diarize_pool.shutdown(wait=False, cancel_futures=True)
        _diarize_pool = None
