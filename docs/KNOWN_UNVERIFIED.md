# Smoke test results & remaining unverified items

## Phase 1 smoke test — PASSED 2026-05-01

End-to-end run on the upstream gvanno example VCF (8871 variants, GRCh37):

```
Duration    : 1m 18s on Ubuntu 24.04 / Docker 29.4 / Nextflow 26.04
Succeeded   : 8 / 8 processes
Output VCF  : 8871 records, BGZF-compressed, full annotation INFO tags
Output TSV  : 221 columns × 8872 rows (CHROM, POS, ID, REF, ALT, QUAL, FILTER, AC, ...)
```

All gvanno helpers (`gvanno_validate_input.py`, `gvanno_vep.py`, `gvanno_vcfanno.py`, `gvanno_summarise.py`, `gvanno_finalize.py`) live on `$PATH` inside `sigven/gvanno:1.7.0` at `/gvanno/`. VEP at `/opt/vep/src/ensembl-vep/vep`. vcf2tsvpy/bcftools at `/conda/bin/`. bgzip/tabix at `/usr/local/bin/`.

## Things confirmed during the smoke test

- **Bundle layout.** `gvanno.databundle.<assembly>.<version>.tgz` extracts directly to `data/<assembly>/...` (no leading directory). VEP cache extracts to `homo_sapiens/<ens>_<asm>/...`. `RELEASE_NOTES` contains `GVANNO_DB_VERSION = 20231224` exactly.
- **Helper output naming.**
  - `gvanno_validate_input.py` writes `<output>.vcf.gz` + `.tbi` directly when given an output ending in `.vcf` (it adds `.gz` itself and indexes).
  - `gvanno_vep.py` writes `<output>.vcf.gz` + `.tbi` directly.
  - `gvanno_vcfanno.py` writes uncompressed VCF (we bgzip + tabix).
  - `gvanno_summarise.py` with `--compress_output_vcf` writes `<output>.vcf.gz` + `.tbi`.
  - `gvanno_finalize.py` writes **gzipped** content into the path given even though the path doesn't end in `.gz` — detect the gzip magic bytes and rename rather than re-compress.
  - `vcf2tsvpy --compress` appends `.gz` to the path given (so `--out_tsv X.tsv` produces `X.tsv.gz`).
- **FASTA prep.** Ensembl ships the primary assembly as plain gzip; VEP needs it bgzipped + faidx'd. The current `BUNDLE_FETCH` does **not** convert — manual prep was needed for this smoke test.

## Modules.config selectors that don't yet match anything

`BCFTOOLS_CONCAT` and `MULTIQC` are present as placeholders for v0.2 / Phase 2. Nextflow logs a benign `WARN: There's no process matching config selector` for each. Safe to ignore until those processes land.

## Remaining unverified

### Bit-identical output gate
This smoke test confirms the pipeline runs and produces well-formed output. It does **not** yet confirm the per-row content matches upstream gvanno on the same input. Phase 1 acceptance gate (`zdiff` of the `.pass.tsv.gz` against an upstream gvanno run on the example VCF) still pending.

### BUNDLE_FETCH FASTA prep
`modules/local/refdata/bundle_fetch.nf` downloads the FASTA but doesn't decompress + bgzip + faidx. Real reference preparation needs a follow-up step that runs inside the gvanno container:

```bash
gunzip Homo_sapiens.<ASM>.dna.primary_assembly.fa.gz
bgzip Homo_sapiens.<ASM>.dna.primary_assembly.fa
samtools faidx Homo_sapiens.<ASM>.dna.primary_assembly.fa.gz
```

Should be wired into `BUNDLE_FETCH` (or a new `BUNDLE_FINALIZE` step) before v0.1.0 ships.

### GRCh38
Smoke test was GRCh37 only. GRCh38 path differences (different fasta filename, different LOFTEE ancestor URL, GENCODE v44 instead of v19) are wired in `conf/genomes.config` but not exercised.

### `--scatter_by chromosome`
Off in this smoke run. Logic in `annotate_variants.nf` exists but was not exercised end-to-end; the `groupTuple` + concat path needs a real test.

### `BUNDLE_FETCH` download mode
This smoke run used `prestaged` mode with a manually prepared bundle. The download mode logic exists but wasn't exercised.

### Container choices for refdata steps
`BUNDLE_VERIFY` runs in `ubuntu:22.04` and `BUNDLE_FETCH` in `curlimages/curl:8.5.0`. Both pull cleanly but bring in two extra images. Could consolidate into a single tiny image or use the gvanno container.
