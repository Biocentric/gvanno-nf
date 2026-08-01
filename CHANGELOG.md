# Changelog

## v0.2.0dev — reference data modernisation, Phase 0 (2026-08-01)

Groundwork for bringing the annotation databases to 2026 versions. **No
reference data has changed yet** — the pipeline still produces `20231224`
annotations. This entry records what was established before the rebuild.

**Upstream gvanno is frozen.** Last release v1.7.0 (2023-12-29), last commit
2024-02-13, last bundle `20231224`. There is no newer upstream bundle to
re-pin to, so this project has to produce the bundle itself. The README's
previous claim that updating is "a one-line `params.refdata_version` change"
no longer holds.

Added `refdata-builder/`:
- `spec/` — the bundle format contract extracted from `20231224`: every
  vcfanno INFO-tag sidecar, VCF headers, tabular column layouts, both INFO tag
  dictionaries, and a full file inventory. This is the build target.
- `spec/DONOR-ASSESSMENT.md` — PCGR 2.3 (`20260620`) evaluated as a donor. It
  covers 6 of the 8 rebuildable resources, two as byte-compatible drop-ins.
- `spec/BASELINE.md` — the run the Phase 2 gate diffs against.
- `steps/capture-spec.sh` — regenerates `spec/` from any bundle.

Findings that change the plan:

- **The `DBNSFP` tag is self-describing.** `dbnsfp.py` does not hardcode a
  predictor list; it parses one at runtime from the tag's own `Format:` string
  (index 6 onward, `_score`/`_pred` stripped) and only requires header and data
  to agree on the field count. Updating dbNSFP is far less constrained than
  assumed. But a mismatch **fails silently** — it returns no predictions while
  the run reports success — so `EFFECT_PREDICTIONS` needs an explicit
  non-empty assertion in the gate.
- **dbNSFP v5.3 drops `LRT`, `FATHMM`, `FATHMM_MKL_coding` and `Aloft`** and
  adds ten predictors (AlphaMissense, REVEL, CADD, ClinPred, ESM1b, MutFormer,
  PHACTboost, PolyPhen2_HVAR, VEST4, FATHMM_xf). `DBNSFP_ALOFTPRED`,
  `DBNSFP_FATHMM` and `DBNSFP_FATHMM_MKL` will disappear from the output. The
  gate's "identical column set" rule is amended: VEP-derived and `NCER_*`
  columns must not drift; `DBNSFP_*` membership is expected to change.
- **Four gene-xref fields have no donor** — `cgc_tier`, `cgc_somatic`,
  `cgc_germline` (Cancer Gene Census) and `mim_phenotype_id` (OMIM). PCGR 2.3
  no longer carries them. Both sources are free for non-commercial use but
  need accounts, so this step cannot run unattended. It is the critical path.
- The bundle ships four resources not previously documented here: Pfam v36.0
  protein domains, a 107 MB ClinVar TSV used for trait resolution, a second
  gene-xref BED (`pc_nopad`), and `hotspot_long.tsv.gz`.

`.gitignore` excluded `*.vcf`/`*.tsv` wholesale, which silently dropped the
captured VCF headers and both INFO tag dictionaries; added a negation for
`refdata-builder/spec/`.

## v0.1.0dev — GRCh38 verified end-to-end (2026-07-31)

Live run on hephaestus (Nextflow 26.04.3 / Docker): reference download 3/3 ✔ (29m50s, 25 GB), annotation 8/8 ✔. All 11 fixture variants resolved to the expected gene + protein change.

Bugs found and fixed by actually running it:
- **`BUNDLE_FETCH` never executed.** `curlimages/curl` declares `ENTRYPOINT ["curl"]`, so Nextflow's `bash .command.run` was handed to curl as arguments — `URL rejected: No host part in the URL`, exit 3, before a single script line ran. All refdata processes now use the gvanno container (`ENTRYPOINT=null`, has bash/curl/wget/tar/gzip), so the **whole pipeline needs exactly one image** (`ubuntu:22.04` and `curlimages/curl` both dropped).
- **`-entry` is rejected by Nextflow 26.x's strict parser.** Replaced with a `--step` param (`annotate` | `prepare_references`) that works on every version. The strict parser also rejects `switch` in a workflow body, so dispatch uses if/else.
- **25 GB of reference data was stranded in the work dir.** `--refdata_dir` was left empty and `nextflow clean` would have deleted the download. `BUNDLE_FETCH` now declares `storeDir params.refdata_dir`.
- **Re-running the download re-downloaded everything.** `PREPARE_REFERENCES` now checks `RELEASE_NOTES` up front and skips fetch+prepare when the bundle is already staged at the requested version (verified: seconds instead of 25 GB). Done in Groovy — the process-level `storeDir` skip does not fire reliably for directory outputs.
- `BUNDLE_FETCH` chunk-reassembly scratch files moved from `/tmp` to the task work dir; under Singularity `/tmp` is host-bind-mounted, so concurrent fetches would have collided.

