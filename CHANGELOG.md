# Changelog

## v0.3.0 — Ensembl VEP 115 (2026-08-10)

**Track B.** The container moves from VEP 110 to 115, which is the only way to
advance the three resources that ride on the VEP cache rather than the bundle.

| Resource | v0.2.0 | v0.3.0 |
|---|---|---|
| Ensembl VEP | 110 | **115** |
| GENCODE (GRCh38) | v44 | **v49** |
| gnomAD | r2.1 (2018) | **v4.1** |
| dbSNP | b154 | **b156** |
| container | `sigven/gvanno:1.7.0` | **`ghcr.io/biocentric/gvanno-nf:2026.1`** |
| bundle | `20260801` | **`20260810`** |

GRCh37 stays on GENCODE 19 — Ensembl freezes it there — so its transcript set
is unchanged. That is deliberate and useful; see the gate below.

### Measured effect

On a 1,250-variant ClinVar panel per assembly:

| | GRCh38 | GRCh37 |
|---|---|---|
| `gnomADe_AF` populated | 638 → **820** | 631 → **837** |
| `DBSNPRSID` populated | 949 → **1048** | 922 → **1033** |
| `gnomADg_AF` populated | 0 → **684** | n/a |

About **+30%** more variants receive a population frequency. `gnomADg_AF` is
populated for the first time in any release: `--af_gnomad` is a back-compat
alias for `--af_gnomade` and only ever requested exomes, so the 11 `gnomADg_*`
tags the bundle declared had always been empty. Fixed by passing
`--af_gnomadg` on GRCh38 (Ensembl has no gnomAD genome data for GRCh37).

### Validation

Both assemblies pass, with GRCh37 as the control arm. Because its GENCODE is
frozen, any churn there is attributable to the container rather than the data:

```
Feature 1/1246 (0.08%) · SYMBOL 0/1246 · HGVSp_short 0/1246 · CONSEQUENCE 0/1246
```

The single `Feature` difference was individually explained: VEP 115 picks the
canonical / APPRIS-principal / CCDS transcript where 110 picked an
alternative-5′UTR read-through. Same protein consequence (`p.Gln36Leu`) — a
better pick, not a regression.

Strict checks — `CLINVAR_*`, `NCER_PERCENTILE`, `GWAS_HIT` — show zero
differences on both assemblies. Full results in
[`refdata-builder/spec/TRACKB-GATE-RESULTS.md`](refdata-builder/spec/TRACKB-GATE-RESULTS.md).

### ⚠️ Float formatting changed

Python 3.7 / pandas 1.x → 3.10 / pandas 2.3 changed float repr:
`97.90899999999999` now serialises as `97.909`. Values are identical; strings
are not. **Diffing a v0.3.0 TSV against a v0.2.0 one will show thousands of
spurious line changes.** Compare numerically, not textually.

### The container

Built on `ensemblorg/ensembl-vep:release_115.2` rather than from source — 258 MB
against 1.5 GB, and it already provides the `modules` directory gvanno
hardcodes. LOFTEE works: `LoF.pm` compiles against the VEP 115 Perl API, and
nf-core/sarek runs the same plugin on 115.2 in production.

**The gvanno helpers are not vendored.** `sigven/gvanno` carries no licence, so
redistributing its source is not ours to do. The repo holds only our patches;
the Dockerfile fetches the pinned upstream tarball at build time and applies
them. See [`container/README.md`](container/README.md). Worth asking upstream
for a licence — PCGR, same author, is MIT.

Four patches, pinned to upstream commit `379ee24`:
`VEP_VERSION` 110→115 (it drives both `--cache_version` and the on-disk cache
paths, so this cannot be worked around from the bundle); `--af_gnomadg`;
a guard on an unguarded `['SYMBOL']` lookup that GENCODE 49's ~16k unnamed loci
would hit; and `check_subprocess()`, which swallowed **every** external failure
including `vep` itself and exited 0.

`pandas` is pinned `<3.0` — `variant.py:170-186` raises under pandas 3.
Verified by execution.

### Fixed

