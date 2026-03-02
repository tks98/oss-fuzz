# Falco OSS-Fuzz corpora

This directory contains seed inputs for `fuzz_scap_event_decode`.

## What this target is fuzzing

`libscap` is Falco's low-level event parser.

1. Raw event bytes come from kernel capture drivers or `.scap` files.
2. `libscap` decodes those bytes.
3. Upper layers (`libsinsp`, rule engine) consume decoded events.

This target focuses on:

1. `scap_event_getinfo` (event-type metadata lookup)
2. `scap_event_decode_params` (parameter boundary decode)
3. Basic payload-byte access for decoded parameters

## What "parameter" means here

A parameter is one event argument/field in a `scap_evt`.

Event layout:

1. Event header (`type`, `nparams`, etc.)
2. Parameter length table
3. Parameter payload bytes

`type` chooses the schema (which parameters exist and how they are read).

## Seed source

`real_*.bin` files are raw `scap_evt` blobs extracted from:

1. `test/libsinsp_e2e/resources/captures/curl_google.scap`
2. `test/libsinsp_e2e/resources/captures/test_ipv6_client.scap`

Extraction steps:

1. Open savefiles with `libscap` (`scap_savefile_engine`)
2. Iterate events with `scap_next`
3. Write each event as `ev->len` bytes
4. Keep a small deterministic subset by event type + length

## Example `scap_evt` bytes

Example from checked-in seed `real_curl_google_type1_len34.bin`:

```text
49 69 57 42 7e bc 4b 15   # ts      = 1534527348514711881
59 44 00 00 00 00 00 00   # tid     = 17497
22 00 00 00               # len     = 34 bytes total
01 00                     # type    = 1
02 00 00 00               # nparams = 2
02 00 02 00               # param lengths: [2, 2]
4b 00                     # param[0] bytes
0a 00                     # param[1] bytes
```

Quick check:

```bash
python3 - <<'PY' projects/falco/corpora/fuzz_scap_event_decode/real_curl_google_type1_len34.bin
import struct
import sys
from pathlib import Path

b = Path(sys.argv[1]).read_bytes()
ts, tid, elen, etype, nparams = struct.unpack_from("<QQIHI", b, 0)
l1, l2 = struct.unpack_from("<HH", b, 26)
print(f"size={len(b)} len={elen} type={etype} nparams={nparams}")
print(f"ts={ts} tid={tid} param_lens=[{l1},{l2}]")
PY
```

Expected output:

```text
size=34 len=34 type=1 nparams=2
ts=1534527348514711881 tid=17497 param_lens=[2,2]
```

## Why checked-in seeds

1. Deterministic startup coverage
2. Faster signal than empty corpus
3. Reviewable provenance for each seed

## Recreate the corpus

Canonical generation tooling currently lives in:

1. [tks98/libs](https://github.com/tks98/libs/tree/master/test/libscap/fuzz/tools)
2. Later switch to [falcosecurity/libs](https://github.com/falcosecurity/libs/tree/master/test/libscap/fuzz/tools) once merged

This does not change `projects/falco/build.sh`: OSS-Fuzz still builds against
the Falco-pinned upstream `falcosecurity/libs` tag.

Regenerate seeds:

```bash
git clone https://github.com/tks98/libs /tmp/tks98-libs
cd /tmp/tks98-libs
./test/libscap/fuzz/tools/recreate_seed_corpus.sh
```

Copy into this project:

```bash
cp /tmp/tks98-libs/test/libscap/fuzz/corpus/fuzz_scap_event_decode/real_*.bin \
  projects/falco/corpora/fuzz_scap_event_decode/
```
