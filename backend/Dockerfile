FROM python:3.12-slim

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Library CUDA (cuBLAS + cuDNN) untuk faster-whisper/ctranslate2 di GPU.
# Container dijalankan dengan akses GPU (gpus: all) via nvidia runtime.
RUN pip install --no-cache-dir nvidia-cublas-cu12 nvidia-cudnn-cu12
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/site-packages/nvidia/cublas/lib:/usr/local/lib/python3.12/site-packages/nvidia/cudnn/lib

# Model diarisasi lokal (sherpa-onnx) — diunduh saat build, tanpa token/login.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates bzip2 \
    && mkdir -p /models \
    && curl -fsSL -o /tmp/seg.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 \
    && tar xjf /tmp/seg.tar.bz2 -C /tmp \
    && cp /tmp/sherpa-onnx-pyannote-segmentation-3-0/model.onnx /models/seg.onnx \
    && curl -fsSL -o /models/emb.onnx https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_titanet_small.onnx \
    && rm -rf /tmp/seg.tar.bz2 /tmp/sherpa-onnx-pyannote-segmentation-3-0 \
    && apt-get purge -y bzip2 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY app ./app

ENV UPLOAD_DIR=/data/uploads
VOLUME /data

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