- **`--scatter_by chromosome` annotated only one shard.** It discarded ~89% of
  variants and exited 0 — 134 rows instead of 1,250 on a 24-contig panel.
  `prepare_references.nf` emitted `refdata_dir`/`vep_cache` as one-element
  queue channels, and Nextflow zips process inputs positionally and stops at
  the shortest, so `VEP(<24 shards>, <1>, <1>)` ran a single task. Fixed with
  `.first()`. The feature had shipped since v0.1.0dev without ever being run;
  it is invisible unless scatter is actually used.
- **`BUNDLE_PREPARE` published the entire reference tree.** No `withName` rule,
  so it fell through to the catch-all `publishDir` and copied ~26 GB into
  `outdir`. `--refdata_mode download` silently cost double the disk.
- **`.gitignore` excluded every sha256 manifest.** `*.tsv` meant
  `assets/refdata_manifest.*.tsv` was never committed, so a fresh clone had no
  manifest and `BUNDLE_VERIFY` skipped checksum verification entirely. Both
  fixes are also on the `0.2.0` branch.

### Added

- `refdata-builder/verify/check_csq_tags.sh` — runs the real VEP in the real
  container and diffs emitted CSQ fields against the declared tag set, both
  directions. It caught VEP 113's `gnomAD*_OTH_AF` → `*_REMAINING_AF` rename,
  which would otherwise have left two columns permanently empty and three
  silently dropped.
- `refdata-builder/verify/compare_trackb.sh` — the redefined gate. Joins on
  variant + **gene**, since GENCODE 44→49 makes `Feature` an unstable key.
- `container/` — Dockerfile, patch series, build script.

### Mirror

<https://github.com/Biocentric/gvanno-nf/releases/tag/refdata-20260810>

```
gvanno.databundle.grch38.20260810.tgz  4.67 GB
  92761062b3d436e3975ba3d424f098888bb8cfd094a5a293aa2e6636cbb7f955
gvanno.databundle.grch37.20260810.tgz  4.64 GB
  85ebccb77d5f14ce3dba4cc7ff63e076b687bbadc92f0a10b85dbe3b0f5f8b15
```

Verified consumable: direct URLs 404 by design, all six chunks resolve, manifests present.

> **The GHCR package is private.** Until it is made public at
> `github.com/orgs/Biocentric/packages`, every `nextflow run` needs a registry
> login.

## v0.2.0 — 2026 annotation databases (2026-08-01)

**`params.refdata_version` now defaults to `20260801`.** Pass
`--refdata_version 20231224` to reproduce a historical run; that bundle and its
mirror remain available.

The pipeline code is materially unchanged — this release is the reference data.
VEP stays at 110, so GENCODE, gnomAD and dbSNP are untouched; those ride on the
container and move in Track B.

### What changed

| Resource | `20231224` | `20260801` | Source |
|---|---|---|---|
| ClinVar | 2023-12 | **2026-07-28** | NCBI, direct |
| dbNSFP | v4.5 | **v5.3** | PCGR 2.3 donor |
| Cancer Hotspots | v2 (2017) | **v3 (2026)** | PCGR 2.3 donor |
| GWAS Catalog | 2023-11 | **2026** | PCGR 2.3 donor |
| Pfam | v36.0 | **2026** | PCGR 2.3 donor |
| Cancer Gene Census | v97-era | **v101 (2025)** | PCGR 2.2 bundle |
| MIM phenotypes | 3,853 genes | **5,271 genes** | NCBI `mim2gene_medgen` ∪ prior |
| Gene/transcript xref | Ensembl 110 | **GENCODE 49** | PCGR 2.3, remapped |
| ncER | v1.0 (2019) | v1.0, carried forward | no newer release exists |
| VEP · GENCODE · gnomAD · dbSNP | 110 · v44/v19 · r2.1 · b154 | *unchanged* | Track B |

Upstream gvanno froze at v1.7.0 (2023-12-29) and will publish no bundle newer
than `20231224`, so this project now builds its own. `refdata-builder/` holds
the whole chain; `make bundle` runs it for one assembly.

**Every source is account-free.** COSMIC and OMIM both gate downloads behind
registration. Cancer Gene Census is lifted from the PCGR 2.2-era bundle (2.3
dropped those fields) and MIM phenotypes come from NCBI, which needs no account
and covers 5,271 genes against the prior 3,853. The builder runs unattended.

### Why it matters

