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

### BUNDLE_FETCH FASTA prep — IMPLEMENTED, not yet integration-tested
Implemented as `modules/local/refdata/bundle_prepare.nf` (`BUNDLE_PREPARE`), wired into `PREPARE_REFERENCES` after `BUNDLE_FETCH`. Runs inside the gvanno container; does `gunzip` → `bgzip` → `samtools faidx` on the Ensembl FASTA and places it at `data/<assembly>/.vep/homo_sapiens/<ens>_<asm>/Homo_sapiens.<asm>.dna.primary_assembly.fa.gz`. Idempotent.

Not yet exercised end-to-end on a fresh `--refdata_mode download` run — the smoke test used a pre-staged bundle. Needs an integration run before v0.1.0.

### GitHub Releases mirror — IMPLEMENTED, not yet populated
`BUNDLE_FETCH` now supports both direct URLs and a chunked-manifest fallback (`<file>.parts.txt`) for any mirror in `params.refdata_url_base`. The chunking strategy targets GitHub's 2 GB per-asset cap.

To populate the mirror, a repo maintainer runs `scripts/publish-refdata-mirror.sh` once per refdata version. The script downloads the bundle from upstream, splits it into 1.9 GB chunks, writes a `.parts.txt` manifest, and uploads everything to the `refdata-<version>` GitHub Release via `gh`. Idempotent.

Until the script runs, the GH mirror URLs in `params.refdata_url_base` return 404 and the pipeline transparently falls back to the upstream Oslo mirror — same behaviour as before.

### GRCh38 — now first-class, statically verified, live run pending
GRCh38 is fully wired and is the pipeline default (`params.genome = 'GRCh38'`). The code is entirely parameterised by `params.genomes[params.genome]` — no module hardcodes an assembly — so GRCh38 traverses exactly the same paths GRCh37 did in the smoke test.

Verified for GRCh38 (2026-05-01):
- **Ensembl VEP cache** `homo_sapiens_vep_110_GRCh38.tar.gz` (20 GB) present at `ftp.ensembl.org/pub/release-110/variation/indexed_vep_cache/`.
- **Ensembl FASTA** `Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz` (841 MB) present (note: GRCh38 uses the main FASTA path, not the `grch37/` subpath — reflected in `conf/genomes.config`).
- **LOFTEE GRCh38 ancestor** `human_ancestor.fa.gz{,.fai,.gzi}` present at the Broad mirror.
- **gvanno GRCh38 bundle** — upstream `download_gvanno_refdata.py` builds `gvanno.databundle.grch38.20231224.tgz` from the same base as grch37, and gvanno's README uses `--genome_assembly grch38` as its *primary* example, so grch38 is upstream's default bundle. (The Oslo directory index is 403-forbidden, so this is confirmed by upstream's URL construction rather than a directory listing.)
- **Test fixture** `assets/example.grch38.vcf` — 11 canonical variants (BRAF V600E, JAK2 V617F, KRAS G12D, EGFR L858R, TP53 R175H, IDH1 R132H, PIK3CA E545K, NRAS Q61K, HFE C282Y, F5 Leiden, MTHFR C677T) across 9 chromosomes. Every chrom/pos/REF/ALT was verified against the Ensembl GRCh38 REST API (`rest.ensembl.org/variation/human/<rsid>`); the REF allele matches the GRCh38 reference base in each case, which is the property VEP enforces.

Not yet done: an actual GRCh38 end-to-end run (`-profile docker,test_grch38`) — the box used for the GRCh37 smoke test was unreachable when GRCh38 was implemented. Fixed genome-invariant fields (`fasta_filename` corrected `.fa.bgz`→`.fa.gz`) but the live GRCh38 pass is still pending.

### `--scatter_by chromosome` — reworked, not yet exercised
Rewritten to enumerate contigs from the validated VCF's own tabix index (`tabix -l`) instead of a reference `.fai`. The previous implementation pointed at `ref.fa.fai`, a path that never exists after `BUNDLE_PREPARE` (which stores the FASTA + `.fai` under `.vep/homo_sapiens/<ens>_<asm>/`), so scatter would have failed on **both** assemblies. The new approach needs no reference index and is assembly-agnostic. The `groupTuple` → `bcftools concat -a | bcftools sort` gather path still needs a real end-to-end test.

### Optional input index
`INPUT_CHECK` no longer requires (or carries) a `.tbi` for input VCFs — `VALIDATE_VCF` re-normalises and re-indexes everything, so a pre-existing index was never used. This lets the pipeline accept plain uncompressed `.vcf` inputs (as the GRCh38 fixture is). The `vcf_index` samplesheet column is still accepted but ignored.

### `BUNDLE_FETCH` download mode
This smoke run used `prestaged` mode with a manually prepared bundle. The download mode logic exists but wasn't exercised.

### Container choices for refdata steps
`BUNDLE_VERIFY` runs in `ubuntu:22.04` and `BUNDLE_FETCH` in `curlimages/curl:8.5.0`. Both pull cleanly but bring in two extra images. Could consolidate into a single tiny image or use the gvanno container.