Docs corrected: `vcf_index` is ignored (not "looked up"), and the output TSV column count varies with the input VCF's INFO tags (~190–220) rather than always being 221.

## v0.1.0dev — unreleased

GRCh38 support (2026-05-01):
- GRCh38 made a first-class, tested assembly (it is already the pipeline default). Verified the GRCh38 external resources against upstream: Ensembl VEP cache 110, Ensembl `primary_assembly` FASTA, LOFTEE GRCh38 ancestor, and the upstream gvanno GRCh38 bundle.
- New committed GRCh38 test fixture `assets/example.grch38.vcf` — 11 canonical variants across 9 chromosomes, every chrom/pos/REF/ALT verified against the Ensembl GRCh38 REST API.
- New `test_grch38` profile + `conf/test_grch38.config` + `assets/test_grch38_samplesheet.csv`.
- Corrected `conf/genomes.config` `fasta_filename` `.fa.bgz` → `.fa.gz` (matches what `gvanno_vep.py` and `BUNDLE_PREPARE` actually use) for both assemblies.
- Reworked `SCATTER_VCF`: enumerate contigs from the validated VCF's own tabix index (`tabix -l`) instead of a reference `.fai`. The old `ref.fa.fai` path never existed after `BUNDLE_PREPARE`, so scatter would have failed on both assemblies. Now assembly-agnostic and needs no reference index. `CONCAT_VCFS` gather now sorts the concatenated output.
- `INPUT_CHECK`/`VALIDATE_VCF`: dropped the input `.tbi` requirement. `VALIDATE_VCF` re-indexes every input, so a pre-existing index was never used; the pipeline now accepts plain uncompressed `.vcf` inputs. `vcf_index` samplesheet column still accepted but ignored.
- Removed dead `asm_short` variable in `FINALIZE_TSV`.

## v0.1.0dev — initial skeleton

Initial Phase 1 skeleton. End-to-end smoke test passed 2026-05-01 on Ubuntu 24.04 / Nextflow 26.04 / Docker 29.4 against the upstream gvanno example VCF (GRCh37, 8871 variants, 1 m 18 s).

Fixes during smoke test:
- Nextflow 26 disallows `def` at config top-level — moved `check_max` to a closure on `params`, removed `trace_timestamp` def.
- Nextflow 26 disallows top-level statements in `main.nf` — wrapped help logic in workflow blocks.
- Switched `BUNDLE_VERIFY` container from non-existent `quay.io/biocontainers/coreutils` to `ubuntu:22.04`.
- Switched `BUNDLE_FETCH` container from non-existent `quay.io/biocontainers/curl` to `curlimages/curl:8.5.0`.
- Made `VALIDATE_VCF`, `VEP`, `VCFANNO`, `SUMMARISE` modules tolerant of helpers that already produce `.vcf.gz` + `.tbi` (skip redundant bgzip/tabix when output already exists).
- `FINALIZE_TSV`: stage inputs under non-colliding names; detect that `gvanno_finalize.py` writes gzipped content to a non-`.gz` path and rename rather than re-compress (was producing double-gzipped output).

Reference-data plumbing:
- New `BUNDLE_PREPARE` module: runs in the gvanno container after `BUNDLE_FETCH`, re-encodes the Ensembl FASTA from plain gzip to BGZF, generates `.fai` + `.gzi` indexes, and places the file at the VEP-expected path inside the cache. Idempotent. Closes the gap that forced manual FASTA prep during the smoke test.
- `BUNDLE_FETCH` mirrors: now supports a chunked-manifest fallback. For each base URL in `params.refdata_url_base`, it tries the direct file first, then `<file>.parts.txt` + chunk reassembly. Lets a GitHub Releases mirror serve assets that exceed GH's 2 GB per-asset cap.
- `scripts/publish-refdata-mirror.sh`: one-shot maintainer script that mirrors the upstream gvanno bundle onto this repo's GitHub Releases page (downloads from upstream, splits into 1.9 GB chunks, writes a manifest, uploads via `gh`). Idempotent.

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
