#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/tools"
CORPUS_DIR="$ROOT_DIR/corpora/fuzz_scap_event_decode"

# Defaults are chosen to match current corpus inputs.
LIBS_REPO_URL="${LIBS_REPO_URL:-https://github.com/falcosecurity/libs}"
LIBS_VERSION="${LIBS_VERSION:-0.23.1}"
WORK_DIR="${WORK_DIR:-/tmp/falco-ossfuzz-corpus-rebuild}"
MAX_EVENTS="${MAX_EVENTS:-500}"
MAX_LEN="${MAX_LEN:-4096}"

LIBS_SRC_DIR="$WORK_DIR/falco-libs"
LIBS_BUILD_DIR="$WORK_DIR/falco-libs-build"
EXTRACTOR_BIN="$WORK_DIR/extract_scap_events"
EXTRACTED_DIR="$WORK_DIR/extracted"

echo "[1/6] Preparing workspace: $WORK_DIR"
mkdir -p "$WORK_DIR"

if [ -d "$LIBS_SRC_DIR/.git" ]; then
  echo "Reusing existing libs checkout: $LIBS_SRC_DIR"
  git -C "$LIBS_SRC_DIR" fetch --tags --quiet
  git -C "$LIBS_SRC_DIR" checkout --quiet "$LIBS_VERSION"
else
  echo "Cloning falcosecurity/libs @ $LIBS_VERSION"
  git clone --depth 1 --branch "$LIBS_VERSION" "$LIBS_REPO_URL" "$LIBS_SRC_DIR"
fi

echo "[2/6] Building libscap static libs"
cmake -S "$LIBS_SRC_DIR" -B "$LIBS_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_BUNDLED_DEPS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DHAVE_LIBSINSP=OFF \
  -DCREATE_TEST_TARGETS=OFF \
  -DBUILD_LIBSCAP_EXAMPLES=OFF \
  -DENABLE_ENGINE_KMOD=OFF \
  -DENABLE_ENGINE_BPF=OFF \
  -DBUILD_LIBSCAP_GVISOR=OFF

cmake --build "$LIBS_BUILD_DIR" --target scap -j"$(getconf _NPROCESSORS_ONLN || echo 4)"

echo "[3/6] Building extractor helper"
mapfile -t STATIC_LIBS < <(find "$LIBS_BUILD_DIR" -name '*.a' -print | sort)

COMMON_INCLUDES=(
  -I"$LIBS_SRC_DIR"
  -I"$LIBS_SRC_DIR/userspace"
  -I"$LIBS_SRC_DIR/userspace/libscap"
  -I"$LIBS_BUILD_DIR"
  -I"$LIBS_BUILD_DIR/libscap"
  -I"$LIBS_BUILD_DIR/uthash-prefix/src/uthash/src"
  -I"$LIBS_BUILD_DIR/zlib-prefix/src/zlib"
)

if [[ "$(uname -s)" == "Darwin" ]]; then
  # Darwin linker uses -all_load instead of GNU --start-group/--whole-archive.
  c++ -std=c++17 -O2 "${COMMON_INCLUDES[@]}" \
    "$TOOLS_DIR/extract_scap_events.cc" \
    -o "$EXTRACTOR_BIN" \
    -Wl,-all_load "${STATIC_LIBS[@]}" \
    -lpthread -ldl
else
  c++ -std=c++17 -O2 "${COMMON_INCLUDES[@]}" \
    "$TOOLS_DIR/extract_scap_events.cc" \
    -o "$EXTRACTOR_BIN" \
    -Wl,--start-group "${STATIC_LIBS[@]}" -Wl,--end-group \
    -lpthread -ldl
fi

echo "[4/6] Extracting raw events from capture fixtures"
mkdir -p "$EXTRACTED_DIR/curl_google" "$EXTRACTED_DIR/test_ipv6_client"

"$EXTRACTOR_BIN" \
  "$LIBS_SRC_DIR/test/libsinsp_e2e/resources/captures/curl_google.scap" \
  "$EXTRACTED_DIR/curl_google" \
  "$MAX_EVENTS" \
  "$MAX_LEN"

"$EXTRACTOR_BIN" \
  "$LIBS_SRC_DIR/test/libsinsp_e2e/resources/captures/test_ipv6_client.scap" \
  "$EXTRACTED_DIR/test_ipv6_client" \
  "$MAX_EVENTS" \
  "$MAX_LEN"

echo "[5/6] Recreating decode corpus with deterministic file picks"
python3 - "$CORPUS_DIR" "$EXTRACTED_DIR" <<'PY'
from pathlib import Path
import shutil
import sys

corpus_dir = Path(sys.argv[1])
extracted_root = Path(sys.argv[2])

corpus_dir.mkdir(parents=True, exist_ok=True)
for old in sorted(corpus_dir.glob("real_*.bin")):
    old.unlink()

selections = [
    ("curl_google", 159, 64, "real_curl_google_type159_len64.bin"),
    ("curl_google", 161, 106, "real_curl_google_type161_len106.bin"),
    ("curl_google", 1, 34, "real_curl_google_type1_len34.bin"),
    ("curl_google", 293, 2394, "real_curl_google_type293_len2394.bin"),
    ("curl_google", 2, 32, "real_curl_google_type2_len32.bin"),
    ("curl_google", 7, 134, "real_curl_google_type7_len134.bin"),
    ("test_ipv6_client", 165, 74, "real_test_ipv6_client_type165_len74.bin"),
    ("test_ipv6_client", 31, 99, "real_test_ipv6_client_type31_len99.bin"),
]

for source_dir, ev_type, ev_len, out_name in selections:
    matches = sorted((extracted_root / source_dir).glob(f"evt_*_type{ev_type}_len{ev_len}.bin"))
    if not matches:
        raise SystemExit(f"Missing extracted event for type={ev_type} len={ev_len} in {source_dir}")
    shutil.copyfile(matches[0], corpus_dir / out_name)

print(f"recreated {len(selections)} files in {corpus_dir}")
PY

echo "[6/6] Corpus summary"
find "$CORPUS_DIR" -maxdepth 1 -type f -name 'real_*.bin' -print | sort
echo "total files: $(find "$CORPUS_DIR" -maxdepth 1 -type f -name 'real_*.bin' | wc -l | tr -d ' ')"
echo "total bytes: $(find "$CORPUS_DIR" -maxdepth 1 -type f -name 'real_*.bin' -print0 | xargs -0 wc -c | tail -n1 | awk '{print $1}')"
