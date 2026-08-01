# gvanno-nf

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A523.10-23aa62.svg)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A Nextflow (DSL2, nf-core style) pipeline for **functional and clinical annotation of human germline DNA variants (SNVs / InDels)**.

> ### Credit
>
> **This pipeline is not new science.** It is a samplesheet-driven re-engineering of the [**`gvanno`**](https://github.com/sigven/gvanno) workflow created and maintained by [**Sigve Nakken**](https://github.com/sigven) and colleagues at the [University of Oslo](https://www.uio.no/) and [Oslo University Hospital](https://www.ous-research.no/).
>
> Every annotation step, every reference database, every helper script that produces output here, and the container it all runs in are the work of the upstream gvanno project. This repository only replaces the orchestration layer — the original `gvanno.py` Docker driver — with a Nextflow workflow, so the same scientific output can be produced from a samplesheet with standard executor profiles.
>
> **If you use this pipeline in published work, cite gvanno.** See [Credit and citation](#credit-and-citation) and [`CITATIONS.md`](CITATIONS.md).

## Status

**v0.2.0** — 2026 annotation databases. `--refdata_version` now defaults to
`20260801`; pass `20231224` to reproduce a historical run. Both assemblies pass
their gates with zero drift in every VEP-derived column, and a 1,250-variant
panel produced zero wrong ClinVar IDs. Bundles are mirrored on
[the `refdata-20260801` release](https://github.com/Biocentric/gvanno-nf/releases/tag/refdata-20260801).

Not yet exercised: `--refdata_mode download` against that mirror. See
[`docs/KNOWN_UNVERIFIED.md`](docs/KNOWN_UNVERIFIED.md).

**v0.1.0dev** — both assemblies verified end to end.

| Assembly | Reference staging | Annotation | Date |
|---|---|---|---|
| **GRCh37** | pre-staged bundle | 8/8 processes ✔ — upstream gvanno example VCF, 8871 variants, 1 m 18 s | 2026-05-01 |
| **GRCh38** | 3/3 processes ✔ — fresh download, 25 GB, 29 m 50 s | 8/8 processes ✔ — 11-variant fixture, all resolved to the expected gene + protein change | 2026-07-31 |
| **GRCh38** | pre-staged, sha256-verified | 8/8 processes ✔ in ~60 s — re-run as the v0.2.0 baseline, 189 columns × 11 rows, `EFFECT_PREDICTIONS` 11/11 | 2026-08-01 |

Not yet verified: bit-identical diff against an upstream `gvanno.py` run, `--scatter_by chromosome`, nf-test coverage, CI. See [`docs/KNOWN_UNVERIFIED.md`](docs/KNOWN_UNVERIFIED.md) — it is kept honest and current.

## Pipeline summary

```
                   ┌──────────────────────┐
samplesheet.csv ─► │  INPUT_CHECK         │
                   └─────────┬────────────┘
                             ▼
                   ┌──────────────────────┐
                   │  PREPARE_REFERENCES  │  prestaged | download
                   └─────────┬────────────┘
                             ▼
                   ┌──────────────────────┐
                   │  VALIDATE_VCF        │  gvanno_validate_input.py
                   └─────────┬────────────┘
                             ▼
              (optional) SCATTER_VCF (--scatter_by chromosome)
                             ▼
                   ┌──────────────────────┐
                   │  VEP                 │  Ensembl VEP 110 (+ LOFTEE / NearestExonJB / UTRannotator)
                   └─────────┬────────────┘
                             ▼
                   ┌──────────────────────┐
                   │  VCFANNO             │  ClinVar / dbNSFP / gnomAD / GWAS / ncER
                   └─────────┬────────────┘
                             ▼
                   ┌──────────────────────┐
                   │  SUMMARISE           │  gvanno_summarise.py (consequence consolidation)
                   └─────────┬────────────┘
                             ▼
                       CONCAT_VCFS  (no-op when not scattered)
                             ▼
                   ┌──────────────────────┐
                   │  VCF2TSV             │  vcf2tsvpy (PASS + all-variants)
                   └─────────┬────────────┘
                             ▼
                   ┌──────────────────────┐
                   │  FINALIZE_TSV        │  gvanno_finalize.py (ClinVar traits, gene symbols, domains)
                   └──────────────────────┘
```

Every process runs in a single container, `sigven/gvanno:1.7.0` — the same image upstream gvanno uses. There is nothing else to install.

## Requirements

- **Nextflow** ≥ 23.10 (tested on 25.04 and 26.04)
- **Docker**, Singularity, or Apptainer
- **Disk**: ~25 GB for a staged GRCh38 bundle, and **~45 GB peak** during setup (the 20 GB VEP cache tarball and its extraction briefly coexist). GRCh37 is smaller — its VEP cache is 13 GB rather than 20 GB. Point `--refdata_dir` at a volume with real headroom.

> **Nextflow 26.x users:** use `--step prepare_references`, not `-entry`. The 26.x strict parser rejects the `-entry` CLI option outright. `--step` works on every Nextflow version.

## Quick start

**1. Stage the reference bundle** (one-off, ~25 GB):

```bash
nextflow run Biocentric/gvanno-nf -r main -latest -profile docker \
    --step prepare_references \
    --genome GRCh38 \
    --refdata_dir /data/refs/gvanno-grch38 \
    --refdata_mode download
```

This downloads the gvanno annotation bundle, the Ensembl VEP 110 cache, and the reference FASTA, then re-encodes the FASTA to BGZF and indexes it. The resulting layout is **identical to upstream gvanno's**, so the same directory works for both this pipeline and the original `gvanno.py`.

Re-running this is cheap: if the bundle is already staged at the requested version, the download is skipped.

**2. Write a samplesheet** (`samplesheet.csv`):

```csv
sample,vcf,vcf_index
patientA,/data/A.vcf.gz,
patientB,/data/B.vcf,
```

**3. Annotate:**

```bash
nextflow run Biocentric/gvanno-nf -r main -latest -profile docker \
    --input samplesheet.csv \
    --genome GRCh38 \
    --refdata_dir /data/refs/gvanno-grch38 \
    --outdir results
```

> `-latest` matters when running straight from GitHub — Nextflow caches the repo under `~/.nextflow/assets/` and will otherwise re-run whatever revision it cached first.

## Input

One single-sample germline VCF (≥ v4.2) per samplesheet row.

| Column | Required | Notes |
|---|---|---|
| `sample` | yes | Unique ID, used to name outputs. Must match `[A-Za-z0-9._-]+`. |
| `vcf` | yes | Path or URL to the VCF. Plain `.vcf` and bgzipped `.vcf.gz` both work. |
| `vcf_index` | no | Accepted but **ignored** — `VALIDATE_VCF` re-normalises and re-indexes every input, so a pre-existing `.tbi` is never used. |

Multi-allelic sites are decomposed automatically. If a VCF contains genotypes for multiple samples, the output TSV carries one record **per sample variant**.

## Output

```
results/
├── annotation/<sample>/
│   ├── <sample>.gvanno.<assembly>.pass.tsv.gz     # PASS variants, finalised TSV
│   └── logs/{*.vep.log, *.vcfanno.log}
├── concat_vcfs/
│   └── <sample>.gvanno.<assembly>.vcf.gz(.tbi)    # annotated VCF
└── pipeline_info/                                  # Nextflow execution reports
```

| File | Description |
|---|---|
| `*.vcf.gz` (`.tbi`) | BGZF-compressed VCF with the full functional / clinical annotation INFO tags (CSQ, ClinVar, dbNSFP, gnomAD, CGC, …). |
| `*.pass.tsv.gz` | Tab-separated, one row per (variant × consequence). Same column set as upstream gvanno's `*.pass.tsv.gz`; the exact count (~190–220) depends on how many INFO tags your input VCF carries through. |

Every annotation tag is documented in the **header of the annotated VCF** — the TSV column names match the VCF INFO tag IDs.

## Parameters

### Core

| Param | Default | Description |
|---|---|---|
| `--input` | — | Samplesheet CSV (required for `--step annotate`) |
| `--outdir` | `./results` | Output directory |
| `--genome` | `GRCh38` | `GRCh37` or `GRCh38` |
| `--step` | `annotate` | `annotate` or `prepare_references` |

### Reference data

| Param | Default | Description |
|---|---|---|
| `--refdata_dir` | — | Bundle location (source when prestaged, destination when downloading). Required. |
| `--refdata_mode` | `prestaged` | `prestaged` or `download` |
| `--refdata_version` | `20231224` | Bundle version, pinned to upstream gvanno 1.7.0 |
| `--refdata_url_base` | Oslo, then GitHub Releases | Ordered mirror list, tried in turn |

### VEP — mirrors upstream gvanno's flags exactly

| Param | Upstream `gvanno.py` flag | Default |
|---|---|---|
| `--vep_n_forks` | `--vep_n_forks` | 4 |
| `--vep_buffer_size` | `--vep_buffer_size` | 500 |
| `--vep_pick_order` | `--vep_pick_order` | `mane_select,mane_plus_clinical,canonical,appris,tsl,biotype,ccds,rank,length` |
| `--vep_regulatory` | `--vep_regulatory` | false |
| `--vep_gencode_basic` | `--vep_gencode_basic` | false |
| `--vep_lof_prediction` | `--vep_lof_prediction` | false |
| `--vep_no_intergenic` | `--vep_no_intergenic` | false |
| `--vep_coding_only` | `--vep_coding_only` | false |
| `--vcfanno_n_processes` | `--vcfanno_n_processes` | 4 |
| `--oncogenicity_annotation` | `--oncogenicity_annotation` | false (requires `--vep_lof_prediction`) |

### Added by this pipeline

| Param | Effect |
|---|---|
| `--scatter_by chromosome` | Split per contig and run VEP/vcfanno in parallel, gathered with `bcftools concat`. Default `none`. |
| `--keep_intermediates` | Retain intermediate VCFs and logs |
| `--max_cpus` / `--max_memory` / `--max_time` | Resource caps applied to all process labels |
| `-profile docker,singularity,apptainer,conda,slurm,…` | Standard Nextflow executor/container profiles |

Upstream's `--container`, `--force_overwrite`, `--debug`, `--docker_uid`, `--gvanno_dir` and `--sif_file` have no equivalent here — Nextflow's profile, `-resume` and container machinery replace them.

## Annotation resources

Currently pinned to upstream gvanno 1.7.0, reference bundle `20231224`:

| Resource | Version | Enters via |
|---|---|---|
| [**VEP**](http://www.ensembl.org/info/docs/tools/vep/index.html) | v110 (GENCODE v44 / v19) | container + cache |
| [**gnomAD**](http://gnomad.broadinstitute.org/) | r2.1 (October 2018) | VEP cache |
| [**dbSNP**](http://www.ncbi.nlm.nih.gov/SNP/) | build 154 | VEP cache |
| [**ClinVar**](http://www.ncbi.nlm.nih.gov/clinvar/) | December 2023 | bundle (vcfanno) |
| [**dbNSFP**](https://www.dbnsfp.org/) | v4.5 (November 2023) | bundle (vcfanno) |
| [**NHGRI-EBI GWAS Catalog**](https://www.ebi.ac.uk/gwas/home) | November 2023 | bundle (vcfanno) |
| [**ncER**](https://www.nature.com/articles/s41467-019-13212-3) | v1.0 (March 2019) | bundle (vcfanno) |
| [**Cancer Hotspots**](https://www.cancerhotspots.org/) | v2 (2017) | bundle (summarise) |
| [**CancerMine**](http://bionlp.bcgsc.ca/cancermine/) | v50 (March 2023) | bundle (gene xref) |
| [**Pfam**](https://www.ebi.ac.uk/interpro/) | v36.0 | bundle (protein domains) |
| [**UniProt**](https://www.uniprot.org/) | release 2023_05 | bundle (gene xref) |

### Bringing these to 2026 — work in progress on `0.2.0`

**Upstream gvanno is frozen.** Its last release was v1.7.0 (2023-12-29) and its
last commit 2024-02-13, so `20231224` is the final bundle upstream will ever
publish. Re-pinning to a newer upstream version is not an option — there is no
newer version. To move the databases forward, this project has to produce the
bundle itself.

That work is split into two tracks:

| | **Track A** → `v0.2.0` | **Track B** → `v0.3.0` |
|---|---|---|
| Container | `sigven/gvanno:1.7.0`, unchanged | rebuilt on VEP 115 |
| Updates | ClinVar, dbNSFP, GWAS Catalog, Cancer Hotspots, CancerMine, Pfam, gene xref | + GENCODE 49, gnomAD v4.1, dbSNP b156 |

The split follows a real seam in the design: five resources are plain data
files that vcfanno reads, and the gvanno helpers do **no** version checking on
the bundle — so they can be replaced under the existing container. The rest
ride on the VEP cache, which is welded to the container by `gvanno_vep.py`'s
`--cache_version`, and cannot move without rebuilding the image.

Track A targets ClinVar 2026, dbNSFP v5.3.1, GWAS Catalog 2026, Cancer Hotspots
v3, CancerMine v51 and a refreshed gene/transcript xref. ncER stays at v1.0 —
no newer release exists.

**Status: bundle `20260801` builds and passes the validation gate on GRCh38.**
What it contains:

| Resource | `20231224` | `20260801` | Source |
|---|---|---|---|
| ClinVar | 2023-12 | **2026-07-28** | NCBI, direct |
| dbNSFP | v4.5 | **v5.3** | PCGR 2.3 donor |
| Cancer Hotspots | v2 (2017) | **v3 (2026)** | PCGR 2.3 donor |
| GWAS Catalog | 2023-11 | **2026** | PCGR 2.3 donor |
| Pfam | v36.0 | **2026** | PCGR 2.3 donor |
| Cancer Gene Census | — | **v101 (2025)** | PCGR 2.2 bundle |
| MIM phenotypes | 3,853 genes | **5,271 genes** | NCBI `mim2gene_medgen` ∪ prior |
| Gene/transcript xref | Ensembl 110 | **GENCODE 49** | PCGR 2.3, remapped |
| ncER | v1.0 (2019) | v1.0 — carried forward | no newer release exists |
| VEP · GENCODE · gnomAD · dbSNP | 110 · v44 · r2.1 · b154 | *unchanged* | Track B |

**Every source is account-free.** COSMIC (Cancer Gene Census) and OMIM
(`genemap2`) both gate downloads behind registration; the builder avoids them
by lifting CGC from the PCGR 2.2-era bundle — PCGR 2.3 dropped those fields —
and taking MIM from NCBI, which needs no account and covers more genes. The
builder therefore runs unattended, with no stored credentials.

Three findings worth carrying forward, each of which cost a build cycle:

- **The `DBNSFP` tag is half self-describing.** `dbnsfp.py` reads the
  *predictor list* at runtime from the tag's `Format:` string, but maps each
  one to an output tag through a **hardcoded 17-entry dict** — `gerp_rs` →
  `DBNSFP_GERP`, not `DBNSFP_GERP_RS`. So the emittable tag set is fixed by the
  container. v5.3's new predictors (AlphaMissense, REVEL, CADD, ESM1b…) still
  reach the combined `EFFECT_PREDICTIONS` string; they just get no column of
  their own until Track B.
- **PCGR's ClinVar is not safe for a germline pipeline.** The gate caught
  F5 p.R534Q — Factor V Leiden, expert-panel Pathogenic — missing from it.
  ClinVar is now built from NCBI directly.
- **Both failure modes are silent.** A dbNSFP field-count mismatch empties
  every prediction while the run still succeeds. `refdata-builder/verify/check_bundle.py`
  asserts these at build time rather than hoping a smoke test notices.

See [`refdata-builder/spec/`](refdata-builder/spec/) for the format contract,
the [donor assessment](refdata-builder/spec/DONOR-ASSESSMENT.md), and the
[baseline and gate criteria](refdata-builder/spec/BASELINE.md).

## Testing

```bash
# GRCh37 — upstream gvanno example VCF (8871 variants)
nextflow run Biocentric/gvanno-nf -profile docker,test \
    --refdata_dir /data/refs/gvanno-grch37

# GRCh38 — committed 11-variant fixture
nextflow run Biocentric/gvanno-nf -profile docker,test_grch38 \
    --refdata_dir /data/refs/gvanno-grch38
```

Both expect the matching bundle already staged. The GRCh38 fixture ([`assets/example.grch38.vcf`](assets/example.grch38.vcf)) holds 11 canonical variants across 9 chromosomes; every coordinate and reference allele was verified against the Ensembl GRCh38 REST API, and the last run annotated each to the expected gene and protein change:

| Variant | Expected | | Variant | Expected |
|---|---|---|---|---|
| 1:11796321 G>A | MTHFR p.A222V | | 7:55191822 T>G | EGFR p.L858R |
| 1:114713909 G>T | NRAS p.Q61K | | 7:140753336 A>T | BRAF p.V600E |
| 1:169549811 C>T | F5 p.R534Q | | 9:5073770 G>T | JAK2 p.V617F |
| 2:208248388 C>T | IDH1 p.R132H | | 12:25245350 C>T | KRAS p.G12D |
| 3:179218303 G>A | PIK3CA p.E545K | | 17:7675088 C>T | TP53 p.R175H |
| 6:26092913 G>A | HFE p.C282Y | | | |

F5 is reported as `p.R534Q`; the familiar "Factor V Leiden R506Q" is the same variant numbered on the mature protein rather than the HGVS precursor. MTHFR `p.A222V` is the protein-level name for the well-known `c.677C>T`.

## Credit and citation

**The science of gvanno is not ours.** All annotation logic, all reference data curation, all helper scripts (`gvanno_validate_input.py`, `gvanno_vep.py`, `gvanno_vcfanno.py`, `gvanno_summarise.py`, `gvanno_finalize.py`), the [`sigven/gvanno:1.7.0`](https://hub.docker.com/r/sigven/gvanno) Docker image, and the curated annotation bundle are the work of [**Sigve Nakken**](https://github.com/sigven) and colleagues at the University of Oslo and Oslo University Hospital.

Please cite gvanno — and the underlying tools (VEP, vcfanno, dbNSFP, ClinVar, gnomAD, GENCODE, …) — when you use this pipeline. Full reference list in [`CITATIONS.md`](CITATIONS.md).

**Where to ask questions:**

- About the **annotations themselves** — what a tag means, why a variant is classified a certain way, when a database was last updated → the upstream project: <https://github.com/sigven/gvanno> (`sigven AT ifi.uio.no`).
- About the **Nextflow pipeline** — samplesheets, executor profiles, resume/scatter behaviour, cluster execution → [issues on this repo](https://github.com/Biocentric/gvanno-nf/issues).

## Why a separate repo, not a fork?

Upstream gvanno is a Python script that builds and runs Docker commands. That shape doesn't map onto a Nextflow refactor — DSL2 modules, samplesheets, channels and per-process resource declarations are a different idiom, so a fork would have meant either hand-carrying every upstream change or diverging silently.

Keeping this separate, and *consuming* upstream's container and reference bundle verbatim at a pinned version, gives clean version tracking on both sides:

- Moving to a newer gvanno is a one-line change to `params.refdata_version` and the container tag.
- Upstream gvanno never has to think about Nextflow.

In terms of science, this repository contains only glue code calling upstream's helpers. Everything material is downstream of `sigven/gvanno`.

## Maintainer note: the GitHub Releases mirror

`params.refdata_url_base` lists `https://github.com/Biocentric/gvanno-nf/releases/download/refdata-<version>` as a fallback mirror. Until that release is populated the URL 404s and `BUNDLE_FETCH` falls through to the upstream Oslo mirror, so nothing breaks.

To populate it (one-shot per refdata version):

```bash
gh auth login
bash scripts/publish-refdata-mirror.sh            # both assemblies
bash scripts/publish-refdata-mirror.sh grch38     # or just one
```

Needs `gh`, `curl`, `split`, `sha256sum` and ~10 GB free disk. The bundle is split into ≤2 GB chunks (GitHub's per-asset cap) with a `.parts.txt` manifest that `BUNDLE_FETCH` reassembles transparently. Idempotent — re-running skips assets already uploaded.

## License

MIT (see [`LICENSE`](LICENSE)) — covering the **Nextflow glue code in this repository only**. The `sigven/gvanno` Docker image, the gvanno annotation bundle, and the underlying tools and databases (VEP, vcfanno, dbNSFP, ClinVar, gnomAD, GENCODE, …) are governed by their own licenses. Please honour those when you use this pipeline.
