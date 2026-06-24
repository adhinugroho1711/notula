"""Ringkasan meeting terstruktur via Ollama.

- Mode `format: "json"` + struktur eksplisit di prompt + parsing defensif.
- Notulen kaya: ringkasan, peserta, agenda, poin penting, keputusan, action items (+tenggat).
- Ringkasan bertingkat untuk rapat panjang: transkrip dipotong per bagian,
  diringkas, lalu digabung jadi notulen final agar detail tidak hilang.
"""
import json
import logging
import os

import httpx

from . import config

logger = logging.getLogger(__name__)

# Di atas ambang ini, transkrip diringkas bertingkat (per bagian lalu digabung).
# Dinaikkan setelah num_ctx 8192: rapat pendek-menengah cukup sekali jalan
# (lebih cepat & koheren); hanya rapat panjang yang dipotong.
HIERARCHICAL_THRESHOLD = int(os.getenv("HIERARCHICAL_THRESHOLD", "14000"))  # ~45 mnt
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "9000"))  # karakter per bagian

SYSTEM_PROMPT = """\
Kamu adalah asisten notulen profesional. Dari transkrip rapat/diskusi berbahasa Indonesia, \
buatlah notulen yang terstruktur, MENDALAM, dan rapi.

Keluarkan HANYA satu objek JSON valid dengan struktur PERSIS seperti ini \
(jangan menambah, menghapus, atau mengganti nama field; jangan membungkus dengan markdown):
{
  "judul": "<judul deskriptif yang menangkap inti diskusi, 1 kalimat ringkas>",
  "ikhtisar": "<satu paragraf ikhtisar 4-8 kalimat: latar pertemuan, hal-hal utama yang dibahas, dan kesimpulan/arahnya>",
  "tugas_penting": ["<tindak lanjut/aksi konkret dalam kalimat lengkap; sebutkan penanggung jawab & tenggat bila ada>"],
  "garis_besar": [
    {"topik": "<judul topik pembahasan>", "poin": ["<poin detail apa yang dibahas: konteks, angka, alasan, kesepakatan>", "<poin berikutnya>"]}
  ],
  "wawasan_cerdas": [
    {"ikon": "<satu emoji relevan, mis. 💡 atau 📊 atau 🔍 atau ⚖️ atau 🚀>", "judul": "<tema wawasan>", "poin": ["<butir analisis/wawasan bermakna>", "<butir berikutnya>"]}
  ]
}

Aturan:
- Bahasa Indonesia baku, jelas, dan profesional.
- "judul": ringkas tapi deskriptif (boleh menyebut tema/topik utama secara spesifik).
- "ikhtisar": SATU paragraf padat berisi gambaran menyeluruh pertemuan.
- "tugas_penting": hanya aksi/tindak lanjut yang benar-benar disebut; kosongkan ([]) bila tidak ada.
- "garis_besar": 3-6 topik. Setiap topik berisi 3-6 poin detail tentang apa yang dibahas \
(siapa bilang apa, angka, alasan, kendala, kesepakatan). INI INTI NOTULEN — gali sedalam mungkin, \
JANGAN menyingkat berlebihan.
- "wawasan_cerdas": 3-5 wawasan/analisis bermakna yang ditarik dari diskusi (bukan sekadar \
mengulang poin) — mis. perbandingan teori vs praktik, implikasi, atau hal penting yang patut \
disorot. Tiap wawasan diberi 1 emoji relevan + judul tema + 2-3 butir.
- Jangan mengarang informasi yang tidak ada di transkrip. Patuhi isi transkrip apa adanya, \
namun uraikan selengkap mungkin.
"""

CHUNK_NOTES_SYSTEM = """\
Kamu mencatat poin-poin dari SATU bagian transkrip rapat berbahasa Indonesia.
Tulis catatan ringkas berupa daftar (pakai tanda '-') yang mencakup: topik yang dibahas, \
poin penting, keputusan, tindak lanjut (beserta penanggung jawab & tenggat bila disebut), \
dan nama peserta yang muncul. Bahasa Indonesia, jangan mengarang, jangan merangkum berlebihan. \
Kembalikan hanya catatannya.
"""


def _extract_json(content: str) -> dict:
    """Parse JSON dari respons model, toleran markdown fence / teks pembungkus."""
    text = content.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1] if text.count("```") >= 2 else text.strip("`")
        if text.lstrip().lower().startswith("json"):
            text = text.lstrip()[4:]
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            return json.loads(text[start : end + 1])
        raise


