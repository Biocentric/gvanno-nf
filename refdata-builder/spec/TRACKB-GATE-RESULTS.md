# Track B gate — VEP 110 → 115

Run 2026-08-10 on hephaestus. 1,250-variant ClinVar panel per assembly
(250 per tier, one variant per gene), sampled from the **20260801** ClinVar so
every variant is known to have been annotatable before the upgrade.

| | Arm A | Arm B |
|---|---|---|
| container | `sigven/gvanno:1.7.0` | `ghcr.io/biocentric/gvanno-nf:2026.1` |
| VEP | 110 | **115** |
| bundle | `20260801` | `20260810` |

Rows joined on **variant + gene**, not variant + transcript — GENCODE 44 → 49
roughly doubles the transcript set, so `Feature` is precisely what moves.

## Result: PASSED on both assemblies

### GRCh37 is the control arm, and it is the load-bearing result

Ensembl freezes GRCh37 at GENCODE 19, so its VEP 115 cache carries the *same*
transcript set as 110. Any churn there is attributable to the container
rebuild rather than to data.

| | differ | |
|---|---|---|
| `Feature` | 1 / 1246 | 0.08% |
| `SYMBOL` | 0 / 1246 | 0.00% |
| `HGVSp_short` | 0 / 1246 | 0.00% |
| `CONSEQUENCE` | 0 / 1246 | 0.00% |

Contrast the variant × gene key sets: GRCh38 has **93 only-old / 93 only-new**
(GENCODE churn); GRCh37 has **4 / 4**. Holding GENCODE constant, swapping VEP
110 for 115 changes essentially nothing.

That separates the two questions the GRCh38 arm cannot: *does VEP 115 behave
correctly* (GRCh37, yes) versus *is the new data better* (GRCh38, below).

### The upgrade delivers

| | GRCh38 | GRCh37 |
|---|---|---|
| `gnomADe_AF` | 638 → **820** (+182) | 631 → **837** (+206) |
| `DBSNPRSID` | 949 → **1048** (+99) | 922 → **1033** (+111) |
| `gnomADg_AF` | 0 → **684** | n/a — Ensembl has no gnomAD genomes for GRCh37 |

Roughly a **30% increase** in variants receiving a population frequency, and
`gnomADg_AF` populated for the first time in any release of this pipeline —
`--af_gnomad` only ever requested exomes, so the 11 `gnomADg_*` tags the bundle
declared had always been empty. That is the `--af_gnomadg` patch working.

**This resolves the B5 decision.** The concern was that the VEP cache only
carries frequencies for variants dbSNP has accessioned, and the 115 cache is on
b156 while gnomAD v4.1 postdates it — so the realised gain might be far smaller
than the 125k → 731k exome jump implies. It is smaller, but it is substantial
and clearly worth the container work.

### Strict and canary checks

| | GRCh38 | GRCh37 |
|---|---|---|
| `CLINVAR_MSID` | 0 differ | 0 differ |
| `CLINVAR_CLASSIFICATION` | 0 differ | 0 differ |
| `NCER_PERCENTILE` | 0 differ | 0 differ |
| `GWAS_HIT` | 0 differ | 0 differ |
| `EFFECT_PREDICTIONS` populated | 788 rows | 868 rows |
| `CLINVAR_CLNSIG` grammar | plain | plain |

## Two findings worth carrying forward

### Float repr changed, and it will show up in every diff

The first GRCh38 run **failed** on `NCER_PERCENTILE`, 36/1157 differing. The
ncER file is byte-identical between the two bundles — same sha256 in both
committed manifests — and the differences were:

```
arm A  97.90899999999999      arm B  97.909
arm A  98.93700000000001      arm B  98.937
```

Python 3.7 / pandas 1.x versus 3.10 / pandas 2.3. Identical values, different
strings. The gate was comparing strings, so it reported data corruption on data
that had not changed.

The gate now compares numerically where both sides parse as numbers (1e-6
relative tolerance) and reports how many differences were formatting-only
rather than hiding them. 36 such on GRCh38, 29 on GRCh37.

> **Downstream impact:** anyone `diff`ing a v0.3.0 TSV against a v0.2.0 one will
> see thousands of spurious line changes from this alone. It is cosmetic, but it
> is not invisible.

### The one GRCh37 Feature difference — explained, and it is an improvement

`14:21161830 A>T`, ANG / RNASE4 locus.

| | arm A (VEP 110) | arm B (VEP 115) |
|---|---|---|
| picked transcript | `ENST00000397990` | `ENST00000336811` |
| `CANONICAL` | `.` | **YES** |
| `PRINCIPAL_ISOFORM_FLAG` | `.` | **PRINCIPAL:1** |
| GENCODE tags | `alternative_5_UTR&basic&…&read…` | `basic&appris_principal&CCDS` |
| HGVSc | `c.107A>T` | `c.107A>T` |
| **HGVSp** | **p.Gln36Leu** | **p.Gln36Leu** |

The protein consequence is identical. VEP 115 picked the canonical,
APPRIS-principal, CCDS transcript where 110 picked an alternative-5′UTR
read-through. gvanno's `--pick_order` is
`mane_select,mane_plus_clinical,canonical,appris,…`, and GRCh37 has no MANE to
outrank `canonical`, so this is Ensembl's revised canonical-transcript
designation propagating through — a strictly better pick with the same biology.

Not a defect, and nothing to fix. Worth knowing that GRCh37 transcript picks
can shift on the canonical criterion even with GENCODE frozen at 19.

## Reproducing

```bash
refdata-builder/verify/compare_trackb.sh <armA.pass.tsv.gz> <armB.pass.tsv.gz> GRCh38
```

Panels are seeded, so `make_check_panel.py` reproduces the same 1,250 variants.
