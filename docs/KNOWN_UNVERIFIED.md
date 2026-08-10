# Verification state

Kept honest and current. If something here is stale, that is a bug.

Last updated: **2026-08-10**, bundle `20260810`, container
`ghcr.io/biocentric/gvanno-nf:2026.1` (VEP 115).

---

## Verified

### Track B gate — both assemblies pass

1,250-variant ClinVar panel per assembly, comparing v0.2.0 as shipped
(VEP 110 + bundle `20260801`) against v0.3.0 (VEP 115 + `20260810`). Rows joined
on variant + **gene**, since GENCODE 44→49 makes `Feature` an unstable key.

| | GRCh38 | GRCh37 |
|---|---|---|
| strict (`CLINVAR_*`, `NCER_PERCENTILE`, `GWAS_HIT`) | 0 differ | 0 differ |
| control (`Feature`/`SYMBOL`/`HGVSp_short`/`CONSEQUENCE`) | n/a — GENCODE moved | **0.08% / 0 / 0 / 0** |
| `gnomADe_AF` | 638 → 820 | 631 → 837 |
| `DBSNPRSID` | 949 → 1048 | 922 → 1033 |
| `gnomADg_AF` | 0 → 684 | n/a |
| canaries | pass | pass |

GRCh37 is the control arm: Ensembl freezes it at GENCODE 19, so its VEP 115
cache carries the same transcript set as 110 and any churn is attributable to
the container rather than the data. The single `Feature` difference is
explained in
[`refdata-builder/spec/TRACKB-GATE-RESULTS.md`](../refdata-builder/spec/TRACKB-GATE-RESULTS.md)
— VEP 115 picks the canonical/CCDS transcript where 110 picked an
alternative-5′UTR read-through, with the same protein consequence.

### Container

`LoF.pm` and `NearestExonJB.pm` both compile against the VEP 115 Perl API
inside the image. The build asserts its own contract before tagging: ten
binaries, five LOFTEE Perl modules, `pandas<3`, `VEP_VERSION == 115`, both
plugin files present, both code patches applied.

### `--refdata_mode download`

Verified on **both** assemblies against the live mirror, fresh empty
`--refdata_dir`, nothing pre-staged. The direct tarball URL 404s by design,
`BUNDLE_FETCH` falls through to `.parts.txt` and reassembles three ~1.9 GB
chunks, and `BUNDLE_VERIFY` checksums all 26 entries against a populated
manifest.

### Bundle contracts

`check_bundle.py` 18/18 on both assemblies; `check_csq_tags.sh` clean against
live VEP 115 output; manifests self-verify.

---

## Known behaviour changes

### Float representation changed ⚠️

Python 3.7 / pandas 1.x → 3.10 / pandas 2.3 changed float repr:
`97.90899999999999` now serialises as `97.909`. The values are identical.

**Diffing a v0.3.0 TSV against a v0.2.0 one shows thousands of spurious line
changes.** Compare numerically. `compare_trackb.sh` does; a plain `diff` does
not.

### `DBNSFP_*` column membership

dbNSFP v5.3 dropped `LRT`, `FATHMM`, `FATHMM_MKL_coding` and `Aloft`, so
`DBNSFP_FATHMM`, `DBNSFP_FATHMM_MKL` and `DBNSFP_ALOFTPRED` are declared but
empty. v5.3's new predictors (AlphaMissense, REVEL, CADD, ESM1b…) reach the
combined `EFFECT_PREDICTIONS` string but get no column of their own — the
container's `algo_mapping` dict fixes the emittable tag set at 17.

### `gnomADg_*` on GRCh37

Permanently empty. Ensembl carries no gnomAD **genome** data for GRCh37, only
exomes. The tag dictionary is shared between assemblies, so the tags are
declared on both.

---

## Not verified

### `--scatter_by chromosome`

Still never exercised end to end, on either assembly or either version.

### The GHCR package is private

Anonymous pulls return 403, so every `nextflow run` currently needs a registry
login. Set it public at `github.com/orgs/Biocentric/packages`.

### `check_bundle.py` validates structure, not values

`check_csq_tags.sh` now covers the CSQ tag set specifically, but the structural
checker still samples only file heads (n=200/2000) and does not validate value
grammar. That is the hole PCGR's `CUI:significance:count` ClinVar encoding
slipped through.

### Wider clinical spot-checking

The 1,250-variant panel is sampled from ClinVar and checks round-tripping and
coverage. It is not a curated clinical truth set, and no orthogonal source has
been used to confirm the annotations are *correct* rather than *consistent*.

### Housekeeping

- `nf-test` coverage: none. CI: none.
- `MULTIQC` and `BCFTOOLS_CONCAT` config selectors still match no process.
- Literal `<NA>` in `ENTREZGENE` (~118/8871 rows) — a pandas artefact from the
  container's own summarise/finalize, present in v0.2.0 too.
