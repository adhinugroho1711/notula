"""Notula backend — transkripsi (faster-whisper) + ringkasan meeting (Ollama)."""
import contextlib
import logging
import os
import uuid
from contextlib import asynccontextmanager

import asyncio

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile

from . import config, jobs
from .summarize import check_ollama


async def require_api_key(x_api_key: str | None = Header(default=None)):
    """Validasi header X-API-Key bila API_KEY di-set di server."""
    if config.API_KEY and x_api_key != config.API_KEY:
        raise HTTPException(status_code=401, detail="API key tidak valid atau tidak ada")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

# Audio + video rekaman meeting (faster-whisper/ffmpeg mengekstrak audionya).
ALLOWED_EXTENSIONS = {
    ".m4a", ".aac", ".wav", ".mp3", ".ogg", ".flac", ".webm", ".opus",
    ".mp4", ".mov", ".mkv", ".m4v", ".avi", ".wmv",  # rekaman Zoom/Teams/Meet
}


def _purge_upload_dir() -> None:
    """Hapus sisa file audio yang mungkin tertinggal akibat proses terputus
    (mis. container di-restart saat job berjalan) — jaga server tetap stateless."""
    try:
        for name in os.listdir(config.UPLOAD_DIR):
            path = os.path.join(config.UPLOAD_DIR, name)
            if os.path.isfile(path):
                os.remove(path)
    except OSError:
        pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    os.makedirs(config.UPLOAD_DIR, exist_ok=True)
    _purge_upload_dir()  # bersihkan sisa upload dari sesi sebelumnya
    worker = asyncio.create_task(jobs.worker_loop())
    yield
    worker.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await worker
    jobs.shutdown()


app = FastAPI(title="Notula API", lifespan=lifespan)


@app.get("/api/health", dependencies=[Depends(require_api_key)])
async def health():
    return {
        "status": "ok",
        "whisper_model": config.WHISPER_MODEL,
        "ollama_model": config.OLLAMA_MODEL,
        "ollama_reachable": await check_ollama(),
    }


@app.post("/api/jobs", status_code=202, dependencies=[Depends(require_api_key)])
async def create_job(
    audio: UploadFile = File(...),
    language: str = Form("id"),
):
    ext = os.path.splitext(audio.filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Format file tidak didukung: {ext or '(tanpa ekstensi)'}",
        )

    dest = os.path.join(config.UPLOAD_DIR, f"{uuid.uuid4().hex}{ext}")
    try:
        with open(dest, "wb") as f:
            while chunk := await audio.read(1024 * 1024):
                f.write(chunk)
    except OSError as exc:
        raise HTTPException(status_code=500, detail="Gagal menyimpan file upload") from exc

    job = jobs.create_job(dest, language=language)
    return {"job_id": job.id, "status": job.status}


@app.get("/api/jobs/{job_id}", dependencies=[Depends(require_api_key)])
async def get_job(job_id: str):
    job = jobs.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job tidak ditemukan")
    body = {
        "job_id": job.id,
        "status": job.status,
        "progress": job.progress,
        "stage_label": job.stage_label,
        "eta_seconds": job.eta_seconds,
    }
    if job.status == "done":
        body["transcript"] = job.transcript
        body["summary"] = job.summary
        if job.processing_started_at and job.finished_at:
            body["processing_seconds"] = round(
                job.finished_at - job.processing_started_at
            )
        if job.audio_seconds:
            body["audio_seconds"] = round(job.audio_seconds)
    elif job.status == "failed":
        body["error"] = job.error
    return body
