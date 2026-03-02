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
