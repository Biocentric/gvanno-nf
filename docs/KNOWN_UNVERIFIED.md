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

## GRCh38 — VERIFIED END-TO-END 2026-07-31

Run on hephaestus (Nextflow 26.04.3 / Docker), GRCh38 bundle downloaded fresh from the Oslo mirror:

```
--step prepare_references --refdata_mode download   : 3/3 processes ✔ (29m 50s, 25 GB)
--input <11-variant fixture> --refdata_mode prestaged: 8/8 processes ✔
```

Every fixture variant annotated to the expected gene and protein change, which confirms the GRCh38 coordinates and reference alleles are correct end-to-end:

| Variant | Result | | Variant | Result |
|---|---|---|---|---|
| 1:11796321 G>A | MTHFR p.A222V | | 7:55191822 T>G | EGFR p.L858R |
| 1:114713909 G>T | NRAS p.Q61K | | 7:140753336 A>T | BRAF p.V600E |
| 1:169549811 C>T | F5 p.R534Q | | 9:5073770 G>T | JAK2 p.V617F |
| 2:208248388 C>T | IDH1 p.R132H | | 12:25245350 C>T | KRAS p.G12D |
| 3:179218303 G>A | PIK3CA p.E545K | | 17:7675088 C>T | TP53 p.R175H |
| 6:26092913 G>A | HFE p.C282Y | | | |

(F5 reports `p.R534Q`; the familiar "R506Q" is the same variant numbered on the mature protein rather than the HGVS precursor.)

Output TSV column count varies with the input VCF's own INFO tags (vcf2tsvpy passes them through): 221 columns for the GRCh37 example VCF, 189 for this fixture whose INFO is empty. Not assembly-dependent.

### Original GRCh38 wiring notes
GRCh38 is fully wired and is the pipeline default (`params.genome = 'GRCh38'`). The code is entirely parameterised by `params.genomes[params.genome]` — no module hardcodes an assembly — so GRCh38 traverses exactly the same paths GRCh37 did in the smoke test.

Verified for GRCh38 (2026-05-01):
- **Ensembl VEP cache** `homo_sapiens_vep_110_GRCh38.tar.gz` (20 GB) present at `ftp.ensembl.org/pub/release-110/variation/indexed_vep_cache/`.
- **Ensembl FASTA** `Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz` (841 MB) present (note: GRCh38 uses the main FASTA path, not the `grch37/` subpath — reflected in `conf/genomes.config`).
- **LOFTEE GRCh38 ancestor** `human_ancestor.fa.gz{,.fai,.gzi}` present at the Broad mirror.
- **gvanno GRCh38 bundle** — upstream `download_gvanno_refdata.py` builds `gvanno.databundle.grch38.20231224.tgz` from the same base as grch37, and gvanno's README uses `--genome_assembly grch38` as its *primary* example, so grch38 is upstream's default bundle. (The Oslo directory index is 403-forbidden, so this is confirmed by upstream's URL construction rather than a directory listing.)
- **Test fixture** `assets/example.grch38.vcf` — 11 canonical variants (BRAF V600E, JAK2 V617F, KRAS G12D, EGFR L858R, TP53 R175H, IDH1 R132H, PIK3CA E545K, NRAS Q61K, HFE C282Y, F5 Leiden, MTHFR C677T) across 9 chromosomes. Every chrom/pos/REF/ALT was verified against the Ensembl GRCh38 REST API (`rest.ensembl.org/variation/human/<rsid>`); the REF allele matches the GRCh38 reference base in each case, which is the property VEP enforces.

All of the above is now confirmed by the live run recorded at the top of this file.

### `--scatter_by chromosome` — reworked, not yet exercised
Rewritten to enumerate contigs from the validated VCF's own tabix index (`tabix -l`) instead of a reference `.fai`. The previous implementation pointed at `ref.fa.fai`, a path that never exists after `BUNDLE_PREPARE` (which stores the FASTA + `.fai` under `.vep/homo_sapiens/<ens>_<asm>/`), so scatter would have failed on **both** assemblies. The new approach needs no reference index and is assembly-agnostic. The `groupTuple` → `bcftools concat -a | bcftools sort` gather path still needs a real end-to-end test.

### Optional input index
`INPUT_CHECK` no longer requires (or carries) a `.tbi` for input VCFs — `VALIDATE_VCF` re-normalises and re-indexes everything, so a pre-existing index was never used. This lets the pipeline accept plain uncompressed `.vcf` inputs (as the GRCh38 fixture is). The `vcf_index` samplesheet column is still accepted but ignored.

### `BUNDLE_FETCH` download mode — VERIFIED
Exercised end-to-end for GRCh38 (see top of file). Two bugs were found and fixed in the process:

1. **Container entrypoint.** `curlimages/curl` declares `ENTRYPOINT ["curl"]`, so Nextflow's `bash .command.run` was passed to curl as arguments; curl reported `URL rejected: No host part in the URL` and exited 3 before running a single script line. All refdata steps now use the gvanno container (`ENTRYPOINT=null`, ships bash/curl/wget/tar/gzip) — so the whole pipeline needs exactly **one** image. This also closes the old "container choices for refdata steps" item.
2. **Where the data lands.** `BUNDLE_FETCH` now declares `storeDir params.refdata_dir`, so the bundle is written to `<refdata_dir>/data` instead of being stranded in the Nextflow work dir where `nextflow clean` would delete it.

Re-running `--step prepare_references --refdata_mode download` is now cheap: `PREPARE_REFERENCES` checks `RELEASE_NOTES` up front and skips fetch+prepare when the bundle is already staged at the requested version (verified: only `BUNDLE_VERIFY` runs, seconds instead of 25 GB). Note this idempotency check is done in Groovy — the process-level `storeDir` skip does **not** fire reliably for a directory output, so it is not relied upon.

### Nextflow 26.x compatibility
`-entry` is rejected outright by the 26.x strict parser. The pipeline uses a `--step` param instead (`annotate` | `prepare_references`), which works on every version. The strict parser also rejects `switch` in a workflow body — the dispatch uses if/else.
