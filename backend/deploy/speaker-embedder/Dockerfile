# Created by Rodion Kholodov.

FROM python:3.12-slim-bookworm

ARG SHERPA_ONNX_VERSION=1.13.4
ARG NUMPY_VERSION=2.2.6
ARG SPEAKER_MODEL_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx
ARG SPEAKER_MODEL_SHA256=98daf9bcf1c8abf3db374fec4c27a5eda7c58705bb3f180d057b085a72a88bb5

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libgomp1 \
    && python -m pip install --no-cache-dir \
        "numpy==${NUMPY_VERSION}" \
        "sherpa-onnx==${SHERPA_ONNX_VERSION}" \
        "sherpa-onnx-bin==${SHERPA_ONNX_VERSION}" \
    && groupadd --system speaker \
    && useradd --system --gid speaker --uid 10003 --no-create-home speaker \
    && mkdir -p /opt/speaker-embedder/models \
    && curl --fail --location --silent --show-error \
        "${SPEAKER_MODEL_URL}" \
        --output /opt/speaker-embedder/models/campplus-en-voxceleb.onnx \
    && echo "${SPEAKER_MODEL_SHA256}  /opt/speaker-embedder/models/campplus-en-voxceleb.onnx" | sha256sum --check \
    && chown -R speaker:speaker /opt/speaker-embedder \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=speaker:speaker services/speaker_embedder/server.py /opt/speaker-embedder/server.py

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8090 \
    SPEAKER_EMBEDDING_MODEL=/opt/speaker-embedder/models/campplus-en-voxceleb.onnx

USER speaker
WORKDIR /opt/speaker-embedder
EXPOSE 8090

ENTRYPOINT ["python", "/opt/speaker-embedder/server.py"]
