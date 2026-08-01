# Phase 0.5 — baseline run against bundle `20231224`

The reference the Phase 2 validation gate diffs against. Re-run this exact
command after the bundle rebuild and compare.

```
host        hephaestus (192.168.50.62)
date        2026-08-01T17:21:59+02:00
nextflow    26.04.3
container   sigven/gvanno:1.7.0   (unchanged)
bundle      20231224              (upstream, sha256-verified)
vep cache   homo_sapiens_vep_110_GRCh38  (21 GB incl. FASTA)
profile     docker,test_grch38
runtime     ~60 s, 8/8 processes, exit 0
```

```bash
nextflow run . -profile docker,test_grch38 \
    --refdata_dir /mnt/big/gvanno-build/ref-20231224 \
    --outdir      /mnt/big/gvanno-build/baseline-grch38 \
    -w            /mnt/big/gvanno-build/work \
    -ansi-log false
```

Output kept at
`/mnt/big/gvanno-build/baseline-grch38/annotation/example_grch38/example_grch38.gvanno.GRCh38.pass.tsv.gz`.

## Shape

| | |
|---|---|
| columns | **189** |
| data rows | **11** (one per fixture variant, all single-consequence) |

189 rather than 221: the column count tracks the input VCF's INFO tags, and the
fixture is minimal. Not a defect — see the v0.1.0dev CHANGELOG entry.

## Every fixture variant resolved as intended

| CHROM | POS | SYMBOL | HGVSp_short | Consequence |
|---|---|---|---|---|
| 1 | 11796321 | MTHFR | p.A222V | missense_variant |
| 1 | 114713909 | NRAS | p.Q61K | missense_variant |
| 1 | 169549811 | F5 | p.R534Q | missense_variant |
| 2 | 208248388 | IDH1 | p.R132H | missense_variant |
| 3 | 179218303 | PIK3CA | p.E545K | missense_variant |
| 6 | 26092913 | HFE | p.C282Y | missense_variant |
| 7 | 55191822 | EGFR | p.L858R | missense_variant |
| 7 | 140753336 | BRAF | p.V600E | missense_variant |
| 9 | 5073770 | JAK2 | p.V617F | missense_variant |
| 12 | 25245350 | KRAS | p.G12D | missense_variant |
| 17 | 7675088 | TP53 | p.R175H | missense_variant |

F5 Leiden appears as `p.R534Q` — the MANE full-length numbering of the variant
usually cited as R506Q in legacy mature-protein coordinates. Correct.

## Annotation coverage

| Column | Populated |
|---|---|
| `SYMBOL` | 11/11 |
| `EFFECT_PREDICTIONS` | **11/11** |
| `CLINVAR_MSID` | 11/11 |
| `CLINVAR_CLASSIFICATION` | 11/11 |
| `DBSNPRSID` | 11/11 |
| `NCER_PERCENTILE` | 11/11 |
| `DBNSFP_SIFT` | 9/11 |
| `DBNSFP_PROVEAN` | 9/11 |
| `gnomADe_AF` | 9/11 |
| `GWAS_HIT` | 0/11 |

`GWAS_HIT` at 0/11 is expected — these are clinical/somatic hotspot variants,
not GWAS lead SNPs. The two variants missing dbNSFP and gnomAD entries are
likewise unremarkable for a fixture of rare pathogenic alleles.

## Baseline `EFFECT_PREDICTIONS` (first record)

```
sift:D, lrt:D, mutationtaster:PD, mutationassessor:D, fathmm:D,
fathmm_mkl_coding:D, provean:D, m-cap:NA, mutpred:NA, gerp_rs:5.08,
primateai:T, deogen2:…
```

Note `lrt`, `fathmm` and `fathmm_mkl_coding` — three of the four predictors
dbNSFP v5.3 removes. Their disappearance after the rebuild is **expected
drift**, not a regression.

## Gate criteria for Phase 2

Re-run against bundle `20260801` and require:

| Check | Expectation |
|---|---|
| process count / exit | 8/8, exit 0 |
| data rows | **exactly 11** — VEP is unchanged in Track A, so no row may appear or vanish |
| VEP-derived columns | **zero drift** — `SYMBOL`, `HGVSp_short`, `Consequence`, `gnomADe_AF`, `DBSNPRSID`, `Feature`, … must match byte for byte. Any change means the bundle rebuild corrupted something. |
| `NCER_PERCENTILE` | **zero drift** — carried forward verbatim |
| `EFFECT_PREDICTIONS` | **11/11 populated** — the canary for the silent dbNSFP count mismatch |
| `DBNSFP_*` membership | **expected to change** — `lrt`/`fathmm`/`fathmm_mkl_coding`/`aloft` drop out, ~10 new predictors appear |
| `CLINVAR_*` | populated 11/11; values expected to drift (2.5 years of reclassification) |
| spot check | BRAF V600E, F5 Leiden, HFE C282Y, MTHFR C677T vs the ClinVar web UI |
