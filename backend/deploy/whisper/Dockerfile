# Created by Rodion Kholodov.

FROM ubuntu:22.04 AS build

ARG WHISPER_CPP_VERSION=v1.9.1
ARG WHISPER_CPP_COMMIT=f049fff95a089aa9969deb009cdd4892b3e74916
ARG WHISPER_MODEL_SHA256=60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cmake git wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/whisper.cpp
RUN git clone --depth 1 --branch "${WHISPER_CPP_VERSION}" https://github.com/ggml-org/whisper.cpp.git .
RUN test "$(git rev-parse HEAD)" = "${WHISPER_CPP_COMMIT}" \
    && ./models/download-ggml-model.sh base \
    && echo "${WHISPER_MODEL_SHA256}  models/ggml-base.bin" | sha256sum --check \
    && cmake -B build -DWHISPER_BUILD_TESTS=OFF \
    && cmake --build build --config Release --target whisper-server --parallel

FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg libgomp1 \
    && groupadd --system whisper \
    && useradd --system --gid whisper --uid 10002 --no-create-home whisper \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/whisper.cpp/build/bin/ /opt/whisper/bin/
COPY --from=build /src/whisper.cpp/models/ggml-base.bin /opt/whisper/models/ggml-base.bin

ENV LD_LIBRARY_PATH=/opt/whisper/bin

USER whisper
WORKDIR /tmp
EXPOSE 8080

ENTRYPOINT ["/opt/whisper/bin/whisper-server"]
CMD ["--model", "/opt/whisper/models/ggml-base.bin", "--host", "0.0.0.0", "--port", "8080", "--convert", "--language", "auto", "--threads", "4"]