def _normalize(data: dict) -> dict:
    """Pastikan semua field ada dengan tipe yang benar (toleran output model).

    Skema: judul, ikhtisar, tugas_penting[], garis_besar[{topik, poin[]}],
    wawasan_cerdas[{ikon, judul, poin[]}].
    """
    def as_str_list(value):
        out = []
        if isinstance(value, list):
            for v in value:
                if isinstance(v, dict):
                    # toleran: action_item lama {tugas,penanggung_jawab,tenggat}
                    tugas = str(v.get("tugas") or v.get("teks") or "").strip()
                    meta = ", ".join(x for x in [str(v.get("penanggung_jawab", "")).strip(),
                                                 str(v.get("tenggat", "")).strip()] if x)
                    s = f"{tugas} ({meta})" if tugas and meta else tugas
                    if s:
                        out.append(s)
                elif str(v).strip():
                    out.append(str(v).strip())
        elif isinstance(value, str) and value.strip():
            out.append(value.strip())
        return out

    def topic_blocks(value, title_keys):
        blocks = []
        if isinstance(value, list):
            for it in value:
                if isinstance(it, dict):
                    topik = ""
                    for k in title_keys:
                        if str(it.get(k, "")).strip():
                            topik = str(it[k]).strip()
                            break
                    poin = as_str_list(it.get("poin") or it.get("points") or it.get("butir"))
                    if topik or poin:
                        blocks.append((topik, poin))
                elif isinstance(it, str) and it.strip():
                    blocks.append(("", [it.strip()]))
        return blocks

    garis_besar = [{"topik": t, "poin": p}
                   for t, p in topic_blocks(data.get("garis_besar"), ("topik", "judul"))]

    wawasan = []
    for it in (data.get("wawasan_cerdas") or []):
        if isinstance(it, dict):
            ikon = (str(it.get("ikon") or it.get("icon") or "💡").strip() or "💡")[:4]
            judul = str(it.get("judul") or it.get("topik") or "").strip()
            poin = as_str_list(it.get("poin") or it.get("points"))
            if judul or poin:
                wawasan.append({"ikon": ikon, "judul": judul, "poin": poin})
        elif isinstance(it, str) and it.strip():
            wawasan.append({"ikon": "💡", "judul": "", "poin": [it.strip()]})

    return {
        "judul": str(data.get("judul", "")).strip(),
        "ikhtisar": str(data.get("ikhtisar") or data.get("ringkasan") or "").strip(),
        "tugas_penting": as_str_list(data.get("tugas_penting") or data.get("action_items")),
        "garis_besar": garis_besar,
        "wawasan_cerdas": wawasan,
    }


def _chunk_text(text: str, max_chars: int) -> list[str]:
    """Potong teks per bagian di batas kalimat/baris, maksimal max_chars."""
    chunks, buf = [], ""
    # pecah per baris dulu (transkrip kita berbasis baris), lalu kalimat
    for line in text.replace(". ", ".\n").splitlines():
        if len(buf) + len(line) + 1 > max_chars and buf:
            chunks.append(buf.strip())
            buf = ""
        buf += line + "\n"
    if buf.strip():
        chunks.append(buf.strip())
    return chunks or [text]


async def _chat(system: str, user: str, *, as_json: bool) -> str:
    payload = {
        "model": config.OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "stream": False,
        "think": False,
        "options": {
            "temperature": 0.2,
            # Paksa semua layer ke GPU: Ollama 0.21.0 under-estimate VRAM untuk
            # gemma4 dan menaruh sebagian di CPU (lambat) padahal GPU cukup.
            "num_gpu": config.OLLAMA_NUM_GPU,
            # Batasi context agar KV cache kecil → muat berdampingan dgn Whisper
            # di GPU 12 GB. Chunk ringkasan ~6000 char (~2000 token) jauh di bawah ini.
            "num_ctx": config.OLLAMA_NUM_CTX,
        },
    }
    if as_json:
        payload["format"] = "json"
    async with httpx.AsyncClient(timeout=httpx.Timeout(600.0, connect=10.0)) as client:
        resp = await client.post(f"{config.OLLAMA_URL}/api/chat", json=payload)
        resp.raise_for_status()
        return resp.json()["message"]["content"]


