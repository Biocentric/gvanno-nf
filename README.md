# ![gvanno-nf](docs/images/gvanno-nf_logo.png)

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A523.10-23aa62.svg)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

**Biocentric/gvanno-nf** is a Nextflow / nf-core style pipeline for **functional and clinical annotation of human germline DNA variants (SNVs / InDels)**.

This pipeline is **not new science**. It is an exact, samplesheet-driven re-engineering of the [**`gvanno`**](https://github.com/sigven/gvanno) workflow developed and maintained by [**Sigve Nakken**](https://github.com/sigven) and colleagues at the University of Oslo. Every annotation step, every reference data file, and every helper script that produces output here is the work of the upstream gvanno project. We have only repackaged the orchestration layer — replacing the original `gvanno.py` Docker driver with a DSL2 Nextflow workflow — so that the same scientific output can be produced with `nextflow run`, a samplesheet, and standard nf-core executor profiles.

If you use this pipeline in published work, **please cite the upstream gvanno project**. See [Credit and citation](#credit-and-citation) below.

## Pipeline summary

The pipeline accepts a CSV samplesheet of one or more single-sample germline VCFs and runs each sample through:

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

## Annotation resources (pinned to upstream gvanno 1.7.0, refdata bundle `20231224`)

These are the same resources used by upstream gvanno 1.7.0:

- [**VEP**](http://www.ensembl.org/info/docs/tools/vep/index.html) — Variant Effect Predictor v110 (GENCODE v44 / v19)
- [**dBNSFP**](https://sites.google.com/site/jpopgen/dbNSFP) — non-synonymous functional predictions, v4.5 (November 2023)
- [**gnomAD**](http://gnomad.broadinstitute.org/) — germline variant frequencies, release 2.1 (October 2018), via VEP
- [**dbSNP**](http://www.ncbi.nlm.nih.gov/SNP/) — short genetic variants, build 154, via VEP
- [**ClinVar**](http://www.ncbi.nlm.nih.gov/clinvar/) — variants and human disease phenotypes (December 2023)
- [**CancerMine**](http://bionlp.bcgsc.ca/cancermine/) — literature-mined cancer driver / oncogene / TSG database (version 50, March 2023)
- [**Mutation hotspots**](https://www.cancerhotspots.org/) — cancer mutation hotspots
- [**NHGRI-EBI GWAS Catalog**](https://www.ebi.ac.uk/gwas/home) — published GWAS associations (November 2023)
- [**ncER**](https://www.nature.com/articles/s41467-019-13212-3) — non-coding essential regulation scores

## Quick start

1. **Install** Nextflow (`>=23.10`) and Docker (or Singularity / Apptainer).

2. **Stage reference data** (one-off, ~20 GB per assembly):

   ```bash
   nextflow run Biocentric/gvanno-nf -profile docker \
       -entry PREPARE_REFERENCES \
       --genome GRCh38 \
       --refdata_dir /scratch/refs/gvanno \
       --refdata_mode download
   ```

   The bundle layout under `--refdata_dir` is **identical to upstream gvanno's**, so the same directory works for both this pipeline and the original `gvanno.py`.

3. **Write a samplesheet** (`samplesheet.csv`):

   ```
   sample,vcf,vcf_index
   patientA,/data/A.vcf.gz,/data/A.vcf.gz.tbi
   patientB,/data/B.vcf.gz,
   ```

   `vcf_index` may be left blank; the pipeline will look for `<vcf>.tbi`.

4. **Run**:

   ```bash
   nextflow run Biocentric/gvanno-nf -profile docker \
       --input samplesheet.csv \
       --genome GRCh38 \
       --refdata_dir /scratch/refs/gvanno \
       --outdir results
   ```

## Inputs

A single-sample VCF (≥ v4.2) per row in the samplesheet. Multi-allelic sites are decomposed automatically by `gvanno_validate_input.py`. We recommend bgzipping and indexing inputs with `tabix`. If your input VCF contains genotypes from multiple samples, the resulting TSV will contain one record **per sample variant**.

## Outputs

For each sample, under `results/annotation/<sample>/`:

| File | Description |
|---|---|
| `<sample>.gvanno.<assembly>.vcf.gz` (`.tbi`) | BGZF-compressed VCF with rich functional / clinical annotation INFO tags (CSQ, ClinVar, dbNSFP, gnomAD, CGC, …). |
| `<sample>.gvanno.<assembly>.pass.tsv.gz` | Tab-separated values, one row per (variant × consequence). 221 columns. Same column set as upstream gvanno's `*.pass.tsv.gz`. |
| `logs/*.vep.log`, `logs/*.vcfanno.log` | Per-step logs. |

Plus standard Nextflow execution reports under `results/pipeline_info/` (`execution_report.html`, `execution_timeline.html`, `pipeline_dag.html`, `execution_trace.txt`).

Documentation of every annotation tag is in the **header of the annotated VCF** — the column names of the TSV match the VCF INFO tag IDs.

## Tunables (mirror of upstream gvanno's CLI flags)

| Pipeline param | Upstream `gvanno.py` flag | Default |
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

Performance knobs added by this pipeline:

| Param | Effect |
|---|---|
| `--scatter_by chromosome` | Split per-contig and run VEP/vcfanno in parallel; gathered with `bcftools concat`. Default `none`. |
| `--max_cpus` / `--max_memory` / `--max_time` | Resource caps applied to all process labels. |
| `-profile slurm,awsbatch,…` | Standard Nextflow executor profiles. |

What you don't need anymore from upstream: `--container`, `--force_overwrite`, `--debug`, `--docker_uid`, `--gvanno_dir`, `--sif_file` are all subsumed by Nextflow's profile / resume / container machinery.

## Credit and citation

**The science of gvanno is not ours.** This pipeline is a thin re-orchestration of the upstream [`sigven/gvanno`](https://github.com/sigven/gvanno) project. All annotation logic, all reference data curation, all helper scripts (`gvanno_validate_input.py`, `gvanno_vep.py`, `gvanno_vcfanno.py`, `gvanno_summarise.py`, `gvanno_finalize.py`), the [`sigven/gvanno:1.7.0`](https://hub.docker.com/r/sigven/gvanno) Docker image, and the curated annotation bundle are the work of [**Sigve Nakken**](https://github.com/sigven) and colleagues at the [University of Oslo](https://www.uio.no/) and [Oslo University Hospital](https://www.ous-research.no/).

Please cite gvanno (and the underlying tools — VEP, vcfanno, dbNSFP, ClinVar, gnomAD, GENCODE, etc.) when you use this pipeline. See [`CITATIONS.md`](CITATIONS.md).

If you have questions about the **annotations themselves** (what a tag means, why a variant is classified a certain way, when a database was last updated), the right place to ask is the upstream gvanno project: <https://github.com/sigven/gvanno>, contact `sigven AT ifi.uio.no`.

If you have questions specific to the **Nextflow pipeline** (samplesheet handling, executor profiles, resume / scatter behaviour, cluster execution), open an issue on this repo: <https://github.com/Biocentric/gvanno-nf/issues>.

## Why a separate pipeline (and not a fork of `sigven/gvanno`)?

Upstream gvanno is structured as a Python script that builds and runs Docker commands. The shape of that codebase doesn't naturally fit a Nextflow refactor — DSL2 modules, samplesheets, channels, and per-process resource declarations are a different idiom. Forking would have left us either (a) carrying every upstream change manually, or (b) diverging silently. By keeping this as a separate repo that *consumes* upstream gvanno's container and reference bundle verbatim — pinned to a specific upstream version — we get clean version tracking on both sides:

- Updating gvanno to a newer release is a one-line `params.refdata_version` + container tag change here.
- Upstream gvanno can keep evolving without ever needing to think about Nextflow.

The only thing this repository contains, in terms of "science", is glue code calling upstream's helpers. Everything material is downstream of `sigven/gvanno`.

## Maintainer note: populating the GitHub Releases mirror

`params.refdata_url_base` lists `https://github.com/Biocentric/gvanno-nf/releases/download/refdata-<version>` as a fallback mirror. Until that release is populated, the URL returns 404 and `BUNDLE_FETCH` transparently falls back to the upstream Oslo mirror.

To populate it (one-shot, per refdata version):

```bash
gh auth login                                    # if not already
bash scripts/publish-refdata-mirror.sh           # both assemblies
# or:
bash scripts/publish-refdata-mirror.sh grch37    # one assembly
```

Requires `gh`, `curl`, `split`, `sha256sum`, ~10 GB free disk. Idempotent — re-running skips assets already on the release.

## Status

**v0.1.0dev** — first end-to-end run completed 2026-05-01 against the upstream example VCF (GRCh37, 8871 variants, 1 m 18 s). See [`CHANGELOG.md`](CHANGELOG.md) and [`docs/KNOWN_UNVERIFIED.md`](docs/KNOWN_UNVERIFIED.md) for the current verification state and roadmap items.

## License

This pipeline is MIT-licensed (see [`LICENSE`](LICENSE)). The MIT license covers the **Nextflow glue code** in this repository only. The `sigven/gvanno` Docker image, the gvanno annotation bundle, and the underlying tools and databases (VEP, vcfanno, dbNSFP, ClinVar, gnomAD, GENCODE, …) are governed by their own licenses — please honour those when you use this pipeline.
