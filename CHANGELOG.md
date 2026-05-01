# Changelog

## v0.1.0dev — unreleased

Initial Phase 1 skeleton. End-to-end smoke test passed 2026-05-01 on Ubuntu 24.04 / Nextflow 26.04 / Docker 29.4 against the upstream gvanno example VCF (GRCh37, 8871 variants, 1 m 18 s).

Fixes during smoke test:
- Nextflow 26 disallows `def` at config top-level — moved `check_max` to a closure on `params`, removed `trace_timestamp` def.
- Nextflow 26 disallows top-level statements in `main.nf` — wrapped help logic in workflow blocks.
- Switched `BUNDLE_VERIFY` container from non-existent `quay.io/biocontainers/coreutils` to `ubuntu:22.04`.
- Switched `BUNDLE_FETCH` container from non-existent `quay.io/biocontainers/curl` to `curlimages/curl:8.5.0`.
- Made `VALIDATE_VCF`, `VEP`, `VCFANNO`, `SUMMARISE` modules tolerant of helpers that already produce `.vcf.gz` + `.tbi` (skip redundant bgzip/tabix when output already exists).
- `FINALIZE_TSV`: stage inputs under non-colliding names; detect that `gvanno_finalize.py` writes gzipped content to a non-`.gz` path and rename rather than re-compress (was producing double-gzipped output).

- DSL2 modules wrapping every gvanno helper (`gvanno_validate_input.py`, `gvanno_vep.py`, `gvanno_vcfanno.py`, `gvanno_summarise.py`, `vcf2tsvpy`, `gvanno_finalize.py`) inside `sigven/gvanno:1.7.0`.
- `PREPARE_REFERENCES` subworkflow with `prestaged` and `download` modes; ordered mirror list.
- Samplesheet input via native `splitCsv` (no external plugin required).
- Optional chromosome-level scatter/gather.
- Profiles: `docker`, `singularity`, `apptainer`, `conda`, `test`, `test_full`.
- Pinned to upstream gvanno 1.7.0 reference bundle (`20231224`).

Not yet:
- Validation against upstream output (the bit-identical gate).
- nf-test coverage.
- MultiQC integration.
- Reference checksum manifest.
- GitHub Actions CI.