CORRECTION_SYSTEM = """\
Kamu adalah editor transkrip rapat berbahasa Indonesia. Teks berikut adalah hasil \
pengenalan suara otomatis yang mungkin mengandung salah eja, salah istilah, atau \
tanda baca yang kurang tepat.

Tugasmu HANYA merapikan:
- Perbaiki kata/istilah yang jelas salah dengar (mis. istilah perbankan: "dana pihak \
ketiga", "QRIS", "kredit", "nasabah"; nama orang; angka dan persentase).
- Perbaiki tanda baca dan kapitalisasi.

Larangan keras:
- JANGAN mengubah makna, JANGAN merangkum, JANGAN menambah atau menghapus kalimat.
- Pertahankan urutan dan isi pembicaraan apa adanya.
- Jika sebuah baris SUDAH diawali penanda pembicara seperti "[Pembicara 1]", pertahankan \
apa adanya. Namun JANGAN PERNAH menambahkan penanda pembicara baru bila teks aslinya tidak \
memilikinya — jangan mengarang label.
- Kembalikan HANYA teks transkrip yang sudah dirapikan, tanpa komentar atau markdown.
"""


async def correct_transcript(transcript: str) -> str:
    """Rapikan typo/istilah hasil STT secara konservatif (tanpa mengubah makna)."""
    try:
        content = (await _chat(CORRECTION_SYSTEM, transcript, as_json=False)).strip()
        if content.startswith("```"):
            content = content.strip("`")
            if content.lower().startswith("text"):
                content = content[4:].strip()
        if len(content) < len(transcript) * 0.5:
            logger.warning("Koreksi transkrip dibatalkan (hasil terlalu pendek)")
            return transcript
        logger.info("Transkrip dirapikan (%d -> %d karakter)", len(transcript), len(content))
        return content
    except (httpx.HTTPError, KeyError, ValueError) as exc:
        logger.warning("Koreksi transkrip gagal, pakai transkrip asli: %s", exc)
        return transcript


async def _structured_summary(source: str) -> dict:
    content = await _chat(SYSTEM_PROMPT, f"Buat notulen dari teks berikut:\n\n{source}",
                          as_json=True)
    if not content or not content.strip():
        raise ValueError("Model mengembalikan respons kosong")
    return _normalize(_extract_json(content))


async def summarize_transcript(transcript: str, progress_cb=None) -> dict:
    """Kembalikan notulen terstruktur; bertingkat untuk transkrip panjang.

    `progress_cb(done, total)` dilaporkan per bagian (mode bertingkat) supaya
    pemanggil bisa menampilkan kemajuan tahap ringkasan.
    """
    if len(transcript) > HIERARCHICAL_THRESHOLD:
        chunks = _chunk_text(transcript, CHUNK_SIZE)
        logger.info("Ringkasan bertingkat: %d bagian", len(chunks))
        # +1 langkah untuk penggabungan akhir menjadi notulen terstruktur.
        total_steps = len(chunks) + 1
        notes = []
        for i, ch in enumerate(chunks, 1):
            try:
                note = await _chat(CHUNK_NOTES_SYSTEM,
                                   f"Bagian {i}/{len(chunks)}:\n\n{ch}", as_json=False)
                notes.append(note.strip())
            except (httpx.HTTPError, KeyError, ValueError) as exc:
                logger.warning("Gagal meringkas bagian %d: %s", i, exc)
            if progress_cb is not None:
                progress_cb(i, total_steps)
        combined = "\n".join(notes) if notes else transcript
        summary = await _structured_summary(combined)
        if progress_cb is not None:
            progress_cb(total_steps, total_steps)
    else:
        if progress_cb is not None:
            progress_cb(0, 1)
        summary = await _structured_summary(transcript)
        if progress_cb is not None:
            progress_cb(1, 1)

    logger.info(
        "Ringkasan selesai (%d garis besar, %d wawasan, %d tugas)",
        len(summary["garis_besar"]), len(summary["wawasan_cerdas"]),
        len(summary["tugas_penting"]))
    return summary


async def check_ollama() -> bool:
    """Cek apakah Ollama bisa dijangkau (untuk /api/health)."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{config.OLLAMA_URL}/api/tags")
            return resp.status_code == 200
    except httpx.HTTPError:
        return False
