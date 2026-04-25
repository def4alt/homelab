FROM nousresearch/hermes-agent:latest

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-eng \
        poppler-utils \
        mupdf-tools \
        ghostscript \
        ocrmypdf \
    && rm -rf /var/lib/apt/lists/*

USER 10000
