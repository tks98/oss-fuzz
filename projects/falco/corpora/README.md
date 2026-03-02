# Falco OSS-Fuzz corpora

This directory contains seed inputs for the `fuzz_scap_event_decode` libFuzzer
target.

## Seed source

The files prefixed with `real_` are raw `scap_evt` blobs extracted from
Falco-libs savefile test captures:

- `test/libsinsp_e2e/resources/captures/curl_google.scap`
- `test/libsinsp_e2e/resources/captures/test_ipv6_client.scap`

Extraction method:

1. Open savefiles with `libscap` (`scap_savefile_engine`).
2. Iterate events with `scap_next`.
3. Write each event as `ev->len` bytes from the returned `scap_evt*`.
4. Curate a small, deterministic subset by event type and length.

This first-pass corpus intentionally keeps only a small real-seed baseline and
is packaged into `*_seed_corpus.zip` artifacts by `projects/falco/build.sh`.

## Why these captures

`curl_google.scap` and `test_ipv6_client.scap` were chosen because they are
already maintained as upstream Falco-libs test fixtures and provide a practical
mix of real event shapes (including syscall/network-related records) without
adding external data dependencies.

The goal here is not to model a specific workload. The goal is to seed the
fuzzer with realistic `scap_evt` byte layouts that help reach parser logic
quickly and reproducibly.

## Why keep a checked-in corpus

For an initial OSS-Fuzz integration, checked-in seed files provide:

1. Deterministic startup coverage across local runs and CI.
2. Faster path discovery than starting from an empty corpus.
3. Reviewer-visible provenance for each seed input.

The corpus is intentionally small to keep the first MR easy to review and cheap
to run. It can be expanded in follow-up changes.

## Recreate the corpus

You can regenerate the `real_*.bin` files deterministically with:

```bash
./projects/falco/tools/recreate_real_corpus.sh
```

Optional environment overrides:

1. `LIBS_VERSION` (default: `0.23.1`)
2. `WORK_DIR` (default: `/tmp/falco-ossfuzz-corpus-rebuild`)
3. `MAX_EVENTS` (default: `500`)
4. `MAX_LEN` (default: `4096`)