On a 1,250-variant panel, **68 of 500 pathogenic-tier calls (13.6%) differ**
between the two bundles, and 77 of 96 total reclassifications fall in the
pathogenic tiers. That is the measured cost of running 2023 ClinVar in a
germline clinical annotator.

### Validation

Both assemblies pass their gates with **zero drift** in every VEP-derived
column and `NCER_PERCENTILE`. The 1,250-variant panel produced **zero wrong
ClinVar IDs**. Both bundles pass `check_bundle.py` 18/18. See
[`docs/KNOWN_UNVERIFIED.md`](docs/KNOWN_UNVERIFIED.md) — the gap that matters
most is that `--refdata_mode download` has not been run against the new mirror.

### Fixed

- **`BUNDLE_VERIFY` was a no-op.** `refdata_manifest.20231224.tsv` shipped
  empty, so the checksum step silently skipped on every run since the project
  started. `refdata_manifest.20260801.tsv` carries all 52 entries (26 per
  assembly) and `package-bundle.sh` refuses to build a tarball if the manifest
  comes out empty. `BUNDLE_VERIFY` also now filters the manifest to the
  assembly in use, since one manifest covers both but users stage one.
- **The mirror URL hardcoded a release tag.** Overriding `--refdata_version`
  would have silently fetched the wrong bundle. `refdata_url_base` now carries
  a `{version}` placeholder that `BUNDLE_FETCH` substitutes at runtime.

### Three findings that cost a build cycle each

- **The `DBNSFP` tag is only half self-describing.** `dbnsfp.py` reads the
  predictor *list* from the tag's own `Format:` string at runtime, but maps
  each to an output tag through a hardcoded 17-entry dict (`gerp_rs` →
  `DBNSFP_GERP`, not `DBNSFP_GERP_RS`). Derived names miss and cyvcf2 raises.
  The emittable tag set is fixed by the container, so v5.3's new predictors
  (AlphaMissense, REVEL, CADD, ESM1b, …) reach the combined
  `EFFECT_PREDICTIONS` string but get no column until Track B.
- **PCGR's ClinVar is not safe for a germline pipeline.** F5 p.R534Q — Factor V
  Leiden, expert-panel Pathogenic — is missing from it. ClinVar is built from
  NCBI directly instead. A later GRCh37 build silently shipped PCGR's copy
  anyway, whose `CLINVAR_CLNSIG` uses a `CUI:significance:count` encoding
  gvanno cannot parse; `check_bundle.py` passed it 18/18 because it validates
  tag names, not value grammar. Both scripts now take an explicit per-assembly
  `-s` output directory instead of swapping a symlink, and a missing NCBI
  ClinVar is a hard error rather than a warning-and-fallback.
- **Comparing runs by column hash is wrong.** One extra row shifts everything
  below it, which reported all seven invariant columns as drifting when zero
  rows actually differed. `compare_runs.sh` joins on
  `(CHROM,POS,REF,ALT,Feature)`.

Both known failure modes are silent — a dbNSFP field-count mismatch empties
every prediction while the run still succeeds. `check_bundle.py` asserts them
at build time; the gate carries canaries for both.

### Added

- `refdata-builder/` — `Makefile` driver, `config/sources.yml`, the step
  scripts, and `spec/` holding the extracted format contract, donor
  assessment, baseline and panel results.
- `refdata-builder/verify/` — `check_bundle.py`, `compare_runs.sh`,
  `make_check_panel.py`.
- `scripts/publish-refdata-mirror.sh` gains `SOURCE_DIR` for locally built
  bundles, verifies against the recorded `.sha256` before publishing, and uses
  provenance-aware release notes — a bundle this project assembled must not be
  described as published by Sigve Nakken.

### Mirror

<https://github.com/Biocentric/gvanno-nf/releases/tag/refdata-20260801>

```
gvanno.databundle.grch38.20260801.tgz  4.7 GB
  fcf1907c9645a9e09bcc02fde261a64d8276c00e2657f1b748f87e5bb6b07f1e
gvanno.databundle.grch37.20260801.tgz  4.7 GB
  1a4a99e4c373e2fd2a5a824978d88a2966f863ee34d386ce50dc450e8f5ef037
```

Each is split into ~1.9 GB chunks with a `.parts.txt` manifest and `.sha256`
sidecar; `BUNDLE_FETCH` reassembles transparently.

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
