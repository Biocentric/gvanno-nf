# Verification state

Kept honest and current. If something here is stale, that is a bug.

Last updated: **2026-08-10**, bundle `20260810`, container
`ghcr.io/biocentric/gvanno-nf:2026.2` (VEP 115).

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

Re-run end to end on the shipped default `20260810`, GRCh38, from clean:

```
BUNDLE_FETCH    45m 2s  exit 0   (chunked path, 3 parts)
BUNDLE_PREPARE   7m 44s exit 0   (FASTA re-encoded BGZF, .fai + .gzi built)
BUNDLE_VERIFY     26.6s exit 0   26/26 sha256 OK
staged 30 GB   published outdir 1.9 MB
```

The published-outdir figure is the check on the `publishDir` fix: before it,
download mode republished the whole 26 GB tree and cost double the disk.

**Downloading a tree is not the same as the tree being usable**, so that is
checked separately. Annotating the fixture against the downloaded tree — in
`prestaged` mode so nothing can be re-fetched, and pointed at a different
directory from the locally built one so a silent fallback would show — produces
output **byte-identical** to the locally built tree, 11 rows x 190 columns,
after normalising the sample id. What the mirror serves is functionally the
bundle that was built, not merely one with matching checksums.

### End-to-end with shipped defaults

Run on hephaestus with **no overrides** — exactly the config a user gets:
`ghcr.io/biocentric/gvanno-nf:2026.2`, bundle `20260810`, 11-variant fixture.
8/8 processes, 190 columns × 11 rows, every variant resolved to the expected
gene and protein change.

Population frequencies are biologically sensible, which is a useful
independent sanity signal: F5 Leiden `gnomADe_AF` 0.0219, HFE C282Y 0.0590,
MTHFR C677T 0.3227 — all consistent with known European frequencies.
`gnomADg_AF` populated on 7/11.

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

### ~~`--scatter_by chromosome`~~ — VERIFIED 2026-08-10, after fixing a serious bug

Now correct, but it was badly broken until tested. On a 1,250-variant panel
across 24 contigs it produced **134 rows instead of 1,250** — exactly the chr1
count — because only one shard was annotated and the other 23 were silently
discarded, with exit 0 and a well-formed output file.

`prepare_references.nf` emitted `refdata_dir` and `vep_cache` as queue channels
holding one element (`.combine()` demotes a value channel). Nextflow zips
process inputs positionally and stops at the shortest, so
`VEP(<24 shards>, <1>, <1>)` ran exactly one task. Fixed with `.first()`.

It could only fail when used — with `scatter_by=none` there is one shard, so
the mismatch never bites — and it had never been used, having shipped from
v0.1.0dev through v0.2.0 as a documented but unexercised feature.

After the fix: 24 VEP / 24 VCFANNO / 24 SUMMARISE tasks, 1,250 rows, and output
byte-identical to the unscattered run after sorting.

Verified across three cells of the assembly x branch matrix, each 24 shards /
1250 rows / byte-identical after sorting:

| Assembly | Code | Container | VEP |
|---|---|---|---|
| GRCh38 | 0.3.0 | `2026.1` | 115 |
| GRCh37 | 0.2.0 | `sigven/gvanno:1.7.0` | 110 |
| GRCh37 | 0.3.0 | `2026.2` | 115 |

The 0.2.0 row mattered because every earlier run used 0.3.0 code with the VEP
115 container, and the 2026.2 row because that is the tag the pipeline now
defaults to. The remaining cell, GRCh38 x 0.2.0, is the combination the
original bug was found on and so is the one already known to be fixed.

### The GHCR package is private — but the reason is gone

Anonymous pulls return 403, so a registry login is still needed until the
visibility is flipped.

It was held private because the image bakes in gvanno helper scripts and
upstream had no licence. **That is resolved**: `sigven/gvanno` is MIT as of
`b25acdf` (2026-08-11), the source is now vendored, and `LICENSE.md` ships
inside the image. Nothing blocks making it public.

GitHub has **no REST endpoint** for package visibility — `PATCH
/user/packages/container/gvanno-nf` returns 404 — so it is a UI-only action:
<https://github.com/users/Biocentric/packages/container/gvanno-nf/settings>.

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
