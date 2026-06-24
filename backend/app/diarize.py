"""Diarisasi pembicara lokal (sherpa-onnx) — tanpa token/login.

Memberi label "[Pembicara N]" pada transkrip dengan menggabungkan hasil
diarisasi (siapa bicara kapan) dengan segmen Whisper (apa yang dikatakan).
"""
import logging
import threading

from . import config

logger = logging.getLogger(__name__)

_sd = None
_lock = threading.Lock()


def _get():
    """Lazy-load pipeline diarisasi sherpa-onnx (sekali, thread-safe)."""
    global _sd
    if _sd is None:
        with _lock:
            if _sd is None:
                import sherpa_onnx

                cfg = sherpa_onnx.OfflineSpeakerDiarizationConfig(
                    segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
                        pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                            model=config.DIARIZE_SEG_MODEL,
                        ),
                    ),
                    embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(
                        model=config.DIARIZE_EMB_MODEL,
                    ),
                    clustering=sherpa_onnx.FastClusteringConfig(
                        num_clusters=config.DIARIZE_NUM_SPEAKERS
                        if config.DIARIZE_NUM_SPEAKERS > 0
                        else -1,
                        threshold=config.DIARIZE_THRESHOLD,
                    ),
                    min_duration_on=config.DIARIZE_MIN_ON,
                    min_duration_off=config.DIARIZE_MIN_OFF,
                )
                if not cfg.validate():
                    raise RuntimeError("Konfigurasi diarisasi tidak valid")
                _sd = sherpa_onnx.OfflineSpeakerDiarization(cfg)
                logger.info("Pipeline diarisasi siap.")
    return _sd


def _speaker_turns(audio_path: str) -> list[tuple[float, float, int]]:
    """Kembalikan daftar (start, end, speaker_id) hasil diarisasi."""
    from faster_whisper.audio import decode_audio

    sd = _get()
    audio = decode_audio(audio_path, sampling_rate=sd.sample_rate)
    result = sd.process(audio).sort_by_start_time()
    return [(s.start, s.end, s.speaker) for s in result]


def _assign_speaker(seg: dict, turns: list[tuple[float, float, int]]) -> int:
    """Pilih pembicara dengan tumpang-tindih waktu terbesar untuk satu segmen."""
    best_spk, best_overlap = -1, 0.0
    for start, end, spk in turns:
        overlap = max(0.0, min(seg["end"], end) - max(seg["start"], start))
        if overlap > best_overlap:
            best_overlap, best_spk = overlap, spk
    return best_spk


def diarized_transcript(audio_path: str, segments: list[dict]) -> str:
    """Bangun transkrip berlabel "[Pembicara N]" dari segmen Whisper.

    Mengelompokkan segmen berurutan dari pembicara yang sama menjadi satu blok.
    Jika diarisasi gagal/hanya 1 pembicara, kembalikan transkrip polos.
    """
    turns = _speaker_turns(audio_path)
    if not turns:
        return "\n".join(s["text"] for s in segments)

    n_speakers = len({spk for _, _, spk in turns})
    logger.info("Diarisasi: %d giliran bicara, %d pembicara", len(turns), n_speakers)

    blocks: list[tuple[int, list[str]]] = []
    for seg in segments:
        spk = _assign_speaker(seg, turns)
        if blocks and blocks[-1][0] == spk:
            blocks[-1][1].append(seg["text"])
        else:
            blocks.append((spk, [seg["text"]]))

    lines = []
    for spk, texts in blocks:
        label = f"Pembicara {spk + 1}" if spk >= 0 else "Pembicara ?"
        lines.append(f"[{label}] {' '.join(texts)}")
    return "\n".join(lines)
