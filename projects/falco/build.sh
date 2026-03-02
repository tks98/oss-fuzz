#!/bin/bash -eu

# Build Falco's userspace libs from the version pinned in the falco repo, then
# link OSS-Fuzz harnesses against libsinsp/libscap.

LIBS_VERSION="$(grep -Po 'set\(FALCOSECURITY_LIBS_VERSION "\K[0-9]+\.[0-9]+\.[0-9]+' \
  "$SRC/falco/cmake/modules/falcosecurity-libs.cmake" | grep -v '^0\.0\.0$' | head -n1)"

if [ -z "${LIBS_VERSION}" ]; then
  echo "Failed to extract FALCOSECURITY_LIBS_VERSION from falco repo"
  exit 1
fi

git clone --depth 1 --branch "${LIBS_VERSION}" \
  https://github.com/falcosecurity/libs "$SRC/falco-libs"

rm -rf "$WORK/falco-libs-build"
mkdir -p "$WORK/falco-libs-build"
cd "$WORK/falco-libs-build"

cmake -G Ninja "$SRC/falco-libs" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$CFLAGS" \
  -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DUSE_BUNDLED_DEPS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DHAVE_LIBSINSP=ON \
  -DCREATE_TEST_TARGETS=OFF \
  -DBUILD_LIBSCAP_EXAMPLES=OFF \
  -DENABLE_ENGINE_KMOD=OFF \
  -DENABLE_ENGINE_BPF=OFF \
  -DBUILD_LIBSCAP_GVISOR=OFF

ninja -j"$(nproc)" scap

COMMON_INCLUDES=(
  -I"$SRC/falco-libs"
  -I"$SRC/falco-libs/userspace"
  -I"$SRC/falco-libs/userspace/libscap"
  -I"$WORK/falco-libs-build"
  -I"$WORK/falco-libs-build/libscap"
  -I"$WORK/falco-libs-build/uthash-prefix/src/uthash/src"
  -I"$WORK/falco-libs-build/zlib-prefix/src/zlib"
)

STATIC_LIBS=(
  $(find "$WORK/falco-libs-build" -name '*.a' -print)
)

"$CXX" $CXXFLAGS \
  "${COMMON_INCLUDES[@]}" \
  "$SRC/fuzz_scap_event_decode.cc" \
  -o "$OUT/fuzz_scap_event_decode" \
  $LIB_FUZZING_ENGINE \
  -Wl,--start-group "${STATIC_LIBS[@]}" -Wl,--end-group \
  -lpthread -ldl

cp "$SRC/fuzz_scap_event_decode.options" "$OUT/"

corpus_dir="$SRC/corpora/fuzz_scap_event_decode"
if [ ! -d "$corpus_dir" ]; then
  echo "Missing corpus directory: $corpus_dir"
  exit 1
fi

if [ -z "$(find "$corpus_dir" -maxdepth 1 -type f -print -quit)" ]; then
  echo "Corpus directory is empty: $corpus_dir"
  exit 1
fi

# Recreate the archive from scratch so removed corpus files don't linger.
rm -f "$OUT/fuzz_scap_event_decode_seed_corpus.zip"
zip -j "$OUT/fuzz_scap_event_decode_seed_corpus.zip" "$corpus_dir"/*
