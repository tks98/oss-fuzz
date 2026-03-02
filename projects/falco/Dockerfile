FROM gcr.io/oss-fuzz-base/base-builder

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    pkg-config

RUN git clone --depth 1 https://github.com/falcosecurity/falco $SRC/falco

COPY build.sh fuzz_*.cc *.options $SRC/
COPY corpora/ $SRC/corpora/
